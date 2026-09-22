"use strict";

// Worldbuilding 0 remains deliberately small: it defines geographic content,
// not ecology, economy or terrain simulation. The Dashboard can override this
// baseline through gameConfigs/zone0.zone0Settings.worldbuildingV2.

const INTERNAL_POSITIONS = ["b1", "a1", "a2", "a3", "b3"];
const NEAR_POSITIONS = new Set(["b1", "a2", "b3"]);
const DEFAULT_MATRIX = [
  ["highRefuge", "highRefuge", "highRefuge", "highRefuge", "dry"],
  ["highRefuge", "transition", "highRefuge", "transition", "dry"],
  ["coastal", "mixed", "highRefuge", "mixed", "dry"],
  ["coastal", "transition", "mixed", "transition", "dry"],
  ["coastal", "coastal", "coastal", "coastal", "dry"],
];

const DEFAULT_PROFILE_POOLS = {
  highRefuge: {near: ["colline", "foret_humide", "savane_humide", "foret_seche"], far: ["haut_refuge", "colline", "foret_humide"], required: ["haut_refuge"]},
  coastal: {near: ["littoral", "mangrove", "marais", "savane_humide", "foret_humide"], far: ["littoral", "mangrove", "marais"], required: ["littoral"]},
  dry: {near: ["savane_seche", "foret_seche", "colline", "savane_humide"], far: ["semi_desert", "savane_seche", "foret_seche"], required: ["semi_desert"]},
  mixed: {near: ["savane_humide", "foret_humide", "colline", "savane_seche", "foret_seche", "littoral"], far: ["colline", "foret_seche", "mangrove", "semi_desert"], required: []},
  transition: {near: ["savane_humide", "foret_humide", "colline", "savane_seche", "foret_seche", "marais"], far: ["colline", "marais", "savane_seche", "semi_desert"], required: []},
};

function definition(tags, ground, vegetation, rocks, weather, ecology) {
  return {
    environmentalTags: tags,
    visualProfile: {
      groundSet: ground,
      vegetationSet: vegetation,
      rockSet: rocks,
      organicNodeVariants: [vegetation],
      mineralNodeVariants: [rocks],
      wasteVisualVariants: ["debris"],
      environmentalProps: [vegetation, rocks],
      ambienceTags: tags.map((tag) => tag.toLowerCase()),
    },
    weatherResponseProfile: {rain: weather},
    ecologyProfileId: ecology,
    possibleFindingTables: [ecology],
  };
}

const DEFAULT_BIOMES = {
  littoral: definition(["COASTAL", "OPEN", "WET"], "shore", "coastal_grass", "pale_rocks", "medium", "coastal"),
  mangrove: definition(["COASTAL", "WET", "FORESTED"], "wet_roots", "mangrove", "dark_roots", "high", "wetland"),
  marais: definition(["WET", "OPEN"], "marsh", "reeds", "mud_rock", "high", "wetland"),
  savane_humide: definition(["OPEN", "WET"], "green_grass", "tall_grass", "warm_rocks", "medium", "savanna_wet"),
  savane_seche: definition(["OPEN", "DRY"], "dry_grass", "short_grass", "ochre_rocks", "low", "savanna_dry"),
  semi_desert: definition(["OPEN", "DRY", "ROCKY"], "sand", "sparse_shrubs", "desert_rocks", "low", "arid"),
  colline: definition(["ROCKY", "OPEN"], "hillside", "shrubs", "ridge_rocks", "medium", "hills"),
  foret_seche: definition(["FORESTED", "DRY"], "leaf_litter", "dry_forest", "root_rocks", "low", "forest_dry"),
  foret_humide: definition(["FORESTED", "WET"], "moss", "wet_forest", "moss_rocks", "high", "forest_wet"),
  haut_refuge: definition(["ROCKY", "HIGH_ALTITUDE"], "highland", "alpine_grass", "dark_rocks", "medium", "highland"),
};

