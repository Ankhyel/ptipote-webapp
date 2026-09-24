const admin = require("firebase-admin");
const {Timestamp} = require("firebase-admin/firestore");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {
  buildWorldbuildingMap,
  runtimeConfig: worldbuildingRuntimeConfig,
  stableSeed: worldbuildingStableSeed,
} = require("./worldbuilding_v2");
const {
  ECOLOGY_VERSION,
  runtimeConfig: ecologyRuntimeConfig,
  ecologyDefaults,
  calculateBiomass,
  resolveBiomeEcology,
  addWasteDeposit,
  qualitativeEcology,
  number: ecologyNumber,
  clamp: ecologyClamp,
} = require("./ecology_v2");

admin.initializeApp();

exports.sendPushForNotification = onDocumentCreated(
  {
    document: "users/{userId}/notifications/{notificationId}",
    region: "europe-west9",
  },
  async (event) => {
    const userId = event.params.userId;
    const notification = event.data && event.data.data();

    if (!notification) return;
    const notificationRef = event.data.ref;

    const tokensSnapshot = await admin
      .firestore()
      .collection("users")
      .doc(userId)
      .collection("fcmTokens")
      .get();

    const tokens = tokensSnapshot.docs
      .map((doc) => `${doc.data().token || doc.id}`.trim())
      .filter(Boolean);

    if (tokens.length === 0) {
      await notificationRef.set(
        {
          pushStatus: "no_tokens",
          pushSuccessCount: 0,
          pushFailureCount: 0,
          pushErrors: [],
          pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return;
    }

    const payload = {
      notification: {
        title: `${notification.title || "PTIPOTE"}`,
        body: `${notification.body || ""}`,
      },
      data: stringifyData({
        notificationId: event.params.notificationId,
        type: notification.type || "",
        ...(notification.data || {}),
      }),
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    let response;
    try {
      response = await admin.messaging().sendEachForMulticast({
        tokens,
        ...payload,
      });
    } catch (error) {
      await notificationRef.set(
        {
          pushStatus: "error",
          pushFailureCount: tokens.length,
          pushErrors: [
            {
              code: error.code || "unknown",
              message: error.message || `${error}`,
            },
          ],
          pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      throw error;
    }
    const pushErrors = response.responses
      .filter((result) => !result.success)
      .slice(0, 5)
      .map((result) => ({
        code: (result.error && result.error.code) || "unknown",
        message: (result.error && result.error.message) || "",
      }));

    const batch = admin.firestore().batch();
    batch.set(
      notificationRef,
      {
        pushStatus: response.failureCount === 0 ? "sent" : "partial",
        pushSuccessCount: response.successCount,
        pushFailureCount: response.failureCount,
        pushErrors,
        pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = result.error && result.error.code;
      const shouldDelete =
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token";
      if (!shouldDelete) return;
      batch.delete(tokensSnapshot.docs[index].ref);
    });
    await batch.commit();
  },
);

// The game simulation is normally persisted by the app, but an iPhone that is
// closed cannot display an in-app warning. This server-side check turns the
// latest saved urgent needs into a notification document, which is then sent by
// the trigger above. Deterministic ids keep one push per need and per hour.
exports.notifySavedPtipoteNeeds = onSchedule(
  {schedule: "every 30 minutes", region: "europe-west9"},
  async () => {
    const games = await admin
      .firestore()
      .collectionGroup("game")
      .where(admin.firestore.FieldPath.documentId(), "==", "zone0")
      .get();
    const hour = new Date().toISOString().slice(0, 13).replace(/[-T:]/g, "");
    const writes = [];
    for (const game of games.docs) {
      const data = game.data();
      const userDoc = game.ref.parent.parent;
      if (!userDoc) continue;
      const uid = userDoc.id;
      const [figurines] = await Promise.all([
        userDoc.collection("figurines").get(),
      ]);
      const names = new Map(figurines.docs.map((doc) => [doc.id, `${doc.data().fields?.s || doc.data().displayName || "P’TIPOTE"}`]));
      const checks = [
        ["hungerOverrides", 20, "faim", "a faim et attend un repas."],
        ["restOverrides", 15, "repos", "a besoin de dormir."],
        ["vitalityOverrides", 10, "energie", "est épuisé et a besoin de repos."],
      ];
      for (const [field, threshold, type, sentence] of checks) {
        const values = data[field] || {};
        for (const [figurineId, value] of Object.entries(values)) {
          if (Number(value) > threshold) continue;
          const name = names.get(figurineId) || "Un P’TIPOTE";
          const ref = userDoc.collection("notifications").doc(`need-${figurineId}-${type}-${hour}`);
          writes.push(ref.create({
            recipientUid: uid,
            senderUid: "system",
            type: "ptipote_need",
            title: `${name} a besoin de toi`,
            body: `${name} ${sentence}`,
            read: false,
            data: {figurineId, needType: type, value: Number(value)},
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }).catch((error) => {
            if (error.code !== 6) throw error; // already notified this hour
          }));
      }
    }
    }
    await Promise.all(writes);
  },
);

function stringifyData(data) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, `${value ?? ""}`]),
  );
}

const WORLDCRAFT_DEFAULT_CONFIG = Object.freeze({
  traceLifetimeHours: 24,
  campActiveGraceMinutes: 15,
  weatherProjectionEnabled: true,
  lazyTraceCleanupLimit: 100,
  macroSimulationVersion: "WORLDCRAFT_0_1",
});

function boundedWorldcraftInteger(value, fallback, minimum, maximum) {
  const candidate = Math.floor(Number(value));
  return Number.isFinite(candidate) ? Math.max(minimum, Math.min(maximum, candidate)) : fallback;
}

async function loadWorldcraftRuntimeConfig(db) {
  const snapshot = await db.collection("gameConfigs").doc("zone0").get();
  const source = snapshot.data()?.zone0Settings?.worldcraftV2 || {};
  return {
    traceLifetimeHours: boundedWorldcraftInteger(source.traceLifetimeHours, WORLDCRAFT_DEFAULT_CONFIG.traceLifetimeHours, 1, 24 * 30),
    campActiveGraceMinutes: boundedWorldcraftInteger(source.campActiveGraceMinutes, WORLDCRAFT_DEFAULT_CONFIG.campActiveGraceMinutes, 1, 24 * 60),
    weatherProjectionEnabled: source.weatherProjectionEnabled !== false,
    lazyTraceCleanupLimit: boundedWorldcraftInteger(source.lazyTraceCleanupLimit, WORLDCRAFT_DEFAULT_CONFIG.lazyTraceCleanupLimit, 1, 500),
    macroSimulationVersion: `${source.macroSimulationVersion || WORLDCRAFT_DEFAULT_CONFIG.macroSimulationVersion}`,
  };
}

async function loadWorldbuildingRuntimeConfig(db) {
  const snapshot = await db.collection("gameConfigs").doc("zone0").get();
  return worldbuildingRuntimeConfig(snapshot.data()?.zone0Settings?.worldbuildingV2);
}

async function loadEcologyRuntimeConfig(db) {
  const snapshot = await db.collection("gameConfigs").doc("zone0").get();
  return ecologyRuntimeConfig(snapshot.data()?.zone0Settings?.ecologyV2);
}

async function cleanupExpiredWorldcraftTraces(db, regionId, now, limit) {
  const snapshot = await db.collection("playerTraces").where("regionId", "==", regionId).get();
  const expired = snapshot.docs.filter((document) => {
    const expiresAt = document.data().expiresAt;
    return expiresAt?.toMillis?.() <= now.toMillis();
  }).slice(0, limit);
  if (expired.length === 0) return 0;
  const batch = db.batch();
  expired.forEach((document) => batch.delete(document.ref));
  await batch.commit();
  return expired.length;
}

// ---------------------------------------------------------------------------
// WORLDCRAFT 0 — shared asynchronous world authority.
// ---------------------------------------------------------------------------
// These callable operations are intentionally the only write path for shared
// territorial state. Clients render the data but Firestore rules deny direct
// writes to the collections below.

const WORLDCRAFT_VERSION = "WORLDCRAFT_0_1";
const WORLD_ID = "zone0-shared-world";
const WORLD_MAP_ID = "zone0-map-5x5";
// Callable endpoints must be publicly invocable at Cloud Run so the Firebase
// SDK can reach their handler. Each handler still requires Firebase Auth and
// validates its own ownership and idempotency rules.
const WORLDCRAFT_CALLABLE_OPTIONS = {region: "europe-west9", invoker: "public"};

function requireWorldcraftAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Connexion requise.");
  return request.auth.uid;
}

