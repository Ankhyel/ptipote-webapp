const admin = require("firebase-admin");
const {Timestamp} = require("firebase-admin/firestore");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

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

function worldcraftProfileAt(x, y) {
  const grid = [
    ["highRefuge", "highRefuge", "highRefuge", "highRefuge", "dry"],
    ["highRefuge", "transition", "highRefuge", "transition", "dry"],
    ["coastal", "mixed", "highRefuge", "mixed", "dry"],
    ["coastal", "transition", "mixed", "transition", "dry"],
    ["coastal", "coastal", "coastal", "coastal", "dry"],
  ];
  return grid[y][x];
}

function worldcraftBiomeComposition(profile) {
  return {
    highRefuge: ["haut_refuge", "colline", "foret_humide", "savane_humide", "foret_seche"],
    coastal: ["littoral", "mangrove", "marais", "savane_humide", "foret_humide"],
    dry: ["semi_desert", "savane_seche", "foret_seche", "colline", "marais"],
    mixed: ["savane_humide", "marais", "colline", "foret_seche", "littoral"],
    transition: ["savane_humide", "colline", "savane_seche", "foret_seche", "marais"],
  }[profile];
}

function worldcraftSeed(value) {
  let hash = 17;
  for (const code of `${value}`) hash = (hash * 31 + code.charCodeAt(0)) & 0x7fffffff;
  return hash;
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

function biomeSharedState(regionId, biomeId, biomeType, now) {
  return {
    regionId,
    biomeId,
    biomeType,
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
  };
}

exports.ensureWorldcraftWorld = onCall({region: "europe-west9"}, async (request) => {
  requireWorldcraftAuth(request);
  const db = admin.firestore();
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
        const profile = worldcraftProfileAt(x, y);
        const biomeIds = Array.from({length: 5}, (_, index) => `${regionId}-biome-${index + 1}`);
        transaction.set(db.collection("regions").doc(regionId), {
          id: regionId,
          worldId: WORLD_ID,
          worldMapId: WORLD_MAP_ID,
          coordinateX: x,
          coordinateY: y,
          displayCoordinate: coordinate,
          profile,
          seed: worldcraftSeed(`250525:${regionId}`),
          biomeIds,
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
        const biomes = worldcraftBiomeComposition(profile);
        biomes.forEach((biomeType, index) => {
          const biomeId = biomeIds[index];
          transaction.set(db.collection("biomeSharedStates").doc(biomeId),
            biomeSharedState(regionId, biomeId, biomeType, now));
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
  });
  return {worldId: WORLD_ID, worldMapId: WORLD_MAP_ID};
});

exports.createCampInRegion = onCall({region: "europe-west9"}, async (request) => {
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

exports.resolveWorldcraftRegionUntil = onCall({region: "europe-west9"}, async (request) => {
  requireWorldcraftAuth(request);
  const regionId = `${request.data?.regionId || ""}`;
  const db = admin.firestore();
  const regionRef = db.collection("regions").doc(regionId);
  const macroRef = db.collection("regionMacroStates").doc(regionId);
  const now = Timestamp.now();
  const config = await loadWorldcraftRuntimeConfig(db);
  const [weatherSnapshot, cleanedTraceCount] = await Promise.all([
    db.collection("weatherCells").where("coveredRegionIds", "array-contains", regionId).get(),
    cleanupExpiredWorldcraftTraces(db, regionId, now, config.lazyTraceCleanupLimit),
  ]);
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
    // Ecology formulas remain deferred. Weather is nevertheless resolved from
    // timestamped shared cells, independently from an open client screen.
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
    };
  });
});

exports.setWorldcraftCampMode = onCall({region: "europe-west9"}, async (request) => {
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

exports.resolveWorldcraftCampUntil = onCall({region: "europe-west9"}, async (request) => {
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

exports.helpWorldcraftCampConstruction = onCall({region: "europe-west9"}, async (request) => {
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

exports.contributeWorldcraftCampConstruction = onCall({region: "europe-west9"}, async (request) => {
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
exports.flushWorldcraftCampStorage = onCall({region: "europe-west9"}, async (request) => {
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

exports.extractSharedResource = onCall({region: "europe-west9"}, async (request) => {
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
    const result = {operationId, biomeId, requestedAmount, actualExtracted};
    transaction.update(biomeRef, {
      mineralReserveSummary: available - actualExtracted,
      exploitationPressure: Number(state.exploitationPressure || 0) + actualExtracted,
      lastSimulatedAt: now,
    });
    transaction.create(operationRef, {id: operationId, type: "extractSharedResource", actorId: playerId, createdAt: now, result});
    return result;
  });
});

exports.adjustWorldcraftBiomeDanger = onCall({region: "europe-west9"}, async (request) => {
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

exports.recordWorldcraftTrace = onCall({region: "europe-west9"}, async (request) => {
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

exports.claimWorldcraftPassageReserve = onCall({region: "europe-west9"}, async (request) => {
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

exports.seedWorldcraftDebug = onCall({region: "europe-west9"}, async (request) => {
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
