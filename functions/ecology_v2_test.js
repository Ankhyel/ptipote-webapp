"use strict";

const assert = require("node:assert/strict");
const {
  HOUR_MS, ecologyDefaults, calculateBiomass, organicRegenMultiplier,
  getFloodThreshold, resolveBiomeEcology, addWasteDeposit,
} = require("./ecology_v2");

const startedAt = 1_700_000_000_000;
const standard = ecologyDefaults({biomeType: "savane_humide", nowMs: startedAt});
assert.equal(calculateBiomass({...standard, contamination: 0}).biologicalFloor, 10);
assert.equal(calculateBiomass({...standard, contamination: 50}).biologicalFloor, 5);
assert.equal(calculateBiomass({...standard, contamination: 100}).biologicalFloor, 0);
assert.ok(calculateBiomass({...standard, organicBiomassCapacity: 120}).biomass > 100, "La Biomasse n'est pas plafonnée à 100.");

const fullNode = {...standard, organicNodes: {a: {vitality: 10, biomassCapacity: 10, state: "active"}}, organicBiomassCapacity: 0};
assert.equal(calculateBiomass(fullNode).biomass, 20, "Un nœud plein contribue à sa capacité biologique.");
assert.equal(getFloodThreshold("semi_desert", "unstable"), 50);
assert.equal(getFloodThreshold("semi_desert", "stable"), 70);
assert.equal(getFloodThreshold("semi_desert", "resilient"), 100);

const rainy = resolveBiomeEcology({
  state: {...standard, lastEcologyResolvedAtMs: startedAt, humidity: 20}, biomeType: "semi_desert",
  targetMs: startedAt + HOUR_MS, weatherCells: [{weatherType: "rain", intensity: 1, startsAtMs: startedAt, endsAtMs: startedAt + 4 * HOUR_MS, status: "active"}],
});
assert.equal(Math.round(rainy.state.humidity), 27, "La pluie ajoute 9/h puis évaporation/drainage arides.");

const flooded = resolveBiomeEcology({
  state: {...standard, lastEcologyResolvedAtMs: startedAt, humidity: 60, organicNodes: {a: {vitality: 10, biomassCapacity: 10, state: "active"}}}, biomeType: "semi_desert",
  targetMs: startedAt + HOUR_MS,
});
assert.ok(flooded.state.organicNodes.a.vitality >= 5 && flooded.state.organicNodes.a.vitality < 6, "L'inondation retire 5 une seule fois par session avant la régénération continue.");
assert.ok(organicRegenMultiplier(flooded.state, "semi_desert").putrefaction < 1, "La putréfaction dure tant que le seuil est franchi.");

const oldWaste = addWasteDeposit({...standard, lastEcologyResolvedAtMs: startedAt}, {id: "w", quantity: 10, createdAtMs: startedAt});
const contaminated = resolveBiomeEcology({state: oldWaste, biomeType: "savane_humide", targetMs: startedAt + 4 * HOUR_MS, config: {contamination: {naturalBiomassThreshold: 999}}});
assert.equal(contaminated.state.contamination, 1, "10 Déchets produisent 1 Contamination après la grâce.");
const cleanedBeforeGrace = resolveBiomeEcology({state: addWasteDeposit({...standard, lastEcologyResolvedAtMs: startedAt}, {id: "fresh", quantity: 10, createdAtMs: startedAt + 2 * HOUR_MS}), biomeType: "savane_humide", targetMs: startedAt + 4 * HOUR_MS});
assert.equal(cleanedBeforeGrace.state.contamination, 0, "Les Déchets récents respectent les 3 h de grâce.");

const deterministicInput = {...standard, lastEcologyResolvedAtMs: startedAt, humidity: 40, contamination: 30};
const one = resolveBiomeEcology({state: deterministicInput, biomeType: "savane_humide", targetMs: startedAt + 24 * HOUR_MS});
const two = resolveBiomeEcology({state: deterministicInput, biomeType: "savane_humide", targetMs: startedAt + 24 * HOUR_MS});
assert.deepEqual(one, two, "La résolution offline est déterministe.");

const severeWeather = {weatherType: "torrentialRain", id: "weather-test", startsAtMs: startedAt, endsAtMs: startedAt + HOUR_MS, status: "active"};
const severeDestroyed = resolveBiomeEcology({
  state: {...standard, lastEcologyResolvedAtMs: startedAt, organicNodes: {depleted: {id: "depleted", vitality: 0, biomassCapacity: 10, state: "depleted"}}},
  biomeType: "savane_humide", targetMs: startedAt + HOUR_MS, weatherCells: [severeWeather],
  config: {organic: {severeWeatherDestructionChance: 1}},
});
assert.equal(severeDestroyed.state.organicNodes.depleted.state, "destroyed", "Une météo sévère détruit de manière déterministe un nœud déjà épuisé lorsque la probabilité configurée le décide.");

const recreated = resolveBiomeEcology({
  state: {...standard, organicBiomassCapacity: 100, lastEcologyResolvedAtMs: startedAt, organicNodes: {slot: {id: "slot", vitality: 0, biomassCapacity: 10, state: "destroyed", depletionAtMs: []}}},
  biomeType: "savane_humide", targetMs: startedAt + 120 * HOUR_MS,
});
assert.equal(recreated.state.organicNodes.slot.state, "active", "La recréation naturelle réutilise un emplacement biologique connu.");
assert.equal(recreated.state.organicNodes.slot.vitality, 10);

console.log("Ecology V2: biomasse, humidité, inondation, déchets et déterminisme validés.");