function worldcraftOperationId(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{8,160}$/.test(value)) {
    throw new HttpsError("invalid-argument", "operationId invalide.");
  }
  return value;
}

function worldcraftCoordinate(x, y) {
  return `${String.fromCharCode("A".charCodeAt(0) + x)}${y + 1}`;
}

function worldcraftOperationRef(operationId) {
  return admin.firestore().collection("worldOperations").doc(operationId);
}

async function requireWorldcraftDev(uid) {
  const user = await admin.firestore().collection("users").doc(uid).get();
  const role = user.data()?.role;
  if (role !== "dev" && role !== "admin") {
    throw new HttpsError("permission-denied", "Outil Worldcraft réservé au développement.");
  }
}

function worldcraftMacro(regionId, now) {
  return {
    regionId,
    biomassFuture: null,
    contaminationFuture: null,
    exploitationPressure: 0,
    renewableResourceAvailability: null,
    mineralReserveSummary: 1000,
    wasteState: null,
    ecologicalStateFuture: null,
    restorationStateFuture: null,
    danger: 0,
    climaticStress: 0,
    communityPresence: 0,
    lastSimulatedAt: now,
    simulationVersion: WORLDCRAFT_VERSION,
  };
}

function biomeSharedState(regionId, biomeId, biomeType, now, metadata = {}) {
  const ecology = ecologyDefaults({biomeType, nowMs: now.toMillis(), existing: {}});
  return {
    regionId,
    biomeId,
    biomeType,
    // V0 ecology uses explicit numerical fields. The legacy `…Future`
    // placeholders stay for compatible readers but are no longer authority.
    biomassFuture: null,
    contaminationFuture: null,
    humidityFuture: null,
    mineralState: "stable",
    mineralReserveSummary: 200,
    wasteState: null,
    exploitationPressure: 0,
    danger: 0,
    dangerCap: 100,
    ecologicalStateFuture: null,
    lastSimulatedAt: now,
    simulationVersion: WORLDCRAFT_VERSION,
    ...ecology,
    ...metadata,
  };
}

function worldbuildingBiomeMetadata({regionId, biomeType, position, definition, version}) {
  return {
    internalPosition: position,
    seed: worldbuildingStableSeed(`250525:${regionId}:${position}:${biomeType}`),
    environmentalTags: definition.environmentalTags || [],
    visualProfileId: definition.visualProfileId || null,
    visualProfile: definition.visualProfile || {},
    parcelGenerationProfileId: definition.parcelGenerationProfileId ||
      definition.parcelGenerationProfile || null,
    neighborCompatibility: definition.neighborCompatibility || [],
    weatherResponseProfile: definition.weatherResponseProfile || {},
    ecologyProfileId: definition.ecologyProfileId || null,
    possibleFindingTables: definition.possibleFindingTables || [],
    worldbuildingVersion: version,
  };
}

// Region documents carry a compact read model for the 5×5 Debug map. The
// detailed Biome documents remain the authority for gameplay and are only read
// when a player enters one Region.
function worldbuildingBiomeSummary({regionId, biomeId, biomeType, position, definition, version}) {
  const metadata = worldbuildingBiomeMetadata({
    regionId, biomeType, position, definition, version,
  });
  return {
    id: biomeId,
    biomeType,
    internalPosition: position,
    seed: metadata.seed,
    environmentalTags: metadata.environmentalTags,
    visualProfileId: metadata.visualProfileId,
    groundSet: metadata.visualProfile.groundSet || null,
    parcelGenerationProfile: metadata.parcelGenerationProfileId,
  };
}