const DEFAULT_WORLDBUILDING_CONFIG = Object.freeze({
  worldbuildingVersion: "WORLDBUILDING_0_1",
  minimumDistinctBiomes: 3,
  internalPositions: INTERNAL_POSITIONS,
  regionProfileMatrix: DEFAULT_MATRIX,
  generationSeedOffsets: [
    [101, 102, 103, 104, 105],
    [201, 202, 203, 204, 205],
    [301, 302, 303, 304, 305],
    [401, 402, 403, 404, 405],
    [501, 502, 503, 504, 505],
  ],
  profilePools: DEFAULT_PROFILE_POOLS,
  selectionWeights: {
    ownProfile: 8,
    ownNear: 3,
    neighborProfile: 2,
    neighborNear: 1,
  },
  parcelGenerationProfiles: Object.fromEntries(
    Object.entries(DEFAULT_BIOMES).map(([id, biome]) => [id, biome.ecologyProfileId]),
  ),
  biomes: DEFAULT_BIOMES,
  continuity: {
    minimumCompatiblePairs: 1,
    maximumBiomeRepresentationShare: 0.5,
    incompatiblePairs: [["mangrove", "haut_refuge"], ["littoral", "haut_refuge"], ["mangrove", "semi_desert"]],
  },
});

function stableSeed(value) {
  let hash = 17;
  for (const code of `${value}`) hash = (hash * 31 + code.charCodeAt(0)) & 0x7fffffff;
  return hash;
}

function coordinate(x, y) {
  return `${String.fromCharCode("A".charCodeAt(0) + x)}${y + 1}`;
}

function validMatrix(value) {
  return Array.isArray(value) && value.length === 5 && value.every((row) =>
    Array.isArray(row) && row.length === 5 && row.every((profile) => typeof profile === "string"));
}

function copyMatrix(matrix) {
  return matrix.map((row) => [...row]);
}

function mergeBiomeDefinitions(base, override) {
  if (!override || typeof override !== "object" || Array.isArray(override)) return base;
  return Object.fromEntries(Object.entries(base).map(([id, definition]) => [
    id,
    {...definition, ...(override[id] || {}), visualProfile: {...definition.visualProfile, ...(override[id]?.visualProfile || {})}},
  ]));
}

// The rich visual object is still convenient for Flutter.  Its stable ID,
// however, prevents future asset packs from having to infer identity from a
// ground-set string.  Neighbour compatibility is declarative data used by the
// non-blocking continuity audit, not a second terrain generator.
function enrichBiomeDefinitions(biomes) {
  return Object.fromEntries(Object.entries(biomes).map(([id, biome]) => [id, {
    ...biome,
    visualProfileId: biome.visualProfileId || `biome-visual-${id}-v1`,
    parcelGenerationProfileId: biome.parcelGenerationProfileId ||
      biome.parcelGenerationProfile || biome.ecologyProfileId || id,
    neighborCompatibility: Array.isArray(biome.neighborCompatibility)
      ? biome.neighborCompatibility : Object.keys(biomes),
  }]));
}

function boundedWeight(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.min(100, number)) : fallback;
}

