/* eslint-disable no-console */
// End-to-end callable checks against Firebase emulators. This intentionally
// uses two authenticated test accounts and server-only fixtures; no production
// credential or production document is touched.
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const projectId = process.env.GCLOUD_PROJECT || "ptipote-13508";
const functionsBase = `http://127.0.0.1:5001/${projectId}/europe-west9`;

async function createUser() {
  const response = await fetch(
    "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key",
    {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({returnSecureToken: true})},
  );
  if (!response.ok) {
    throw new Error(`Création compte émulateur: ${await response.text()}`);
  }
  return response.json();
}

async function callable(token, name, data) {
  const response = await fetch(`${functionsBase}/${name}`, {
    method: "POST",
    headers: {"Content-Type": "application/json", Authorization: `Bearer ${token}`},
    body: JSON.stringify({data}),
  });
  const payload = await response.json();
  if (!response.ok) throw Object.assign(new Error(payload.error?.message || "Callable refusée"), {payload});
  return payload.result;
}

async function main() {
  const first = await createUser();
  const second = await createUser();
  if (admin.apps.length === 0) admin.initializeApp({projectId});
  const db = admin.firestore();
  await db.collection("users").doc(first.localId).set({role: "dev"}, {merge: true});
  await callable(first.idToken, "ensureWorldcraftWorld", {});
  const worldbuilding = await callable(first.idToken, "upgradeWorldcraftWorldbuilding", {
    operationId: "emulator-worldbuilding-001",
  });
  assert.equal(worldbuilding.upgradedRegions, 25, "Worldbuilding met à jour les 25 Régions");
  const worldbuildingReplay = await callable(first.idToken, "upgradeWorldcraftWorldbuilding", {
    operationId: "emulator-worldbuilding-001",
  });
  assert.deepEqual(worldbuildingReplay, worldbuilding, "Worldbuilding est idempotent");
  const upgradedBiome = await db.collection("biomeSharedStates").doc("region-c3-biome-1").get();
  assert.ok(upgradedBiome.data().visualProfile, "le profil visuel est persistant");
  const upgradedRegion = await db.collection("regions").doc("region-c3").get();
  assert.equal(upgradedRegion.data().biomeSummaries.length, 5,
    "la Région fournit son résumé léger de cinq Biomes");
  assert.ok(upgradedRegion.data().biomeSummaries.every((biome) => biome.seed),
    "les seeds de Biome sont visibles sans charger les états détaillés");

  const creates = await Promise.allSettled([
    callable(first.idToken, "createCampInRegion", {operationId: "emulator-camp-a-001", regionId: "region-a1"}),
    callable(second.idToken, "createCampInRegion", {operationId: "emulator-camp-b-001", regionId: "region-a1"}),
  ]);
  assert.equal(creates.filter((result) => result.status === "fulfilled").length, 1, "une seule fondation concurrente doit réussir");
  const winnerIndex = creates[0].status === "fulfilled" ? 0 : 1;
  const created = creates[winnerIndex].value;
  const replay = await callable(
    winnerIndex === 0 ? first.idToken : second.idToken,
    "createCampInRegion",
    {operationId: winnerIndex === 0 ? "emulator-camp-a-001" : "emulator-camp-b-001", regionId: "region-a1"},
  );
  assert.equal(replay.campId, created.campId, "un operationId rejoué doit retourner le même Camp");

  const extracts = await Promise.all([
    callable(first.idToken, "extractSharedResource", {operationId: "emulator-extract-a-001", biomeId: "region-b1-biome-1", requestedAmount: 150}),
    callable(second.idToken, "extractSharedResource", {operationId: "emulator-extract-b-001", biomeId: "region-b1-biome-1", requestedAmount: 150}),
  ]);
  assert.equal(extracts[0].actualExtracted + extracts[1].actualExtracted, 200, "la réserve finie ne doit jamais devenir négative");
  const extractReplay = await callable(first.idToken, "extractSharedResource", {operationId: "emulator-extract-a-001", biomeId: "region-b1-biome-1", requestedAmount: 150});
  assert.equal(extractReplay.actualExtracted, extracts[0].actualExtracted, "extraction idempotente");

  await db.collection("passageReserves").doc(created.campId).set({
    id: created.campId, campId: created.campId, policy: "open",
    resourceEntries: {mineral: {availableQuantity: 10, maxPerTraveler: 10}},
    updatedAt: admin.firestore.Timestamp.now(),
  }, {merge: true});
  const claims = await Promise.all([
    callable(first.idToken, "claimWorldcraftPassageReserve", {operationId: "emulator-reserve-a-001", campId: created.campId, resourceType: "mineral", requestedAmount: 8}),
    callable(second.idToken, "claimWorldcraftPassageReserve", {operationId: "emulator-reserve-b-001", campId: created.campId, resourceType: "mineral", requestedAmount: 8}),
  ]);
  assert.equal(claims[0].claimedAmount + claims[1].claimedAmount, 10, "réserve de passage atomique");
  const claimReplay = await callable(first.idToken, "claimWorldcraftPassageReserve", {operationId: "emulator-reserve-a-001", campId: created.campId, resourceType: "mineral", requestedAmount: 8});
  assert.equal(claimReplay.claimedAmount, claims[0].claimedAmount, "claim idempotent");
  console.log("Worldcraft emulator concurrency checks passed.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
