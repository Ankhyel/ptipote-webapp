"use strict";

// ECOLOGY_0_1 is deliberately a deterministic, side-effect-free resolver.
// Firestore transactions decide *when* it is applied; this module only
// describes the same physical outcome for the same initial state and time.

const ECOLOGY_VERSION = "ECOLOGY_0_1";
const HOUR_MS = 60 * 60 * 1000;
const SESSION_HOURS = 4;

const DEFAULT_CONFIG = Object.freeze({
  version: ECOLOGY_VERSION,
  biomass: {
    baseBiologicalFloor: 10,
    curve: [[0, 0.10], [15, 0.15], [20, 0.25], [30, 0.50], [50, 0.75], [71, 1], [100, 1], [110, 1.10], [120, 1.20]],
    naturalRecreateThreshold: 90,
    naturalRecreateHours: 120,
    maxNaturalRecreatesPerBiome: 1,
  },
  organic: {
    maxVitality: 10,
    nodeBiomassCapacity: 10,
    simpleBiomeOrganicCapacity: 80,
    regenHours: 12,
    depletionWindowHours: 48,
    destructionDepletions: 3,
    weatherDestroyedAtZeroChance: 0,
    putrefactionMultiplier: 0.90,
  },
  humidity: {
    ranges: {
      marsh: [70, 95], mangrove: [65, 90], humidForest: [60, 85], humidSavanna: [45, 70],
      coastal: [40, 70], hill: [35, 60], highRefuge: [35, 60], dryForest: [30, 55],
      drySavanna: [20, 45], semiDesert: [10, 30],
    },
    evaporationPerHour: {default: 1.1, dry: 1.8, wet: 0.7},
    drainagePerHour: {default: 0.7, dry: 0.35, wet: 1.1},
    floodThresholds: {default: {unstable: 85, stable: 100, resilient: 120}, semiDesert: {unstable: 50, stable: 70, resilient: 100}},
    rainfallPerHour: {rain: 9, heavyRain: 15, torrentialRain: 20},
  },
  waste: {graceHours: 3, contaminationPerTenWastePerSession: 1},
  contamination: {
    organicRegenCurve: [[0, 1], [20, 1], [21, .9], [40, .9], [41, .75], [60, .75], [61, .5], [80, .5], [81, .25], [100, .25]],
    naturalBiomassThreshold: 80, naturalMaximumContamination: 60, naturalReductionPerHour: 1,
  },
  mineral: {surfaceWastePerTenExtracted: 1},
  mine: {
    deepReserve: 2000,
    cadences: {gentle: {multiplier: .5, pressurePerTen: .5}, normal: {multiplier: 1, pressurePerTen: 1}, intensive: {multiplier: 2, pressurePerTen: 2}},
    wastePerTenExtracted: 1, directContaminationPerTenExtracted: 1,
  },
  qualitative: {
    biomass: [[15, "Critique"], [50, "Faible"], [80, "Stable"], [100, "Abondante"], [Infinity, "Foisonnante"]],
    humidity: [[20, "Très sèche"], [40, "Sèche"], [70, "Favorable"], [100, "Humide"], [Infinity, "Saturée"]],
    contamination: [[20, "Faible"], [60, "Présente"], [80, "Forte"], [Infinity, "Critique"]],
  },
});