function runtimeConfig(source) {
  const candidate = source && typeof source === "object" && !Array.isArray(source) ? source : {};
  const matrix = copyMatrix(validMatrix(candidate.regionProfileMatrix)
    ? candidate.regionProfileMatrix
    : DEFAULT_WORLDBUILDING_CONFIG.regionProfileMatrix);
  const offsets = copyMatrix(validMatrix(candidate.generationSeedOffsets)
    ? candidate.generationSeedOffsets
    : DEFAULT_WORLDBUILDING_CONFIG.generationSeedOffsets);
  const pools = {...DEFAULT_PROFILE_POOLS, ...(candidate.profilePools || {})};
  const parcelGenerationProfiles = {
    ...DEFAULT_WORLDBUILDING_CONFIG.parcelGenerationProfiles,
    ...(candidate.parcelGenerationProfiles || {}),
  };
  const baseBiomes = mergeBiomeDefinitions(DEFAULT_BIOMES, candidate.biomes);
  const biomes = enrichBiomeDefinitions(Object.fromEntries(Object.entries(baseBiomes).map(([id, biome]) => [
    id,
    {
      ...biome,
      parcelGenerationProfile: `${parcelGenerationProfiles[id] || biome.ecologyProfileId || id}`,
      parcelGenerationProfileId: `${parcelGenerationProfiles[id] || biome.ecologyProfileId || id}`,
    },
  ])));
  return {
    worldbuildingVersion: typeof candidate.worldbuildingVersion === "string" && candidate.worldbuildingVersion.length > 0
      ? candidate.worldbuildingVersion : DEFAULT_WORLDBUILDING_CONFIG.worldbuildingVersion,
    minimumDistinctBiomes: Math.max(1, Math.min(5, Math.floor(Number(candidate.minimumDistinctBiomes) || DEFAULT_WORLDBUILDING_CONFIG.minimumDistinctBiomes))),
    internalPositions: Array.isArray(candidate.internalPositions) && candidate.internalPositions.length === 5
      ? candidate.internalPositions.map(String) : INTERNAL_POSITIONS,
    regionProfileMatrix: matrix,
    generationSeedOffsets: offsets,
    profilePools: pools,
    selectionWeights: Object.fromEntries(Object.entries(
      DEFAULT_WORLDBUILDING_CONFIG.selectionWeights,
    ).map(([key, fallback]) => [key, boundedWeight(candidate.selectionWeights?.[key], fallback)])),
    parcelGenerationProfiles,
    biomes,
    continuity: {...DEFAULT_WORLDBUILDING_CONFIG.continuity, ...(candidate.continuity || {})},
  };
}

function neighborProfiles(config, x, y) {
  const result = [];
  for (const [nx, ny] of [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]) {
    if (nx >= 0 && nx < 5 && ny >= 0 && ny < 5) result.push(config.regionProfileMatrix[ny][nx]);
  }
  return result;
}

function rankedCandidates(config, profile, neighbors, mode, key) {
  const scores = new Map();
  const add = (values, weight) => (values || []).forEach((id) => {
    const definition = config.biomes[id];
    if (!definition || (Array.isArray(definition.compatibleRegionProfiles) &&
      !definition.compatibleRegionProfiles.includes(profile))) return;
    scores.set(id, (scores.get(id) || 0) + weight);
  });
  const main = config.profilePools[profile] || DEFAULT_PROFILE_POOLS.mixed;
  add(main[mode], config.selectionWeights.ownProfile);
  add(main.near, mode === "near" ? config.selectionWeights.ownNear : config.selectionWeights.neighborNear);
  for (const neighbor of neighbors) {
    const pool = config.profilePools[neighbor] || DEFAULT_PROFILE_POOLS.mixed;
    add(pool[mode], config.selectionWeights.neighborProfile);
    add(pool.near, config.selectionWeights.neighborNear);
  }
  return [...scores.keys()].sort((left, right) =>
    (scores.get(right) - scores.get(left)) ||
    (stableSeed(`${key}:${left}`) - stableSeed(`${key}:${right}`)) || left.localeCompare(right));
}

function selectCandidate(candidates, selected, key, allowDuplicate = false) {
  const eligible = candidates.filter((id) => allowDuplicate || !selected.includes(id));
  const pool = eligible.length > 0 ? eligible : candidates;
  if (pool.length === 0) throw new Error("Aucun Biome compatible n’est configuré.");
  const window = Math.min(4, pool.length);
  return pool[stableSeed(key) % window];
}