exports.ensureWorldcraftWorld = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  requireWorldcraftAuth(request);
  const db = admin.firestore();
  const worldbuilding = await loadWorldbuildingRuntimeConfig(db);
  const worldbuildingMap = buildWorldbuildingMap(worldbuilding, 250525);
  const composedByCoordinate = new Map(
    worldbuildingMap.regions.map((region) => [region.coordinate, region]),
  );
  const worldRef = db.collection("worlds").doc(WORLD_ID);
  const mapRef = db.collection("worldMaps").doc(WORLD_MAP_ID);
  const now = Timestamp.now();
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(worldRef);
    if (existing.exists) return;
    transaction.set(worldRef, {
      id: WORLD_ID,
      worldVersion: WORLDCRAFT_VERSION,
      seed: 250525,
      activeWorldMapId: WORLD_MAP_ID,
      worldbuildingVersion: worldbuildingMap.config.worldbuildingVersion,
      createdAt: now,
      simulationVersion: WORLDCRAFT_VERSION,
      status: "active",
    });
    const regionIds = [];
    const connectionIds = new Map();
    for (let y = 0; y < 5; y += 1) {
      for (let x = 0; x < 5; x += 1) {
        connectionIds.set(`region-${worldcraftCoordinate(x, y).toLowerCase()}`, []);
      }
    }
    for (let y = 0; y < 5; y += 1) {
      for (let x = 0; x < 5; x += 1) {
        const fromId = `region-${worldcraftCoordinate(x, y).toLowerCase()}`;
        for (const [nx, ny] of [[x + 1, y], [x, y + 1]]) {
          if (nx > 4 || ny > 4) continue;
          const toId = `region-${worldcraftCoordinate(nx, ny).toLowerCase()}`;
          const connectionId = `connection-${fromId}-${toId}`;
          connectionIds.get(fromId).push(connectionId);
          connectionIds.get(toId).push(connectionId);
          transaction.set(db.collection("regionConnections").doc(connectionId), {
            id: connectionId,
            worldId: WORLD_ID,
            worldMapId: WORLD_MAP_ID,
            fromRegionId: fromId,
            toRegionId: toId,
            connectionType: "orthogonal",
            traversable: true,
            createdAt: now,
          });
        }
      }
    }
    for (let y = 0; y < 5; y += 1) {
      for (let x = 0; x < 5; x += 1) {
        const coordinate = worldcraftCoordinate(x, y);
        const regionId = `region-${coordinate.toLowerCase()}`;
        regionIds.push(regionId);
        const composed = composedByCoordinate.get(coordinate);
        const profile = composed.profile;
        const biomeIds = Array.from({length: 5}, (_, index) => `${regionId}-biome-${index + 1}`);
        const biomePlans = worldbuildingMap.config.internalPositions.map((position, index) => {
          const biomeType = composed.biomeTypesByPosition[position];
          const definition = worldbuildingMap.config.biomes[biomeType];
          return {biomeId: biomeIds[index], biomeType, position, definition};
        });
        transaction.set(db.collection("regions").doc(regionId), {
          id: regionId,
          worldId: WORLD_ID,
          worldMapId: WORLD_MAP_ID,
          coordinateX: x,
          coordinateY: y,
          displayCoordinate: coordinate,
          profile,
          seed: worldbuildingStableSeed(`250525:${regionId}`),
          worldbuildingVersion: worldbuildingMap.config.worldbuildingVersion,
          primaryInfluence: composed.primaryInfluence,
          secondaryInfluences: composed.secondaryInfluences,
          visualTags: composed.visualTags,
          generationSeedOffset: composed.generationSeedOffset,
          biomeIds,
          biomeSummaries: biomePlans.map((plan) => worldbuildingBiomeSummary({
            regionId,
            biomeId: plan.biomeId,
            biomeType: plan.biomeType,
            position: plan.position,
            definition: plan.definition,
            version: worldbuildingMap.config.worldbuildingVersion,
          })),
          connectionIds: connectionIds.get(regionId),
          hubId: coordinate === "C3" ? "hub-c3" : null,
          campId: null,
          macroStateId: regionId,
          weatherStateId: regionId,
          occupancyState: "free",
          passagePolicy: "closed",
          createdAt: now,
          lastSimulatedAt: now,
          simulationVersion: WORLDCRAFT_VERSION,
        });
        transaction.set(db.collection("regionMacroStates").doc(regionId), worldcraftMacro(regionId, now));
        biomePlans.forEach((plan) => {
          transaction.set(db.collection("biomeSharedStates").doc(plan.biomeId),
            biomeSharedState(regionId, plan.biomeId, plan.biomeType, now,
              worldbuildingBiomeMetadata({
                regionId,
                biomeType: plan.biomeType,
                position: plan.position,
                definition: plan.definition,
                version: worldbuildingMap.config.worldbuildingVersion,
              })));
        });
      }
    }
    transaction.set(mapRef, {
      id: WORLD_MAP_ID,
      worldId: WORLD_ID,
      width: 5,
      height: 5,
      regionIds,
      hubIds: ["hub-c3"],
      createdAt: now,
      version: WORLDCRAFT_VERSION,
      worldbuildingVersion: worldbuildingMap.config.worldbuildingVersion,
    });
    transaction.set(db.collection("hubs").doc("hub-c3"), {
      id: "hub-c3",
      worldId: WORLD_ID,
      regionId: "region-c3",
      hubType: "highRefuge",
      name: "Hub C3",
      state: "active",
      createdAt: now,
    });
    transaction.set(db.collection("worldbuildingAudits").doc(WORLD_MAP_ID), {
      worldId: WORLD_ID,
      worldMapId: WORLD_MAP_ID,
      worldbuildingVersion: worldbuildingMap.config.worldbuildingVersion,
      warnings: worldbuildingMap.warnings,
      generatedAt: now,
    });
  });
  return {worldId: WORLD_ID, worldMapId: WORLD_MAP_ID};
});

// Applies a versioned Dashboard composition to an already seeded prototype
// world. It deliberately preserves every macro value, Camp and inventory: only
// geographic content and visual/projection metadata are upgraded.
exports.upgradeWorldcraftWorldbuilding = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const actorId = requireWorldcraftAuth(request);
  await requireWorldcraftDev(actorId);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const db = admin.firestore();
  const worldbuilding = await loadWorldbuildingRuntimeConfig(db);
  const built = buildWorldbuildingMap(worldbuilding, 250525);
  const now = Timestamp.now();
  const operationRef = worldcraftOperationRef(operationId);
  const worldRef = db.collection("worlds").doc(WORLD_ID);
  const result = await db.runTransaction(async (transaction) => {
    const [operation, world] = await Promise.all([
      transaction.get(operationRef), transaction.get(worldRef),
    ]);
    if (operation.exists) return operation.data().result;
    if (!world.exists) {
      throw new HttpsError("failed-precondition", "Initialise d’abord le World partagé.");
    }
    const regionRefs = built.regions.map((region) =>
      db.collection("regions").doc(`region-${region.coordinate.toLowerCase()}`));
    const regionSnapshots = await transaction.getAll(...regionRefs);
    const regionById = new Map(regionSnapshots.map((snapshot) => [snapshot.id, snapshot]));
    for (const composed of built.regions) {
      const regionId = `region-${composed.coordinate.toLowerCase()}`;
      const regionRef = db.collection("regions").doc(regionId);
      const regionSnapshot = regionById.get(regionId);
      if (!regionSnapshot.exists) {
        throw new HttpsError("failed-precondition", `Région ${composed.coordinate} absente.`);
      }
      const biomeIds = Array.isArray(regionSnapshot.data().biomeIds)
        ? regionSnapshot.data().biomeIds.map(String) : [];
      if (biomeIds.length !== built.config.internalPositions.length) {
        throw new HttpsError("failed-precondition", `Biomes invalides pour ${composed.coordinate}.`);
      }
      const biomePlans = built.config.internalPositions.map((position, index) => {
        const biomeType = composed.biomeTypesByPosition[position];
        return {
          biomeId: biomeIds[index],
          biomeType,
          position,
          definition: built.config.biomes[biomeType],
        };
      });
      transaction.set(regionRef, {
        profile: composed.profile,
        primaryInfluence: composed.primaryInfluence,
        secondaryInfluences: composed.secondaryInfluences,
        visualTags: composed.visualTags,
        generationSeedOffset: composed.generationSeedOffset,
        biomeSummaries: biomePlans.map((plan) => worldbuildingBiomeSummary({
          regionId,
          biomeId: plan.biomeId,
          biomeType: plan.biomeType,
          position: plan.position,
          definition: plan.definition,
          version: built.config.worldbuildingVersion,
        })),
        worldbuildingVersion: built.config.worldbuildingVersion,
        worldbuildingUpdatedAt: now,
      }, {merge: true});
      biomePlans.forEach((plan) => {
        transaction.set(db.collection("biomeSharedStates").doc(plan.biomeId), {
          biomeType: plan.biomeType,
          ...worldbuildingBiomeMetadata({
            regionId,
            biomeType: plan.biomeType,
            position: plan.position,
            definition: plan.definition,
            version: built.config.worldbuildingVersion,
          }),
          lastWorldbuildingUpdatedAt: now,
        }, {merge: true});
      });
    }
    const upgraded = {
      worldId: WORLD_ID,
      worldMapId: WORLD_MAP_ID,
      worldbuildingVersion: built.config.worldbuildingVersion,
      upgradedRegions: built.regions.length,
      warnings: built.warnings,
    };
    transaction.set(worldRef, {
      worldbuildingVersion: built.config.worldbuildingVersion,
      worldbuildingUpdatedAt: now,
    }, {merge: true});
    transaction.set(db.collection("worldMaps").doc(WORLD_MAP_ID), {
      worldbuildingVersion: built.config.worldbuildingVersion,
      worldbuildingUpdatedAt: now,
    }, {merge: true});
    transaction.set(db.collection("worldbuildingAudits").doc(WORLD_MAP_ID), {
      worldId: WORLD_ID,
      worldMapId: WORLD_MAP_ID,
      worldbuildingVersion: built.config.worldbuildingVersion,
      warnings: built.warnings,
      generatedAt: now,
    }, {merge: true});
    transaction.create(operationRef, {
      id: operationId,
      type: "upgradeWorldcraftWorldbuilding",
      actorId,
      createdAt: now,
      result: upgraded,
    });
    return upgraded;
  });
  return result;
});

