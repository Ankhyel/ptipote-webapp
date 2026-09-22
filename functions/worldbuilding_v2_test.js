"use strict";

const assert = require("assert");
const {buildWorldbuildingMap} = require("./worldbuilding_v2");

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

console.log("Worldbuilding V2: carte, diversité, matrice et déterminisme validés.");
