"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {
  buildWorldbuildingMap, composeRegion, rankedCandidates, runtimeConfig,
} = require("./worldbuilding_v2");

const first = buildWorldbuildingMap({}, 250525);
const replay = buildWorldbuildingMap({}, 250525);

assert.strictEqual(first.regions.length, 25, "La carte contient 25 Régions.");
assert.deepStrictEqual(first, replay, "La génération est stable pour une même seed.");
assert.strictEqual(first.regions.find((region) => region.coordinate === "C3").profile, "highRefuge");

for (const region of first.regions) {
  const positions = Object.keys(region.biomeTypesByPosition).sort();
  assert.deepStrictEqual(positions, ["a1", "a2", "a3", "b1", "b3"]);
  assert.strictEqual(Object.values(region.biomeTypesByPosition).length, 5);
  assert.ok(new Set(Object.values(region.biomeTypesByPosition)).size >= 3,
    `${region.coordinate} conserve au moins trois Biomes distincts.`);
}

assert.strictEqual(first.regions.find((region) => region.coordinate === "A1").profile, "highRefuge");
assert.strictEqual(first.regions.find((region) => region.coordinate === "E1").profile, "dry");
assert.strictEqual(first.regions.find((region) => region.coordinate === "A5").profile, "coastal");
assert.ok(!first.warnings.some((warning) => warning.type === "overrepresentation"),
  "Aucun Biome ne dépasse le seuil de représentation configuré.");

const dashboardConfig = JSON.parse(fs.readFileSync(
  path.join(__dirname, "../ptipote-dashboard/worldbuilding-v2-config.json"), "utf8"));
const dashboardMap = buildWorldbuildingMap(dashboardConfig, 250525);
assert.equal(dashboardMap.config.selectionWeights.ownProfile, 8);
for (const region of dashboardMap.regions) {
  for (const type of Object.values(region.biomeTypesByPosition)) {
    assert.ok(dashboardMap.config.biomes[type].compatibleRegionProfiles.includes(region.profile),
      `${type} est compatible avec ${region.profile}.`);
    assert.ok(dashboardMap.config.biomes[type].parcelGenerationProfile,
      `${type} possède un profil de génération de Parcelles.`);
  }
}

// The stable world seed is not the sole input: the coordinate offset and the
// neighbouring profile weights are independently observable and deterministic.
const coordinateConfig = runtimeConfig({
  generationSeedOffsets: first.config.generationSeedOffsets.map((row) => [...row]),
});
coordinateConfig.generationSeedOffsets[2][2] += 1;
const originalC3 = composeRegion(first.config, {worldSeed: 250525, x: 2, y: 2});
const offsetC3 = composeRegion(coordinateConfig, {worldSeed: 250525, x: 2, y: 2});
assert.notDeepStrictEqual(originalC3.biomeTypesByPosition, offsetC3.biomeTypesByPosition,
  "Un offset de coordonnée modifie la composition déterministe.");

const nextWorldbuilding = buildWorldbuildingMap({
  worldbuildingVersion: "WORLDBUILDING_0_2_TEST",
}, 250525);
assert.notDeepStrictEqual(
  first.regions.map((region) => region.biomeTypesByPosition),
  nextWorldbuilding.regions.map((region) => region.biomeTypesByPosition),
  "La version Worldbuilding participe elle aussi au déterminisme.");

const neighbourOnly = runtimeConfig({
  selectionWeights: {ownProfile: 0, ownNear: 0, neighborProfile: 100, neighborNear: 0},
});
const highNeighbours = rankedCandidates(neighbourOnly, "mixed", ["highRefuge"], "near", "test");
const dryNeighbours = rankedCandidates(neighbourOnly, "mixed", ["dry"], "near", "test");
assert.notDeepStrictEqual(highNeighbours, dryNeighbours,
  "Le profil d’une Région voisine influence les candidats du Biome.");

for (const definition of Object.values(dashboardMap.config.biomes)) {
  assert.ok(definition.visualProfileId, "Chaque Biome possède un visualProfileId stable.");
  assert.ok(definition.parcelGenerationProfileId,
    "Chaque Biome possède un parcelGenerationProfileId stable.");
  assert.ok(Array.isArray(definition.neighborCompatibility),
    "Chaque Biome expose sa compatibilité de voisinage déclarative.");
}

console.log("Worldbuilding V2: carte, diversité, matrice et déterminisme validés.");