exports.createCampInRegion = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const founderId = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const regionId = `${request.data?.regionId || ""}`;
  const db = admin.firestore();
  const operationRef = worldcraftOperationRef(operationId);
  const regionRef = db.collection("regions").doc(regionId);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [operation, regionSnapshot] = await Promise.all([
      transaction.get(operationRef), transaction.get(regionRef),
    ]);
    if (operation.exists) return operation.data().result;
    if (!regionSnapshot.exists) throw new HttpsError("not-found", "Région introuvable.");
    const region = regionSnapshot.data();
    if (region.campId) {
      throw new HttpsError("already-exists", "Cette Région possède déjà un Camp.");
    }
    const campId = `camp-${regionId}`;
    const campRef = db.collection("camps").doc(campId);
    const macroRef = db.collection("campMacroStates").doc(campId);
    const storageRef = db.collection("campStorages").doc(`${campId}-storage`);
    const reserveRef = db.collection("passageReserves").doc(campId);
    const camp = {
      id: campId,
      regionId,
      founderId,
      communityId: null,
      coreId: `${campId}-core`,
      buildingIds: [`${campId}-house`, `${campId}-kernel`],
      storageId: `${campId}-storage`,
      state: "active",
      simulationMode: "active",
      macroStateId: campId,
      accessPolicy: "founderOnly",
      foundedAt: now,
      lastActiveAt: now,
      lastSimulatedAt: now,
      simulationVersion: WORLDCRAFT_VERSION,
      // Detailed state is kept under the one global Camp document during the
      // prototype. It is the same implantation in ACTIVE and AUTONOMOUS mode.
      detailedState: {
        core: {id: `${campId}-core`, state: "active", progressionTier: 0},
        buildings: {
          [`${campId}-house`]: {
            id: `${campId}-house`, buildingType: "house", state: "underConstruction",
            construction: {startedAt: now, baseDurationSeconds: 86400, assistanceEvents: [], resourceContributions: [], assistanceCooldownSeconds: 10800},
          },
          [`${campId}-kernel`]: {
            id: `${campId}-kernel`, buildingType: "kernel", state: "underConstruction",
            construction: {startedAt: now, baseDurationSeconds: 86400, assistanceEvents: [], resourceContributions: [], assistanceCooldownSeconds: 10800},
          },
        },
        residents: [
          {id: `${campId}-resident-1`, displayName: "Aube", desiredJob: "Récolteur"},
          {id: `${campId}-resident-2`, displayName: "Mousse", desiredJob: "Patrouilleur"},
          {id: `${campId}-resident-3`, displayName: "Silex", desiredJob: "Bâtisseur"},
        ],
        firstResidentHook: {status: "arrived", campId},
      },
    };
    const result = {campId, regionId, worldId: WORLD_ID, created: true};
    transaction.create(campRef, camp);
    transaction.create(macroRef, {
      campId,
      autonomy: 0,
      resilience: 0,
      infrastructureState: "foundation",
      foodSecurity: 0,
      populationPressure: 0,
      ecologicalSupport: 0,
      essentialFunctionsState: "stable",
      recentEventIds: [],
      helpState: "none",
      lastSimulatedAt: now,
      simulationVersion: WORLDCRAFT_VERSION,
    });
    transaction.create(storageRef, {
      id: `${campId}-storage`,
      campId,
      resourceEntries: {},
      updatedAt: now,
      accessPolicy: "community",
    });
    transaction.create(reserveRef, {
      id: campId,
      campId,
      resourceEntries: {},
      policy: "closed",
      updatedAt: now,
    });
    transaction.update(regionRef, {
      campId,
      occupancyState: "occupied",
      lastSimulatedAt: now,
    });
    transaction.create(operationRef, {
      id: operationId,
      type: "createCampInRegion",
      actorId: founderId,
      createdAt: now,
      result,
    });
    return result;
  });
});

exports.resolveWorldcraftRegionUntil = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  requireWorldcraftAuth(request);
  const regionId = `${request.data?.regionId || ""}`;
  const db = admin.firestore();
  const regionRef = db.collection("regions").doc(regionId);
  const macroRef = db.collection("regionMacroStates").doc(regionId);
  const now = Timestamp.now();
  const config = await loadWorldcraftRuntimeConfig(db);
  const [ecologyConfig, weatherSnapshot, cleanedTraceCount] = await Promise.all([
    loadEcologyRuntimeConfig(db),
    db.collection("weatherCells").where("coveredRegionIds", "array-contains", regionId).get(),
    cleanupExpiredWorldcraftTraces(db, regionId, now, config.lazyTraceCleanupLimit),
  ]);
  const weatherCells = weatherSnapshot.docs.map((document) => {
    const cell = document.data();
    return {...cell, startsAtMs: cell.startsAt?.toMillis?.(), endsAtMs: cell.endsAt?.toMillis?.()};
  });
  const activeWeather = config.weatherProjectionEnabled ? weatherSnapshot.docs
    .map((document) => document.data())
    .filter((cell) => cell.status !== "expired" && cell.startsAt?.toMillis?.() <= now.toMillis() && cell.endsAt?.toMillis?.() > now.toMillis())
    .map((cell) => `${cell.id}`) : [];
  return db.runTransaction(async (transaction) => {
    const [regionSnapshot, macroSnapshot] = await Promise.all([
      transaction.get(regionRef), transaction.get(macroRef),
    ]);
    if (!regionSnapshot.exists || !macroSnapshot.exists) {
      throw new HttpsError("not-found", "Région introuvable.");
    }
    const region = regionSnapshot.data();
    const biomeIds = Array.isArray(region.biomeIds) ? region.biomeIds : [];
    const biomeSnapshots = await Promise.all(biomeIds.map((id) =>
      transaction.get(db.collection("biomeSharedStates").doc(id))));
    const ecology = [];
    biomeSnapshots.forEach((biomeSnapshot) => {
      if (!biomeSnapshot.exists) return;
      const current = biomeSnapshot.data();
      const result = resolveBiomeEcology({
        state: current,
        biomeType: current.biomeType,
        targetMs: now.toMillis(),
        weatherCells,
        config: ecologyConfig,
      });
      transaction.update(biomeSnapshot.ref, {
        ...result.state,
        lastSimulatedAt: now,
        lastEcologyResolvedAtMs: result.state.lastEcologyResolvedAtMs,
        ecologyQualitative: qualitativeEcology(result.state, ecologyConfig),
      });
      ecology.push({biomeId: current.biomeId, effects: result.effects, ecology: qualitativeEcology(result.state, ecologyConfig)});
    });
    transaction.update(regionRef, {lastSimulatedAt: now});
    transaction.update(macroRef, {
      lastSimulatedAt: now,
      simulationVersion: WORLDCRAFT_VERSION,
      activeWeatherCellIds: activeWeather,
      weatherResolvedAt: now,
    });
    return {
      region: {...regionSnapshot.data(), lastSimulatedAt: now.toMillis()},
      macroState: {...macroSnapshot.data(), lastSimulatedAt: now.toMillis(), activeWeatherCellIds: activeWeather},
      cleanedTraceCount,
      ecology,
    };
  });
});