function clone(value) { return JSON.parse(JSON.stringify(value)); }
function merge(base, override) {
  if (Array.isArray(base)) return Array.isArray(override) ? override : clone(base);
  if (base && typeof base === "object") {
    const source = override && typeof override === "object" ? override : {};
    return Object.fromEntries(Object.entries(base).map(([key, value]) => [key, merge(value, source[key])]));
  }
  return override === undefined || override === null ? base : override;
}
function runtimeConfig(source) { return merge(DEFAULT_CONFIG, source || {}); }
function number(value, fallback = 0) { const result = Number(value); return Number.isFinite(result) ? result : fallback; }
function clamp(value, min, max) { return Math.max(min, Math.min(max, value)); }
function interpolate(points, input) {
  const sorted = [...points].sort((left, right) => left[0] - right[0]);
  if (input <= sorted[0][0]) return sorted[0][1];
  for (let index = 1; index < sorted.length; index += 1) {
    const [rightX, rightY] = sorted[index]; const [leftX, leftY] = sorted[index - 1];
    if (input <= rightX) return leftY + ((input - leftX) / (rightX - leftX)) * (rightY - leftY);
  }
  return sorted.at(-1)[1];
}
function biomeFamily(type) {
  const key = `${type || ""}`.replace(/[ _-]/g, "").toLowerCase();
  return ({marais: "marsh", mangrove: "mangrove", foretHumide: "humidForest", foresthumid: "humidForest", savaneHumide: "humidSavanna", humidSavanna: "humidSavanna", littoral: "coastal", coastal: "coastal", colline: "hill", hill: "hill", hautrefuge: "highRefuge", highrefuge: "highRefuge", foretSeche: "dryForest", dryforest: "dryForest", savaneSeche: "drySavanna", drysavanna: "drySavanna", semidesert: "semiDesert"})[key] || "default";
}
function ecologyDefaults({biomeType, nowMs, config: source, existing = {}}) {
  const config = runtimeConfig(source);
  const organicNodes = existing.organicNodes && typeof existing.organicNodes === "object" ? clone(existing.organicNodes) : {};
  return {
    ecologyVersion: ECOLOGY_VERSION,
    biomass: number(existing.biomass, config.biomass.baseBiologicalFloor + config.organic.simpleBiomeOrganicCapacity),
    biologicalFloor: number(existing.biologicalFloor, config.biomass.baseBiologicalFloor),
    humidity: number(existing.humidity, 50),
    contamination: clamp(number(existing.contamination, 0), 0, 100),
    wasteQuantity: Math.max(0, number(existing.wasteQuantity, 0)),
    wasteContaminationRemainder: Math.max(0, number(existing.wasteContaminationRemainder, 0)),
    wasteDeposits: existing.wasteDeposits && typeof existing.wasteDeposits === "object" ? clone(existing.wasteDeposits) : {},
    mineralReserveSummary: Math.max(0, number(existing.mineralReserveSummary, 200)),
    deepMineralReserve: Math.max(0, number(existing.deepMineralReserve, config.mine.deepReserve)),
    exploitationPressure: Math.max(0, number(existing.exploitationPressure, 0)),
    mineState: existing.mineState && typeof existing.mineState === "object" ? clone(existing.mineState) : {enabled: false, cadence: "normal", automated: false, actorType: null},
    organicNodes,
    organicBiomassCapacity: Math.max(0, number(existing.organicBiomassCapacity, config.organic.simpleBiomeOrganicCapacity)),
    lastNaturalOrganicRecreateAtMs: number(existing.lastNaturalOrganicRecreateAtMs, 0),
    lastEcologyResolvedAtMs: number(existing.lastEcologyResolvedAtMs, nowMs),
    floodedSessionIds: Array.isArray(existing.floodedSessionIds) ? existing.floodedSessionIds.slice(-12) : [],
    appliedEcologyEffects: existing.appliedEcologyEffects && typeof existing.appliedEcologyEffects === "object" ? clone(existing.appliedEcologyEffects) : {},
    biomeType,
  };
}
function calculateBiomass(state, source) {
  const config = runtimeConfig(source);
  const contamination = clamp(number(state.contamination), 0, 100);
  const floor = config.biomass.baseBiologicalFloor * (1 - contamination / 100);
  const defaultCapacity = Math.max(0, number(state.organicBiomassCapacity, config.organic.simpleBiomeOrganicCapacity));
  const nodes = Object.values(state.organicNodes || {});
  const trackedCapacity = nodes.reduce((sum, node) => sum + number(node.biomassCapacity, config.organic.nodeBiomassCapacity), 0);
  const trackedContribution = nodes.reduce((sum, node) => {
    if (node.state === "destroyed") return sum;
    return sum + clamp(number(node.vitality), 0, config.organic.maxVitality) / config.organic.maxVitality * number(node.biomassCapacity, config.organic.nodeBiomassCapacity);
  }, 0);
  // The first player to inspect a Parcel progressively materialises its stable
  // local node ids. Unseen slots retain their contribution, so discovering one
  // node never makes a living Biome collapse from 90 to 20 Biomasse.
  const contribution = Math.max(0, defaultCapacity - trackedCapacity) + trackedContribution;
  return {biologicalFloor: floor, organicContribution: contribution, biomass: floor + contribution};
}
function organicRegenMultiplier(state, biomeType, source, weatherMultiplier = 1) {
  const config = runtimeConfig(source); const family = biomeFamily(biomeType);
  const [minimum, maximum] = config.humidity.ranges[family] || [35, 65];
  const humidity = number(state.humidity);
  const humidityMultiplier = humidity >= minimum && humidity <= maximum ? 1 : humidity >= minimum - 10 && humidity <= maximum + 10 ? .85 : .60;
  const contaminationMultiplier = interpolate(config.contamination.organicRegenCurve, clamp(number(state.contamination), 0, 100));
  const biomassMultiplier = interpolate(config.biomass.curve, number(state.biomass));
  const floodThreshold = getFloodThreshold(biomeType, state.ecologyState || "unstable", config);
  const putrefaction = humidity > floodThreshold ? config.organic.putrefactionMultiplier : 1;
  return {biomassMultiplier, humidityMultiplier, contaminationMultiplier, weatherMultiplier, putrefaction, value: biomassMultiplier * humidityMultiplier * contaminationMultiplier * weatherMultiplier * putrefaction};
}
function getFloodThreshold(biomeType, ecologyState, source) {
  const config = runtimeConfig(source); const family = biomeFamily(biomeType); const states = config.humidity.floodThresholds[family] || config.humidity.floodThresholds.default;
  return number(states[ecologyState] ?? states.unstable, 85);
}
function weatherRate(cell, biomeType, source) {
  const config = runtimeConfig(source); const raw = `${cell?.weatherType || ""}`.toLowerCase();
  const rain = raw.includes("torrential") || raw.includes("torrent") ? "torrentialRain" : raw.includes("heavy") || raw.includes("forte") ? "heavyRain" : raw.includes("rain") || raw.includes("pluie") ? "rain" : null;
  if (!rain) return {humidityDelta: 0, regenMultiplier: 1, severe: false};
  const response = cell?.biomeResponses?.[biomeFamily(biomeType)] || cell?.weatherResponseProfile || {};
  const responseMultiplier = clamp(number(response.rainMultiplier ?? response.humidityMultiplier ?? cell?.intensity, 1), 0, 3);
  return {humidityDelta: config.humidity.rainfallPerHour[rain] * responseMultiplier, regenMultiplier: 1, severe: rain === "torrentialRain"};
}
function weatherForHour(cells, timestampMs) {
  return (cells || []).filter((cell) => number(cell.startsAtMs ?? cell.startsAt?.toMillis?.()) <= timestampMs && number(cell.endsAtMs ?? cell.endsAt?.toMillis?.()) > timestampMs && cell.status !== "expired");
}
function resolveBiomeEcology({state: input, biomeType, targetMs, weatherCells = [], config: source}) {
  const config = runtimeConfig(source); const state = ecologyDefaults({biomeType, nowMs: targetMs, config, existing: input});
  const start = state.lastEcologyResolvedAtMs; const end = Math.max(start, number(targetMs, start));
  const effects = [];
  for (let hour = Math.floor(start / HOUR_MS) * HOUR_MS; hour < end; hour += HOUR_MS) {
    const hourStart = Math.max(hour, start); const hourEnd = Math.min(hour + HOUR_MS, end); const ratio = (hourEnd - hourStart) / HOUR_MS;
    const cells = weatherForHour(weatherCells, hourStart); const weather = cells.reduce((total, cell) => {
      const rate = weatherRate(cell, biomeType, config); total.humidityDelta += rate.humidityDelta; total.regenMultiplier *= rate.regenMultiplier; total.severe ||= rate.severe; return total;
    }, {humidityDelta: 0, regenMultiplier: 1, severe: false});
    const family = biomeFamily(biomeType); const dry = ["drySavanna", "semiDesert", "dryForest"].includes(family); const wet = ["marsh", "mangrove", "humidForest"].includes(family);
    state.humidity = Math.max(0, number(state.humidity) + weather.humidityDelta * ratio - number(config.humidity.evaporationPerHour[dry ? "dry" : wet ? "wet" : "default"]) * ratio - number(config.humidity.drainagePerHour[dry ? "dry" : wet ? "wet" : "default"]) * ratio);
    const sessionId = `${Math.floor(hour / (SESSION_HOURS * HOUR_MS))}`;
    const floodThreshold = getFloodThreshold(biomeType, state.ecologyState || "unstable", config);
    if (state.humidity > floodThreshold && !state.floodedSessionIds.includes(sessionId)) {
      state.floodedSessionIds.push(sessionId); state.floodedSessionIds = state.floodedSessionIds.slice(-12);
      Object.values(state.organicNodes).forEach((node) => { if (node.state !== "destroyed") node.vitality = Math.max(0, number(node.vitality) - 5); });
      effects.push({type: "flood", sessionId});
    }
    const calculated = calculateBiomass(state, config); state.biomass = calculated.biomass; state.biologicalFloor = calculated.biologicalFloor;
    const regen = organicRegenMultiplier(state, biomeType, config, weather.regenMultiplier).value;
    const vitalityPerHour = config.organic.maxVitality / config.organic.regenHours * regen * ratio;
    Object.values(state.organicNodes).forEach((node) => {
      if (node.state === "destroyed") return;
      node.vitality = clamp(number(node.vitality) + vitalityPerHour, 0, config.organic.maxVitality);
      if (node.vitality > 0 && node.state === "depleted") node.state = "active";
    });
    if (weather.severe) Object.values(state.organicNodes).forEach((node) => {
      if (node.state === "depleted" && number(config.organic.weatherDestroyedAtZeroChance) >= 1) node.state = "destroyed";
    });
    if (hourEnd % (SESSION_HOURS * HOUR_MS) === 0 || hourEnd === end) {
      const contaminatingWaste = Object.values(state.wasteDeposits).reduce((sum, deposit) => number(deposit.createdAtMs) + config.waste.graceHours * HOUR_MS <= hourEnd ? sum + number(deposit.quantity) : sum, 0);
      const generated = contaminatingWaste / 10 * config.waste.contaminationPerTenWastePerSession + number(state.wasteContaminationRemainder);
      const whole = Math.floor(generated); state.wasteContaminationRemainder = generated - whole; state.contamination = clamp(number(state.contamination) + whole, 0, 100);
    }
    const after = calculateBiomass(state, config); state.biomass = after.biomass; state.biologicalFloor = after.biologicalFloor;
    if (state.biomass > config.contamination.naturalBiomassThreshold && state.contamination < config.contamination.naturalMaximumContamination) state.contamination = clamp(state.contamination - config.contamination.naturalReductionPerHour * ratio, 0, 100);
  }
  const calculated = calculateBiomass(state, config); state.biomass = calculated.biomass; state.biologicalFloor = calculated.biologicalFloor;
  if (state.biomass >= config.biomass.naturalRecreateThreshold && end - state.lastNaturalOrganicRecreateAtMs >= config.biomass.naturalRecreateHours * HOUR_MS) {
    const period = Math.floor(end / (config.biomass.naturalRecreateHours * HOUR_MS));
    const nodeId = `natural-organic-${period}`;
    state.organicNodes[nodeId] = {
      id: nodeId,
      vitality: config.organic.maxVitality,
      biomassCapacity: config.organic.nodeBiomassCapacity,
      state: "active",
      depletionAtMs: [],
      createdAtMs: end,
      origin: "natural-recreation",
    };
    state.lastNaturalOrganicRecreateAtMs = end;
    effects.push({type: "organic-recreated", nodeId, maximum: config.biomass.maxNaturalRecreatesPerBiome});
  }
  state.lastEcologyResolvedAtMs = end; state.ecologyVersion = ECOLOGY_VERSION;
  return {state, effects, nextResolutionAtMs: Math.ceil(end / HOUR_MS) * HOUR_MS};
}
function addWasteDeposit(state, {id, quantity, createdAtMs}) {
  const next = clone(state); next.wasteDeposits ||= {}; if (!next.wasteDeposits[id]) next.wasteDeposits[id] = {id, quantity: 0, createdAtMs}; next.wasteDeposits[id].quantity += Math.max(0, number(quantity)); next.wasteQuantity = Object.values(next.wasteDeposits).reduce((sum, item) => sum + number(item.quantity), 0); return next;
}
function qualitative(value, categories) { return categories.find(([limit]) => value <= limit)?.[1] || categories.at(-1)?.[1]; }
function qualitativeEcology(state, source) { const config = runtimeConfig(source); return {biomass: qualitative(number(state.biomass), config.qualitative.biomass), humidity: qualitative(number(state.humidity), config.qualitative.humidity), contamination: qualitative(number(state.contamination), config.qualitative.contamination)}; }

module.exports = {ECOLOGY_VERSION, HOUR_MS, SESSION_HOURS, DEFAULT_CONFIG, runtimeConfig, ecologyDefaults, calculateBiomass, organicRegenMultiplier, getFloodThreshold, resolveBiomeEcology, addWasteDeposit, qualitativeEcology, clamp, number};