function composeRegion(config, {worldSeed, x, y}) {
  const profile = config.regionProfileMatrix[y][x];
  const neighbors = neighborProfiles(config, x, y);
  const offset = Number(config.generationSeedOffsets[y][x]) || 0;
  const key = `${worldSeed}:${config.worldbuildingVersion}:${coordinate(x, y)}:${offset}`;
  const near = rankedCandidates(config, profile, neighbors, "near", key);
  const far = rankedCandidates(config, profile, neighbors, "far", key);
  const required = (config.profilePools[profile]?.required || []).filter((id) => config.biomes[id]);
  const selected = [];
  const byPosition = {};
  for (const position of config.internalPositions) {
    const candidates = NEAR_POSITIONS.has(position) ? near : far;
    const forced = position === "a1" ? required[0] : null;
    const type = forced || selectCandidate(candidates, selected, `${key}:${position}`);
    selected.push(type);
    byPosition[position] = type;
  }
  // Retain a useful diversity baseline even if future Dashboard weights become
  // highly specialised. The replacement is deterministic and never rerolls.
  const distinct = new Set(selected);
  for (const candidate of [...near, ...far]) {
    if (distinct.size >= config.minimumDistinctBiomes) break;
    if (distinct.has(candidate)) continue;
    const replacePosition = config.internalPositions.find((position) =>
      position !== "a1" && byPosition[position] === selected[0]);
    if (!replacePosition) break;
    distinct.delete(byPosition[replacePosition]);
    byPosition[replacePosition] = candidate;
    distinct.add(candidate);
  }
  return {
    coordinate: coordinate(x, y),
    profile,
    primaryInfluence: profile,
    secondaryInfluences: [...new Set(neighbors)],
    generationSeedOffset: offset,
    biomeTypesByPosition: byPosition,
    visualTags: [...new Set(Object.values(byPosition).flatMap((type) => config.biomes[type].environmentalTags || []))],
  };
}

function isPairIncompatible(config, left, right) {
  return (config.continuity.incompatiblePairs || []).some((pair) =>
    Array.isArray(pair) && ((pair[0] === left && pair[1] === right) || (pair[0] === right && pair[1] === left)));
}

function compatibleCrossRegionPairs(config, left, right) {
  let count = 0;
  for (const first of Object.values(left.biomeTypesByPosition)) {
    for (const second of Object.values(right.biomeTypesByPosition)) {
      if (!isPairIncompatible(config, first, second)) count += 1;
    }
  }
  return count;
}

function buildWorldbuildingMap(configSource, worldSeed) {
  const config = runtimeConfig(configSource);
  const regions = [];
  for (let y = 0; y < 5; y += 1) {
    for (let x = 0; x < 5; x += 1) regions.push(composeRegion(config, {worldSeed, x, y}));
  }
  const byCoordinate = new Map(regions.map((region) => [region.coordinate, region]));
  const warnings = [];
  const representation = new Map();
  for (const region of regions) {
    const x = region.coordinate.charCodeAt(0) - "A".charCodeAt(0);
    const y = Number(region.coordinate.slice(1)) - 1;
    for (const [nx, ny] of [[x + 1, y], [x, y + 1]]) {
      if (nx > 4 || ny > 4) continue;
      const neighbor = byCoordinate.get(coordinate(nx, ny));
      if (compatibleCrossRegionPairs(config, region, neighbor) < config.continuity.minimumCompatiblePairs) {
        warnings.push({type: "continuity", region: region.coordinate, neighbor: neighbor.coordinate});
      }
    }
    const distinct = new Set(Object.values(region.biomeTypesByPosition)).size;
    if (distinct < config.minimumDistinctBiomes) warnings.push({type: "variety", region: region.coordinate, distinct});
    for (const biomeType of Object.values(region.biomeTypesByPosition)) {
      representation.set(biomeType, (representation.get(biomeType) || 0) + 1);
    }
  }
  const totalBiomes = regions.length * config.internalPositions.length;
  const maximumShare = Math.max(0, Math.min(1,
    Number(config.continuity.maximumBiomeRepresentationShare) || 0.5));
  for (const [biomeType, count] of representation) {
    if (count / totalBiomes > maximumShare) {
      warnings.push({type: "overrepresentation", biomeType, count, totalBiomes, maximumShare});
    }
  }
  return {config, regions, warnings};
}

module.exports = {
  DEFAULT_WORLDBUILDING_CONFIG,
  buildWorldbuildingMap,
  composeRegion,
  neighborProfiles,
  rankedCandidates,
  runtimeConfig,
  stableSeed,
};