exports.setWorldcraftCampMode = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const uid = requireWorldcraftAuth(request);
  const campId = `${request.data?.campId || ""}`;
  const mode = request.data?.mode === "autonomous" ? "autonomous" : "active";
  const campRef = admin.firestore().collection("camps").doc(campId);
  const now = Timestamp.now();
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(campRef);
    if (!snapshot.exists) throw new HttpsError("not-found", "Camp introuvable.");
    if (snapshot.data().founderId !== uid) throw new HttpsError("permission-denied", "Accès Camp refusé.");
    transaction.update(campRef, {simulationMode: mode, state: mode, lastActiveAt: now, lastSimulatedAt: now});
    return {campId, mode};
  });
});

exports.resolveWorldcraftCampUntil = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const uid = requireWorldcraftAuth(request);
  const campId = `${request.data?.campId || ""}`;
  const db = admin.firestore();
  const campRef = db.collection("camps").doc(campId);
  const macroRef = db.collection("campMacroStates").doc(campId);
  const now = Timestamp.now();
  const config = await loadWorldcraftRuntimeConfig(db);
  return db.runTransaction(async (transaction) => {
    const [campSnapshot, macroSnapshot] = await Promise.all([transaction.get(campRef), transaction.get(macroRef)]);
    if (!campSnapshot.exists || !macroSnapshot.exists) throw new HttpsError("not-found", "Camp introuvable.");
    const camp = campSnapshot.data();
    const lastActive = camp.lastActiveAt?.toMillis?.() || 0;
    const isFounderVisiting = camp.founderId === uid;
    const activeRecently = now.toMillis() - lastActive <= config.campActiveGraceMinutes * 60 * 1000;
    const wasAutonomous = camp.simulationMode === "autonomous" || !activeRecently;
    const mode = isFounderVisiting ? "active" : (activeRecently ? camp.simulationMode : "autonomous");
    const macro = macroSnapshot.data();
    const pendingNarrative = isFounderVisiting && wasAutonomous ? {
      type: "camp_reactivation",
      createdAt: now,
      message: macro.helpState && macro.helpState !== "none"
        ? "Pendant ton absence, le Camp a tenu bon mais demande encore de l’aide."
        : "Pendant ton absence, le Camp a poursuivi son rythme autonome.",
    } : camp.pendingNarrative || null;
    transaction.update(campRef, {
      simulationMode: mode,
      state: mode,
      lastActiveAt: isFounderVisiting ? now : camp.lastActiveAt,
      lastSimulatedAt: now,
      pendingNarrative,
    });
    transaction.update(macroRef, {lastSimulatedAt: now, simulationVersion: WORLDCRAFT_VERSION});
    return {campId, mode, narrative: pendingNarrative, macroState: {...macro, lastSimulatedAt: now.toMillis()}};
  });
});

function resolveWorldcraftConstruction(building, now) {
  const construction = building.construction || {};
  const assistance = construction.assistanceEvents || [];
  const contributions = construction.resourceContributions || [];
  const baseSeconds = Number(construction.baseDurationSeconds || 86400);
  const remaining = baseSeconds - 10800 * (assistance.length + contributions.length);
  if (remaining <= 0 || now.toMillis() >= construction.startedAt.toMillis() + baseSeconds * 1000) {
    building.state = "active";
  }
}

function mutateWorldcraftCampBuilding(camp, buildingId, mutator, now) {
  const details = {...(camp.detailedState || {})};
  const buildings = {...(details.buildings || {})};
  const building = {...(buildings[buildingId] || {})};
  if (!building.id) throw new HttpsError("not-found", "Chantier introuvable.");
  const construction = {...(building.construction || {})};
  if (building.state === "active") throw new HttpsError("failed-precondition", "Bâtiment déjà construit.");
  mutator(construction);
  building.construction = construction;
  resolveWorldcraftConstruction(building, now);
  buildings[buildingId] = building;
  details.buildings = buildings;
  return {...camp, detailedState: details};
}

exports.helpWorldcraftCampConstruction = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const uid = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const campId = `${request.data?.campId || ""}`;
  const buildingId = `${request.data?.buildingId || ""}`;
  const db = admin.firestore();
  const operationRef = worldcraftOperationRef(operationId);
  const campRef = db.collection("camps").doc(campId);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [previous, campSnapshot] = await Promise.all([transaction.get(operationRef), transaction.get(campRef)]);
    if (previous.exists) return previous.data().result;
    if (!campSnapshot.exists) throw new HttpsError("not-found", "Camp introuvable.");
    const camp = campSnapshot.data();
    if (camp.founderId !== uid) throw new HttpsError("permission-denied", "Accès Camp refusé.");
    const next = mutateWorldcraftCampBuilding(camp, buildingId, (construction) => {
      const events = [...(construction.assistanceEvents || [])];
      const last = events.length > 0 ? events[events.length - 1] : null;
      const lastMillis = last?.toMillis?.() || Number(last || 0);
      if (lastMillis && now.toMillis() - lastMillis < Number(construction.assistanceCooldownSeconds || 10800) * 1000) {
        throw new HttpsError("failed-precondition", "Les bâtisseurs auront de nouveau besoin de toi dans 3 h.");
      }
      events.push(now);
      construction.assistanceEvents = events;
    }, now);
    const result = {campId, buildingId, message: "Ton aide fait gagner 3 h au chantier."};
    transaction.set(campRef, next);
    transaction.create(operationRef, {id: operationId, type: "helpWorldcraftCampConstruction", actorId: uid, createdAt: now, result});
    return result;
  });
});

exports.contributeWorldcraftCampConstruction = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const uid = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const campId = `${request.data?.campId || ""}`;
  const buildingId = `${request.data?.buildingId || ""}`;
  const resourceType = `${request.data?.resourceType || ""}`;
  if (!["organic", "mineral", "waste"].includes(resourceType)) {
    throw new HttpsError("invalid-argument", "Ressource de chantier invalide.");
  }
  const db = admin.firestore();
  const operationRef = worldcraftOperationRef(operationId);
  const campRef = db.collection("camps").doc(campId);
  const storageRef = db.collection("campStorages").doc(`${campId}-storage`);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [previous, campSnapshot, storageSnapshot] = await Promise.all([transaction.get(operationRef), transaction.get(campRef), transaction.get(storageRef)]);
    if (previous.exists) return previous.data().result;
    if (!campSnapshot.exists || !storageSnapshot.exists) throw new HttpsError("not-found", "Camp ou stock V2 introuvable.");
    const camp = campSnapshot.data();
    if (camp.founderId !== uid) throw new HttpsError("permission-denied", "Accès Camp refusé.");
    const amounts = {...(storageSnapshot.data().resourceEntries || {})};
    if (Number(amounts[resourceType] || 0) < 1) {
      throw new HttpsError("failed-precondition", "Ressource insuffisante dans le stock du Camp.");
    }
    amounts[resourceType] = Number(amounts[resourceType]) - 1;
    if (amounts[resourceType] === 0) delete amounts[resourceType];
    const next = mutateWorldcraftCampBuilding(camp, buildingId, (construction) => {
      construction.resourceContributions = [...(construction.resourceContributions || []), {resource: resourceType, at: now}];
    }, now);
    const result = {campId, buildingId, resourceType, message: "Ressource livrée : le chantier gagne 3 h."};
    transaction.set(campRef, next);
    transaction.update(storageRef, {resourceEntries: amounts, updatedAt: now});
    transaction.create(operationRef, {id: operationId, type: "contributeWorldcraftCampConstruction", actorId: uid, createdAt: now, result});
    return result;
  });
});

// The detailed Lisière inventory remains a local transport projection. This
// operation atomically moves arrived physical stacks into the shared Camp
// storage, which is the authority used by Camp actions.
exports.flushWorldcraftCampStorage = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const uid = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const campId = `${request.data?.campId || ""}`;
  const db = admin.firestore();
  const operationRef = worldcraftOperationRef(operationId);
  const campRef = db.collection("camps").doc(campId);
  const storageRef = db.collection("campStorages").doc(`${campId}-storage`);
  const lisiereRef = db.collection("users").doc(uid).collection("game").doc("zone0V2Lisiere");
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [previous, campSnapshot, storageSnapshot, lisiereSnapshot] = await Promise.all([
      transaction.get(operationRef), transaction.get(campRef), transaction.get(storageRef), transaction.get(lisiereRef),
    ]);
    if (previous.exists) return previous.data().result;
    if (!campSnapshot.exists || !storageSnapshot.exists || !lisiereSnapshot.exists) {
      throw new HttpsError("not-found", "Camp ou stockage introuvable.");
    }
    if (campSnapshot.data().founderId !== uid) throw new HttpsError("permission-denied", "Accès Camp refusé.");
    const inventories = {...(lisiereSnapshot.data().inventories || {})};
    const localStock = {...(inventories["camp-storage-v2"] || {})};
    const localAmounts = {...(localStock.amounts || {})};
    const entries = {...(storageSnapshot.data().resourceEntries || {})};
    let transferred = 0;
    ["organic", "mineral", "waste"].forEach((resourceType) => {
      const amount = Math.max(0, Math.floor(Number(localAmounts[resourceType] || 0)));
      if (amount === 0) return;
      entries[resourceType] = Math.max(0, Math.floor(Number(entries[resourceType] || 0))) + amount;
      delete localAmounts[resourceType];
      transferred += amount;
    });
    localStock.amounts = localAmounts;
    inventories["camp-storage-v2"] = localStock;
    const result = {campId, transferred, resourceEntries: entries};
    transaction.update(storageRef, {resourceEntries: entries, updatedAt: now});
    transaction.update(lisiereRef, {inventories, updatedAt: now});
    transaction.create(operationRef, {id: operationId, type: "flushWorldcraftCampStorage", actorId: uid, createdAt: now, result});
    return result;
  });
});

exports.extractSharedResource = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const playerId = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const biomeId = `${request.data?.biomeId || ""}`;
  const requestedAmount = Math.max(0, Math.floor(Number(request.data?.requestedAmount || 0)));
  if (requestedAmount < 1) throw new HttpsError("invalid-argument", "Quantité invalide.");
  const db = admin.firestore();
  const operationRef = worldcraftOperationRef(operationId);
  const biomeRef = db.collection("biomeSharedStates").doc(biomeId);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [previous, biomeSnapshot] = await Promise.all([transaction.get(operationRef), transaction.get(biomeRef)]);
    if (previous.exists) return previous.data().result;
    if (!biomeSnapshot.exists) throw new HttpsError("not-found", "Biome introuvable.");
    const state = biomeSnapshot.data();
    const available = Math.max(0, Math.floor(Number(state.mineralReserveSummary || 0)));
    const actualExtracted = Math.min(available, requestedAmount);
    const ecology = ecologyDefaults({biomeType: state.biomeType, nowMs: now.toMillis(), existing: state});
    const extractionRemainder = Math.max(0, ecologyNumber(state.surfaceExtractionWasteRemainder));
    const wasteProgress = extractionRemainder + actualExtracted;
    const generatedWaste = Math.floor(wasteProgress / 10);
    const next = generatedWaste > 0
      ? addWasteDeposit(ecology, {id: `surface-${operationId}`, quantity: generatedWaste, createdAtMs: now.toMillis()})
      : ecology;
    next.surfaceExtractionWasteRemainder = wasteProgress % 10;
    const biomass = calculateBiomass(next);
    next.biomass = biomass.biomass;
    next.biologicalFloor = biomass.biologicalFloor;
    const result = {operationId, biomeId, requestedAmount, actualExtracted, generatedWaste};
    transaction.update(biomeRef, {
      // Surface mineral is finite but does not create exploitation pressure.
      ...next,
      mineralReserveSummary: available - actualExtracted,
      ecologyQualitative: qualitativeEcology(next),
      lastSimulatedAt: now,
    });
    transaction.create(operationRef, {id: operationId, type: "extractSharedResource", actorId: playerId, createdAt: now, result});
    return result;
  });
});

async function weatherForBiome(db, biomeId) {
  const biome = await db.collection("biomeSharedStates").doc(biomeId).get();
  if (!biome.exists) throw new HttpsError("not-found", "Biome introuvable.");
  const regionId = biome.data().regionId;
  const weather = await db.collection("weatherCells").where("coveredRegionIds", "array-contains", regionId).get();
  return weather.docs.map((document) => {
    const cell = document.data();
    return {...cell, startsAtMs: cell.startsAt?.toMillis?.(), endsAtMs: cell.endsAt?.toMillis?.()};
  });
}

function validEcologyNodeId(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{3,180}$/.test(value);
}

// A detailed Organic node is a shared prototype state keyed by the stable
// local parcel node id. It is intentionally a compact map in the Biome
// document: Worldcraft does not create one Firestore document per sprite.
exports.harvestWorldcraftOrganic = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const playerId = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const biomeId = `${request.data?.biomeId || ""}`;
  const nodeId = `${request.data?.nodeId || ""}`;
  const requestedAmount = Math.min(10, Math.max(1, Math.floor(Number(request.data?.requestedAmount || 1))));
  if (!validEcologyNodeId(nodeId) || !nodeId.startsWith(`${biomeId}-parcel-`) || !nodeId.endsWith("-organic")) {
    throw new HttpsError("invalid-argument", "Nœud Organique invalide.");
  }
  const db = admin.firestore();
  const [config, weatherCells] = await Promise.all([loadEcologyRuntimeConfig(db), weatherForBiome(db, biomeId)]);
  const operationRef = worldcraftOperationRef(operationId);
  const biomeRef = db.collection("biomeSharedStates").doc(biomeId);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [previous, snapshot] = await Promise.all([transaction.get(operationRef), transaction.get(biomeRef)]);
    if (previous.exists) return previous.data().result;
    if (!snapshot.exists) throw new HttpsError("not-found", "Biome introuvable.");
    const current = snapshot.data();
    const resolved = resolveBiomeEcology({state: current, biomeType: current.biomeType, targetMs: now.toMillis(), weatherCells, config}).state;
    const node = resolved.organicNodes[nodeId] || {
      id: nodeId, vitality: config.organic.maxVitality, biomassCapacity: config.organic.nodeBiomassCapacity,
      state: "active", depletionAtMs: [], createdAtMs: now.toMillis(),
    };
    const actualHarvested = Math.min(requestedAmount, Math.max(0, Math.floor(ecologyNumber(node.vitality))));
    node.vitality = Math.max(0, ecologyNumber(node.vitality) - actualHarvested);
    if (node.vitality <= 0 && actualHarvested > 0) {
      const cutoff = now.toMillis() - config.organic.depletionWindowHours * 60 * 60 * 1000;
      node.depletionAtMs = [...(Array.isArray(node.depletionAtMs) ? node.depletionAtMs : []), now.toMillis()].filter((value) => ecologyNumber(value) >= cutoff);
      node.state = node.depletionAtMs.length >= config.organic.destructionDepletions ? "destroyed" : "depleted";
    }
    resolved.organicNodes[nodeId] = node;
    const biomass = calculateBiomass(resolved, config); resolved.biomass = biomass.biomass; resolved.biologicalFloor = biomass.biologicalFloor;
    const result = {operationId, biomeId, nodeId, requestedAmount, actualHarvested, nodeState: node.state, vitality: node.vitality};
    transaction.update(biomeRef, {...resolved, ecologyQualitative: qualitativeEcology(resolved, config), lastSimulatedAt: now});
    transaction.create(operationRef, {id: operationId, type: "harvestWorldcraftOrganic", actorId: playerId, createdAt: now, result});
    return result;
  });
});

exports.cleanWorldcraftWaste = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const playerId = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const biomeId = `${request.data?.biomeId || ""}`;
  const depositId = `${request.data?.depositId || ""}`;
  const requestedAmount = Math.min(100, Math.max(1, Math.floor(Number(request.data?.requestedAmount || 1))));
  if (!validEcologyNodeId(depositId) || !depositId.startsWith(`${biomeId}-parcel-`) || !depositId.endsWith("-waste")) {
    throw new HttpsError("invalid-argument", "Amas de Déchets invalide.");
  }
  const db = admin.firestore(); const operationRef = worldcraftOperationRef(operationId); const biomeRef = db.collection("biomeSharedStates").doc(biomeId); const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [previous, snapshot] = await Promise.all([transaction.get(operationRef), transaction.get(biomeRef)]);
    if (previous.exists) return previous.data().result;
    if (!snapshot.exists) throw new HttpsError("not-found", "Biome introuvable.");
    const state = ecologyDefaults({biomeType: snapshot.data().biomeType, nowMs: now.toMillis(), existing: snapshot.data()});
    // Parcels are deterministic local projections. Their finite starting
    // deposits are materialised once on the server the first time somebody
    // cleans one, rather than trusting a client supplied quantity.
    if (!state.wasteDeposits[depositId]) {
      Object.assign(state, addWasteDeposit(state, {
        id: depositId,
        quantity: 10,
        createdAtMs: state.lastEcologyResolvedAtMs,
      }));
    }
    const deposit = state.wasteDeposits[depositId];
    const cleanedAmount = Math.min(requestedAmount, Math.max(0, Math.floor(ecologyNumber(deposit?.quantity))));
    if (deposit) { deposit.quantity -= cleanedAmount; if (deposit.quantity <= 0) delete state.wasteDeposits[depositId]; }
    state.wasteQuantity = Object.values(state.wasteDeposits).reduce((sum, item) => sum + ecologyNumber(item.quantity), 0);
    const result = {operationId, biomeId, depositId, requestedAmount, cleanedAmount, remainingVitality: deposit?.quantity || 0};
    transaction.update(biomeRef, {...state, ecologyQualitative: qualitativeEcology(state), lastSimulatedAt: now});
    transaction.create(operationRef, {id: operationId, type: "cleanWorldcraftWaste", actorId: playerId, createdAt: now, result});
    return result;
  });
});

exports.extractWorldcraftDeepMineral = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const playerId = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const biomeId = `${request.data?.biomeId || ""}`;
  const requestedAmount = Math.min(1000, Math.max(1, Math.floor(Number(request.data?.requestedAmount || 1))));
  const cadence = ["gentle", "normal", "intensive"].includes(request.data?.cadence) ? request.data.cadence : "normal";
  const automated = request.data?.automated === true;
  const actorType = ["ptibug", "resident", "manual"].includes(request.data?.actorType) ? request.data.actorType : "manual";
  const db = admin.firestore(); const config = await loadEcologyRuntimeConfig(db); const operationRef = worldcraftOperationRef(operationId); const biomeRef = db.collection("biomeSharedStates").doc(biomeId); const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [previous, snapshot] = await Promise.all([transaction.get(operationRef), transaction.get(biomeRef)]);
    if (previous.exists) return previous.data().result;
    if (!snapshot.exists) throw new HttpsError("not-found", "Biome introuvable.");
    const state = ecologyDefaults({biomeType: snapshot.data().biomeType, nowMs: now.toMillis(), config, existing: snapshot.data()});
    const regime = config.mine.cadences[cadence]; const desired = Math.max(1, Math.floor(requestedAmount * ecologyNumber(regime.multiplier, 1)));
    const actualExtracted = Math.min(Math.floor(state.deepMineralReserve), desired);
    state.deepMineralReserve -= actualExtracted;
    const wasteProgress = ecologyNumber(state.deepExtractionWasteRemainder) + actualExtracted;
    const directProgress = ecologyNumber(state.deepExtractionContaminationRemainder) + actualExtracted;
    const generatedWaste = Math.floor(wasteProgress / 10 * ecologyNumber(config.mine.wastePerTenExtracted, 1));
    const directContamination = Math.floor(directProgress / 10 * ecologyNumber(config.mine.directContaminationPerTenExtracted, 1));
    state.deepExtractionWasteRemainder = wasteProgress % 10; state.deepExtractionContaminationRemainder = directProgress % 10;
    if (generatedWaste > 0) Object.assign(state, addWasteDeposit(state, {id: `mine-${operationId}`, quantity: generatedWaste, createdAtMs: now.toMillis()}));
    state.contamination = ecologyClamp(ecologyNumber(state.contamination) + directContamination, 0, 100);
    state.exploitationPressure = Math.max(0, ecologyNumber(state.exploitationPressure) + actualExtracted / 10 * ecologyNumber(regime.pressurePerTen, 1));
    state.mineState = {enabled: true, cadence, automated, actorType, lastExtractedAtMs: now.toMillis()};
    const biomass = calculateBiomass(state, config); state.biomass = biomass.biomass; state.biologicalFloor = biomass.biologicalFloor;
    const result = {operationId, biomeId, cadence, automated, actorType, actualExtracted, generatedWaste, directContamination, exploitationPressure: state.exploitationPressure};
    transaction.update(biomeRef, {...state, ecologyQualitative: qualitativeEcology(state, config), lastSimulatedAt: now});
    transaction.create(operationRef, {id: operationId, type: "extractWorldcraftDeepMineral", actorId: playerId, createdAt: now, result});
    return result;
  });
});

exports.adjustWorldcraftBiomeDanger = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const playerId = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const biomeId = `${request.data?.biomeId || ""}`;
  const delta = Math.trunc(Number(request.data?.delta || 0));
  const db = admin.firestore();
  const operationRef = worldcraftOperationRef(operationId);
  const biomeRef = db.collection("biomeSharedStates").doc(biomeId);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [previous, biomeSnapshot] = await Promise.all([transaction.get(operationRef), transaction.get(biomeRef)]);
    if (previous.exists) return previous.data().result;
    if (!biomeSnapshot.exists) throw new HttpsError("not-found", "Biome introuvable.");
    const state = biomeSnapshot.data();
    const cap = Math.max(1, Number(state.dangerCap || 100));
    const danger = Math.max(0, Math.min(cap, Number(state.danger || 0) + delta));
    const result = {biomeId, danger};
    transaction.update(biomeRef, {danger, lastSimulatedAt: now});
    transaction.create(operationRef, {id: operationId, type: "adjustWorldcraftBiomeDanger", actorId: playerId, createdAt: now, result});
    return result;
  });
});

exports.recordWorldcraftTrace = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const playerId = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const regionId = `${request.data?.regionId || ""}`;
  const biomeId = request.data?.biomeId ? `${request.data.biomeId}` : null;
  const traceType = `${request.data?.traceType || "visit"}`;
  const db = admin.firestore();
  const operationRef = worldcraftOperationRef(operationId);
  const traceRef = db.collection("playerTraces").doc(`trace-${operationId}`);
  const now = Timestamp.now();
  const config = await loadWorldcraftRuntimeConfig(db);
  return db.runTransaction(async (transaction) => {
    const previous = await transaction.get(operationRef);
    if (previous.exists) return previous.data().result;
    const result = {traceId: traceRef.id, regionId};
    transaction.create(traceRef, {id: traceRef.id, worldId: WORLD_ID, playerId, regionId, biomeId, traceType, createdAt: now, expiresAt: Timestamp.fromMillis(now.toMillis() + config.traceLifetimeHours * 3600000)});
    transaction.create(operationRef, {id: operationId, type: "recordWorldcraftTrace", actorId: playerId, createdAt: now, result});
    return result;
  });
});

exports.claimWorldcraftPassageReserve = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const playerId = requireWorldcraftAuth(request);
  const operationId = worldcraftOperationId(request.data?.operationId);
  const campId = `${request.data?.campId || ""}`;
  const resourceType = `${request.data?.resourceType || ""}`;
  const requestedAmount = Math.max(0, Math.floor(Number(request.data?.requestedAmount || 0)));
  if (!resourceType || requestedAmount < 1) {
    throw new HttpsError("invalid-argument", "Demande de réserve invalide.");
  }
  const db = admin.firestore();
  const operationRef = worldcraftOperationRef(operationId);
  const reserveRef = db.collection("passageReserves").doc(campId);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const [previous, reserveSnapshot] = await Promise.all([transaction.get(operationRef), transaction.get(reserveRef)]);
    if (previous.exists) return previous.data().result;
    if (!reserveSnapshot.exists) throw new HttpsError("not-found", "Réserve de passage introuvable.");
    const reserve = reserveSnapshot.data();
    if (reserve.policy !== "open") throw new HttpsError("permission-denied", "Réserve de passage fermée.");
    const entries = {...(reserve.resourceEntries || {})};
    const entry = entries[resourceType] || {};
    const available = Math.max(0, Math.floor(Number(entry.availableQuantity || 0)));
    const maxPerTraveler = Math.max(0, Math.floor(Number(entry.maxPerTraveler || requestedAmount)));
    const claimedAmount = Math.min(available, requestedAmount, maxPerTraveler);
    entries[resourceType] = {...entry, availableQuantity: available - claimedAmount};
    const result = {campId, resourceType, claimedAmount};
    transaction.update(reserveRef, {resourceEntries: entries, updatedAt: now});
    transaction.create(operationRef, {id: operationId, type: "claimWorldcraftPassageReserve", actorId: playerId, createdAt: now, result});
    return result;
  });
});

exports.seedWorldcraftDebug = onCall(WORLDCRAFT_CALLABLE_OPTIONS, async (request) => {
  const uid = requireWorldcraftAuth(request);
  await requireWorldcraftDev(uid);
  const scenario = `${request.data?.scenario || ""}`;
  const db = admin.firestore();
  const now = Timestamp.now();
  const hourAgo = Timestamp.fromMillis(now.toMillis() - 4 * 3600000);
  const writes = db.batch();
  if (scenario === "d3-help") {
    const regionRef = db.collection("regions").doc("region-d3");
    const campId = "camp-debug-d3";
    writes.set(db.collection("camps").doc(campId), {
      id: campId, regionId: "region-d3", founderId: "debug-community", coreId: `${campId}-core`, buildingIds: [], storageId: `${campId}-storage`, state: "autonomous", simulationMode: "autonomous", macroStateId: campId, accessPolicy: "passage", foundedAt: now, lastActiveAt: hourAgo, lastSimulatedAt: hourAgo, simulationVersion: WORLDCRAFT_VERSION,
    }, {merge: true});
    writes.set(db.collection("campMacroStates").doc(campId), {campId, autonomy: 20, resilience: 20, foodSecurity: 10, infrastructureState: "fragile", populationPressure: 60, ecologicalSupport: 20, essentialFunctionsState: "strained", recentEventIds: ["drought-d3"], helpState: "drought", lastSimulatedAt: hourAgo, simulationVersion: WORLDCRAFT_VERSION}, {merge: true});
    writes.set(db.collection("helpRequests").doc("help-debug-d3-drought"), {id: "help-debug-d3-drought", campId, regionId: "region-d3", type: "drought", severity: 3, createdAt: now, expiresAt: Timestamp.fromMillis(now.toMillis() + 86400000), status: "open"}, {merge: true});
    writes.set(regionRef, {campId, occupancyState: "occupied"}, {merge: true});
  } else if (scenario === "e2-reserve") {
    writes.set(db.collection("passageReserves").doc("camp-debug-e2"), {id: "camp-debug-e2", campId: "camp-debug-e2", resourceEntries: {organic: {availableQuantity: 12, maxPerTraveler: 3}}, policy: "open", updatedAt: now}, {merge: true});
    writes.set(db.collection("regionMacroStates").doc("region-e2"), {ecologicalStateFuture: "high", restorationStateFuture: "restored", lastSimulatedAt: now}, {merge: true});
  } else if (scenario === "b4-exploitation") {
    writes.set(db.collection("regionMacroStates").doc("region-b4"), {exploitationPressure: 90, mineralReserveSummary: 10, lastSimulatedAt: now}, {merge: true});
  } else if (scenario === "c4-trace") {
    writes.set(db.collection("playerTraces").doc("trace-debug-c4"), {id: "trace-debug-c4", worldId: WORLD_ID, playerId: "debug-player", regionId: "region-c4", biomeId: null, traceType: "visit", createdAt: hourAgo, expiresAt: Timestamp.fromMillis(now.toMillis() + 20 * 3600000)}, {merge: true});
  } else if (scenario === "weather-front") {
    writes.set(db.collection("weatherCells").doc("weather-debug-front"), {id: "weather-debug-front", worldId: WORLD_ID, weatherType: "rain", intensity: 0.7, coveredRegionIds: ["region-b2", "region-b3", "region-c2", "region-c3"], startsAt: now, endsAt: Timestamp.fromMillis(now.toMillis() + 8 * 3600000), seed: 2026, status: "active"}, {merge: true});
  } else {
    throw new HttpsError("invalid-argument", "Scénario Worldcraft inconnu.");
  }
  await writes.commit();
  return {scenario, seededAt: now.toMillis()};
});
