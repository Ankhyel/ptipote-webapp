enum PTibugSpecies { scarabe, hyme, arac }

enum PTibugTraitGrade { commun, rare, avance }

enum PTibugModuleType { ailes, pinces, reservoir, reflecteur, etancheite }

extension PTibugModuleTypeLabel on PTibugModuleType {
  String get displayName {
    switch (this) {
      case PTibugModuleType.ailes:
        return 'Ailes';
      case PTibugModuleType.pinces:
        return 'Pinces';
      case PTibugModuleType.reservoir:
        return 'Réservoir';
      case PTibugModuleType.reflecteur:
        return 'Réflecteur';
      case PTibugModuleType.etancheite:
        return 'Étanchéité';
    }
  }
}

/// Scientific data is owned by the Kernel, never by the material inventory.
enum PTibugDataFamily {
  organique,
  minerale,
  mycelienne,
  toxine,
  biomimetisme,
  energie,
  comportementInsectoide,
}

enum PTibugDataQuality { common, sought, rare }

enum PTibugPatternCategory {
  craft,
  building,
  species,
  trait,
  module,
  advancedTechnology,
}

enum PTibugPatternState {
  unknown,
  discovered,
  researching,
  ready,
  active,
  masteredCurrentLevel,
}

/// These IDs are deliberately independent from the historical Lisiere IDs.
/// The game state maps the four original biomes during save migration.
enum PTibugBiome {
  hautsRefuges,
  foretHumideRelictuelle,
  foretSecheTropicale,
  savaneTropicale,
  mangroves,
  maraisSales,
  semiDesertGarrigueTropicale,
  littoral,
}

class PTibugBiomeConfig {
  const PTibugBiomeConfig({
    required this.displayName,
    required this.risks,
    required this.dataWeights,
    required this.localProductionBonus,
    this.nurseryInsectBehaviourWeight = 0,
    this.aracProductionWeights = const <String, int>{},
    this.weatherTypes = const <String>[],
  });

  final String displayName;
  final List<String> risks;
  final Map<PTibugDataFamily, int> dataWeights;
  final Map<PTibugSpecies, Map<String, int>> localProductionBonus;
  final int nurseryInsectBehaviourWeight;

  /// Arac keeps its adaptive production, but each biome steers the outcome.
  /// Only material inventory resources are allowed in this table.
  final Map<String, int> aracProductionWeights;

  /// Weather identifiers accepted by this biome: toxicCloud, heatWave,
  /// heavyRain. The Tower remains the single source of the active alert.
  final List<String> weatherTypes;
}

/// A scientific Pattern is one persistent Kernel research project. It is not
/// an inventory object and its mastery can be increased over time.
class PTibugResearchPatternConfig {
  const PTibugResearchPatternConfig({
    required this.id,
    required this.displayName,
    required this.category,
    required this.description,
    required this.masteryCosts,
    this.linkedSpecies,
    this.linkedTraitId,
    this.linkedModuleType,
    this.requiredTrustLevel = 1,
    this.requiredBreederLevel = 0,
    this.requiredBuilderLevel = 0,
    this.requiredRestorerLevel = 0,
    this.origin = 'Kernel',
    this.biomesSuggested = const <PTibugBiome>[],
  });

  final String id;
  final String displayName;
  final PTibugPatternCategory category;
  final String description;
  final Map<int, Map<PTibugDataFamily, int>> masteryCosts;
  final PTibugSpecies? linkedSpecies;
  final String? linkedTraitId;
  final PTibugModuleType? linkedModuleType;
  final int requiredTrustLevel;
  final int requiredBreederLevel;
  final int requiredBuilderLevel;
  final int requiredRestorerLevel;
  final String origin;
  final List<PTibugBiome> biomesSuggested;
}

class PTibugSpeciesConfig {
  const PTibugSpeciesConfig({
    required this.displayName,
    required this.styles,
    required this.creationCost,
    required this.creationEnergyCost,
    this.creationBioBatteryCost = 0,
    this.futureMyceliumCost = 0,
    required this.creationMinutes,
  });

  final String displayName;
  final List<String> styles;
  final Map<String, int> creationCost;
  final int creationEnergyCost;
  final int creationBioBatteryCost;

  /// Reserved for future P'TIBUG recipes. It is editable remotely but is not
  /// consumed by the V1 creation flow yet.
  final int futureMyceliumCost;
  final int creationMinutes;
}

/// A Pattern is the Kernel knowledge required before the Nurserie can create
/// a species. The creation recipe itself stays on [PTibugSpeciesConfig].
class PTibugPatternConfig {
  const PTibugPatternConfig({
    required this.species,
    required this.kernelPlanId,
    required this.description,
  });

  final PTibugSpecies species;
  final String kernelPlanId;
  final String description;
}

class PTibugTraitDefinition {
  const PTibugTraitDefinition({
    required this.id,
    required this.displayName,
    required this.description,
    required this.effects,
    required this.gradeMultipliers,
    required this.colorHex,
    required this.isActive,
    this.dataCostByLevel = const <int, Map<PTibugDataFamily, int>>{},
    this.materialCostByLevel = const <int, Map<String, int>>{},
    this.energyCostByLevel = const <int, int>{},
    this.maxLevel = 3,
  });

  final String id;
  final String displayName;
  final String description;
  final Map<String, int> effects;
  final Map<PTibugTraitGrade, int> gradeMultipliers;
  final String colorHex;
  final bool isActive;
  final Map<int, Map<PTibugDataFamily, int>> dataCostByLevel;
  final Map<int, Map<String, int>> materialCostByLevel;
  final Map<int, int> energyCostByLevel;
  final int maxLevel;

  static const Set<String> _materialProductionEffects = <String>{
    'Organique',
    'Minéral',
    'Mycélium',
    'Déchets',
  };

  /// Only material effects belong in the passive production inventory. The
  /// other effect keys are consumed by their dedicated game systems.
  Map<String, int> productionFor(PTibugTraitGrade grade) => Map.fromEntries(
        effects.entries
            .where((entry) => _materialProductionEffects.contains(entry.key))
            .map(
              (entry) => MapEntry(
                entry.key,
                entry.value * (gradeMultipliers[grade] ?? 1),
              ),
            ),
      );

  Map<String, int> productionForLevel(int level) => Map.fromEntries(
        effects.entries
            .where((entry) => _materialProductionEffects.contains(entry.key))
            .map(
              (entry) => MapEntry(
                entry.key,
                entry.value * level.clamp(1, maxLevel),
              ),
            ),
      );

  int effectForGrade(String effect, PTibugTraitGrade grade) =>
      (effects[effect] ?? 0) * (gradeMultipliers[grade] ?? 1);

  int effectForLevel(String effect, int level) =>
      (effects[effect] ?? 0) * level.clamp(1, maxLevel);

  Map<PTibugDataFamily, int> dataCostForLevel(int level) =>
      dataCostByLevel[level.clamp(1, maxLevel)] ??
      const <PTibugDataFamily, int>{};

  Map<String, int> materialCostForLevel(int level) =>
      materialCostByLevel[level.clamp(1, maxLevel)] ?? const <String, int>{};

  int energyCostForLevel(int level) =>
      energyCostByLevel[level.clamp(1, maxLevel)] ?? 0;
}

class PTibugConfig {
  const PTibugConfig({
    required this.nurseryRequirements,
    required this.nurseryDurationMinutes,
    required this.slotsByLevel,
    required this.moduleSlotsByLevel,
    required this.productionCycleMinutes,
    required this.carryingCapacity,
    required this.storageMultiplier,
    required this.xpPerCycle,
    required this.wingsCycleReduction,
    required this.clawProductionBonus,
    required this.reservoirCapacityBonus,
    required this.species,
    required this.patterns,
    required this.sourcierPatternPrices,
    required this.traitDefinitions,
    required this.researchPatterns,
    required this.biomes,
    required this.dataQualityValues,
    required this.dataQualityWeights,
    required this.baseCellChancePercent,
    required this.cellChanceByOrdinal,
    required this.neutralCellChancePercent,
    required this.maxCellsByMission,
    required this.reservoirCapacityBonusByLevel,
    required this.wingsCycleReductionByLevel,
    required this.clawProductionBonusByLevel,
    required this.moduleFusionEnergyCost,
    required this.moduleMaxLevel,
    required this.capsuleEnergyCost,
    required this.moduleCraftCosts,
    required this.moduleCraftEnergyCosts,
    required this.moduleCraftMinutes,
    required this.nurseryReserveCapacity,
    required this.sourcierCellPricePerDataValue,
    required this.territory,
    required this.progression,
    required this.moduleCapacity,
    required this.weather,
  });

  final Map<String, int> nurseryRequirements;
  final int nurseryDurationMinutes;
  final Map<int, int> slotsByLevel;
  final Map<int, int> moduleSlotsByLevel;
  final int productionCycleMinutes;
  final int carryingCapacity;
  final int storageMultiplier;
  final int xpPerCycle;
  final double wingsCycleReduction;
  final int clawProductionBonus;
  final int reservoirCapacityBonus;
  final Map<PTibugSpecies, PTibugSpeciesConfig> species;
  final Map<PTibugSpecies, PTibugPatternConfig> patterns;
  final Map<PTibugSpecies, int> sourcierPatternPrices;
  final Map<String, PTibugTraitDefinition> traitDefinitions;
  final Map<String, PTibugResearchPatternConfig> researchPatterns;
  final Map<PTibugBiome, PTibugBiomeConfig> biomes;
  final Map<PTibugDataQuality, int> dataQualityValues;
  final Map<PTibugDataQuality, int> dataQualityWeights;
  final int baseCellChancePercent;
  final Map<int, int> cellChanceByOrdinal;
  final int neutralCellChancePercent;
  final Map<int, int> maxCellsByMission;
  final Map<int, int> reservoirCapacityBonusByLevel;
  final Map<int, double> wingsCycleReductionByLevel;
  final Map<int, int> clawProductionBonusByLevel;
  final int moduleFusionEnergyCost;
  final int moduleMaxLevel;
  final int capsuleEnergyCost;
  final Map<PTibugModuleType, Map<String, int>> moduleCraftCosts;
  final Map<PTibugModuleType, int> moduleCraftEnergyCosts;
  final Map<PTibugModuleType, int> moduleCraftMinutes;
  final int nurseryReserveCapacity;
  final int sourcierCellPricePerDataValue;
  final PTibugTerritoryConfig territory;
  final PTibugProgressionConfig progression;
  final PTibugModuleCapacityConfig moduleCapacity;
  final PTibugWeatherConfig weather;

  int slotsForLevel(int level) => territory.nurseryCapacityForLevel(level);
  int moduleSlotsForLevel(int level) =>
      moduleSlotsByLevel[level.clamp(1, 3)] ?? 1;

  int traitMultiplier(PTibugTraitGrade grade) => grade.index + 1;

  PTibugTraitDefinition? traitDefinitionFor(String id) => traitDefinitions[id];

  List<PTibugTraitDefinition> get activeTraitDefinitions =>
      traitDefinitions.values
          .where((definition) => definition.isActive)
          .toList();

  PTibugPatternConfig? patternForKernelPlanId(String planId) {
    for (final pattern in patterns.values) {
      if (pattern.kernelPlanId == planId) return pattern;
    }
    return null;
  }

  int dataValue(PTibugDataQuality quality) => dataQualityValues[quality] ?? 1;

  int maxCellsForMissionHours(int hours) {
    if (hours >= 6) return maxCellsByMission[3] ?? 3;
    if (hours >= 2) return maxCellsByMission[2] ?? 2;
    return maxCellsByMission[1] ?? 1;
  }

  int cellChanceForOrdinal(int ordinal) {
    return (cellChanceByOrdinal[ordinal] ?? 0).clamp(0, 100).toInt();
  }

  int reservoirCapacityForLevel(int level) =>
      reservoirCapacityBonusByLevel[level.clamp(1, moduleMaxLevel)] ?? 0;

  double wingsReductionForLevel(int level) =>
      wingsCycleReductionByLevel[level.clamp(1, moduleMaxLevel)] ?? 0;

  int clawBonusForLevel(int level) =>
      clawProductionBonusByLevel[level.clamp(1, moduleMaxLevel)] ?? 0;

  Map<String, int> moduleCraftCostFor(PTibugModuleType type) =>
      moduleCraftCosts[type] ?? const <String, int>{};

  int moduleCraftEnergyFor(PTibugModuleType type) =>
      moduleCraftEnergyCosts[type] ?? 0;

  int moduleCraftMinutesFor(PTibugModuleType type) =>
      moduleCraftMinutes[type] ?? 1;
}

class PTibugProgressionConfig {
  const PTibugProgressionConfig(
      {required this.maximumLevel,
      required this.xpRequiredByLevel,
      required this.yieldBonusPerLevel,
      required this.baseEnergyPerDay,
      required this.energyReductionPerLevel,
      required this.minimumEnergyPerDay,
      required this.renewalLevel,
      required this.renewalMaterialCost,
      required this.renewalEnergyCost,
      required this.renewalBioBatteryCost,
      required this.renewalDurationMinutes,
      required this.maximumRenewals});
  final int maximumLevel;
  final Map<int, int> xpRequiredByLevel;
  final double yieldBonusPerLevel;
  final int baseEnergyPerDay;
  final int energyReductionPerLevel;
  final int minimumEnergyPerDay;
  final int renewalLevel;
  final Map<String, int> renewalMaterialCost;
  final int renewalEnergyCost;
  final int renewalBioBatteryCost;
  final int renewalDurationMinutes;
  final int maximumRenewals;
  int xpForNextLevel(int level) =>
      xpRequiredByLevel[level.clamp(1, maximumLevel).toInt()] ?? 0;
  double yieldMultiplierForLevel(int level) =>
      1 + (level.clamp(1, maximumLevel).toInt() - 1) * yieldBonusPerLevel;
  int baseEnergyPerDayForLevel(int level) {
    final reduced = baseEnergyPerDay -
        (level.clamp(1, maximumLevel).toInt() - 1) * energyReductionPerLevel;
    return reduced < minimumEnergyPerDay ? minimumEnergyPerDay : reduced;
  }
}

class PTibugModuleCapacityConfig {
  const PTibugModuleCapacityConfig(
      {required this.initialCapacity,
      required this.maximumUpgrades,
      required this.capacityPerUpgrade,
      required this.materialCostsByLevel,
      required this.bioBatteryCostsByLevel,
      required this.dataCostsByLevel});
  final int initialCapacity;
  final int maximumUpgrades;
  final int capacityPerUpgrade;
  final Map<int, Map<String, int>> materialCostsByLevel;
  final Map<int, int> bioBatteryCostsByLevel;
  final Map<int, Map<PTibugDataFamily, int>> dataCostsByLevel;
  int capacityForLevel(int level) =>
      initialCapacity +
      level.clamp(0, maximumUpgrades).toInt() * capacityPerUpgrade;
}

class PTibugWeatherConfig {
  const PTibugWeatherConfig({
    required this.productionMalusPercent,
    required this.sensorMaterialPenaltyPercent,
    required this.sensorChanceByLevel,
    required this.sensorPityEnabled,
    required this.sensorPityCycleThreshold,
    required this.stabilizerRegenerationPercentByLevel,
    required this.stabilizerMaximumPercent,
    required this.economyOrganicReductionPercentByLevel,
    required this.economyEnergyReductionPercentByLevel,
  });

  final int productionMalusPercent;
  final int sensorMaterialPenaltyPercent;
  final Map<int, int> sensorChanceByLevel;
  final bool sensorPityEnabled;
  final int sensorPityCycleThreshold;
  final Map<int, int> stabilizerRegenerationPercentByLevel;
  final int stabilizerMaximumPercent;
  final Map<int, int> economyOrganicReductionPercentByLevel;
  final Map<int, int> economyEnergyReductionPercentByLevel;

  double multiplierForPenalty(int percent) =>
      (100 - percent.clamp(0, 100)) / 100;
}

/// Territorial rules are intentionally separate from species and Traits: they
/// describe the building that hosts a P'TIBUG, not the P'TIBUG itself.
class PTibugTerritoryConfig {
  const PTibugTerritoryConfig({
    required this.nurseryMaximumLevel,
    required this.refugeMaximumLevel,
    required this.capacityPerLevel,
    required this.organicAmount,
    required this.organicEveryHours,
    required this.mineralAmount,
    required this.mineralEveryHours,
    required this.energyAmount,
    required this.energyEveryHours,
    required this.moduleEnergyAmount,
    required this.moduleEnergyEveryHours,
    required this.nurseryEnergyAmount,
    required this.nurseryEnergyEveryHours,
    required this.refugeEnergyAmount,
    required this.refugeEnergyEveryHours,
    required this.dataCellStorageCapacity,
    required this.refugeConstructionOrganic,
    required this.refugeConstructionMineral,
    required this.refugeConstructionBioBatteries,
    required this.refugeConstructionMinutes,
    required this.refugeUpgradeOrganicByLevel,
    required this.refugeUpgradeMineralByLevel,
    required this.refugeUpgradeBioBatteriesByLevel,
    required this.refugeUpgradeMinutes,
  });

  final int nurseryMaximumLevel;
  final int refugeMaximumLevel;
  final int capacityPerLevel;
  final int organicAmount;
  final int organicEveryHours;
  final int mineralAmount;
  final int mineralEveryHours;
  final int energyAmount;
  final int energyEveryHours;
  final int moduleEnergyAmount;
  final int moduleEnergyEveryHours;
  final int nurseryEnergyAmount;
  final int nurseryEnergyEveryHours;
  final int refugeEnergyAmount;
  final int refugeEnergyEveryHours;
  final int dataCellStorageCapacity;
  final int refugeConstructionOrganic;
  final int refugeConstructionMineral;
  final int refugeConstructionBioBatteries;
  final int refugeConstructionMinutes;
  final Map<int, int> refugeUpgradeOrganicByLevel;
  final Map<int, int> refugeUpgradeMineralByLevel;
  final Map<int, int> refugeUpgradeBioBatteriesByLevel;
  final int refugeUpgradeMinutes;

  int nurseryCapacityForLevel(int level) =>
      level.clamp(0, nurseryMaximumLevel).toInt() * capacityPerLevel;
  int refugeCapacityForLevel(int level) =>
      level.clamp(0, refugeMaximumLevel).toInt() * capacityPerLevel;

  Map<String, int> refugeRequirementsForLevel(int level) => <String, int>{
        'Organique': level <= 1
            ? refugeConstructionOrganic
            : refugeUpgradeOrganicByLevel[level] ?? 0,
        'Minéral': level <= 1
            ? refugeConstructionMineral
            : refugeUpgradeMineralByLevel[level] ?? 0,
      }..removeWhere((_, amount) => amount <= 0);

  int refugeBioBatteriesForLevel(int level) => level <= 1
      ? refugeConstructionBioBatteries
      : refugeUpgradeBioBatteriesByLevel[level] ?? 0;

  int refugeMinutesForLevel(int level) =>
      level <= 1 ? refugeConstructionMinutes : refugeUpgradeMinutes;
}

/// Runtime final because this catalog uses collection-for entries to keep the
/// Trait and Module Pattern lists aligned with their enums.
final PTibugConfig defaultPTibugConfig = PTibugConfig(
  nurseryRequirements: <String, int>{'Organique': 20, 'Minéral': 35},
  nurseryDurationMinutes: 1,
  slotsByLevel: <int, int>{1: 1, 2: 2, 3: 3},
  moduleSlotsByLevel: <int, int>{1: 1, 2: 2, 3: 3},
  productionCycleMinutes: 60,
  carryingCapacity: 10,
  storageMultiplier: 5,
  xpPerCycle: 1,
  wingsCycleReduction: 0.15,
  clawProductionBonus: 1,
  reservoirCapacityBonus: 4,
  species: <PTibugSpecies, PTibugSpeciesConfig>{
    PTibugSpecies.scarabe: PTibugSpeciesConfig(
      displayName: 'Scarabé',
      styles: <String>['compact', 'cornu', 'cuirassé'],
      creationCost: <String, int>{'Organique': 30, 'Minéral': 15},
      creationEnergyCost: 0,
      creationBioBatteryCost: 10,
      futureMyceliumCost: 0,
      creationMinutes: 20,
    ),
    PTibugSpecies.hyme: PTibugSpeciesConfig(
      displayName: 'Hyme',
      styles: <String>['fourmi', 'abeille', 'guêpe'],
      creationCost: <String, int>{'Organique': 30, 'Minéral': 15},
      creationEnergyCost: 0,
      creationBioBatteryCost: 10,
      futureMyceliumCost: 0,
      creationMinutes: 20,
    ),
    PTibugSpecies.arac: PTibugSpeciesConfig(
      displayName: 'Arac',
      styles: <String>['toile', 'chasseuse', 'sauteuse'],
      creationCost: <String, int>{'Organique': 30, 'Minéral': 15},
      creationEnergyCost: 0,
      creationBioBatteryCost: 10,
      futureMyceliumCost: 0,
      creationMinutes: 25,
    ),
  },
  patterns: <PTibugSpecies, PTibugPatternConfig>{
    PTibugSpecies.scarabe: PTibugPatternConfig(
      species: PTibugSpecies.scarabe,
      kernelPlanId: 'ptibug-pattern-scarabe',
      description: 'Un premier collecteur robuste pour les sols du refuge.',
    ),
    PTibugSpecies.hyme: PTibugPatternConfig(
      species: PTibugSpecies.hyme,
      kernelPlanId: 'ptibug-pattern-hyme',
      description: 'Un P’TIBUG rapide, adapté aux ressources organiques.',
    ),
    PTibugSpecies.arac: PTibugPatternConfig(
      species: PTibugSpecies.arac,
      kernelPlanId: 'ptibug-pattern-arac',
      description: 'Un collecteur agile capable de s’adapter à sa collecte.',
    ),
  },
  sourcierPatternPrices: <PTibugSpecies, int>{
    PTibugSpecies.hyme: 6,
    PTibugSpecies.arac: 8,
  },
  traitDefinitions: <String, PTibugTraitDefinition>{
    'pollinisateur': PTibugTraitDefinition(
      id: 'pollinisateur',
      displayName: 'Pollinisateur',
      description: '+1 / +2 / +3 Organique par cycle aux niveaux I / II / III.',
      effects: <String, int>{'Organique': 1},
      gradeMultipliers: <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3
      },
      colorHex: '#5D8D71',
      isActive: true,
      dataCostByLevel: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.comportementInsectoide: 3,
          PTibugDataFamily.organique: 2,
        },
        2: <PTibugDataFamily, int>{
          PTibugDataFamily.comportementInsectoide: 6,
          PTibugDataFamily.organique: 4,
          PTibugDataFamily.biomimetisme: 2,
        },
        3: <PTibugDataFamily, int>{
          PTibugDataFamily.comportementInsectoide: 10,
          PTibugDataFamily.organique: 7,
          PTibugDataFamily.biomimetisme: 4,
        },
      },
      materialCostByLevel: <int, Map<String, int>>{
        1: <String, int>{'Organique': 4, 'Minéral': 2},
        2: <String, int>{'Organique': 7, 'Minéral': 4},
        3: <String, int>{'Organique': 10, 'Minéral': 7},
      },
      energyCostByLevel: <int, int>{1: 2, 2: 4, 3: 6},
    ),
    'mineur': PTibugTraitDefinition(
      id: 'mineur',
      displayName: 'Mineur',
      description: '+1 / +2 / +3 Minéral par cycle aux niveaux I / II / III.',
      effects: <String, int>{'Minéral': 1},
      gradeMultipliers: <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3
      },
      colorHex: '#4977A6',
      isActive: true,
      dataCostByLevel: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 3,
          PTibugDataFamily.comportementInsectoide: 2,
        },
        2: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 6,
          PTibugDataFamily.biomimetisme: 3,
        },
        3: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 10,
          PTibugDataFamily.biomimetisme: 6,
        },
      },
      materialCostByLevel: <int, Map<String, int>>{
        1: <String, int>{'Organique': 2, 'Minéral': 4},
        2: <String, int>{'Organique': 4, 'Minéral': 7},
        3: <String, int>{'Organique': 7, 'Minéral': 10},
      },
      energyCostByLevel: <int, int>{1: 2, 2: 4, 3: 6},
    ),
    'decomposeur': PTibugTraitDefinition(
      id: 'decomposeur',
      displayName: 'Décomposeur',
      description: '+1 / +2 / +3 Organique par cycle ; chance croissante de Mycélium.',
      effects: <String, int>{'Organique': 1, 'Mycélium': 1},
      gradeMultipliers: <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3
      },
      colorHex: '#8C5AA2',
      isActive: true,
      dataCostByLevel: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.mycelienne: 3,
          PTibugDataFamily.organique: 2,
        },
        2: <PTibugDataFamily, int>{
          PTibugDataFamily.mycelienne: 6,
          PTibugDataFamily.toxine: 3,
        },
        3: <PTibugDataFamily, int>{
          PTibugDataFamily.mycelienne: 10,
          PTibugDataFamily.toxine: 6,
        },
      },
      materialCostByLevel: <int, Map<String, int>>{
        1: <String, int>{'Organique': 4, 'Minéral': 2},
        2: <String, int>{'Organique': 7, 'Minéral': 4},
        3: <String, int>{'Organique': 10, 'Minéral': 7},
      },
      energyCostByLevel: <int, int>{1: 2, 2: 4, 3: 6},
    ),
    'recuperateur': PTibugTraitDefinition(
      id: 'recuperateur',
      displayName: 'Récupérateur',
      description: '+1 / +2 / +3 Déchets exploitables par cycle.',
      effects: <String, int>{'Déchets': 1},
      gradeMultipliers: <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3,
      },
      colorHex: '#8A7654',
      isActive: true,
      dataCostByLevel: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 2,
          PTibugDataFamily.biomimetisme: 3,
        },
        2: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 5,
          PTibugDataFamily.biomimetisme: 6,
        },
        3: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 9,
          PTibugDataFamily.biomimetisme: 10,
        },
      },
      materialCostByLevel: <int, Map<String, int>>{
        1: <String, int>{'Organique': 3, 'Minéral': 4},
        2: <String, int>{'Organique': 5, 'Minéral': 7},
        3: <String, int>{'Organique': 8, 'Minéral': 10},
      },
      energyCostByLevel: <int, int>{1: 2, 2: 4, 3: 6},
    ),
    'capteurIntelligent': PTibugTraitDefinition(
      id: 'capteurIntelligent',
      displayName: 'Capteur intelligent',
      description:
          'Production matérielle -50 % ; 5 % / 10 % / 15 % de chance de Cellule par cycle.',
      effects: const <String, int>{'Chance Cellule': 5, 'Malus matériel %': 50},
      gradeMultipliers: const <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3,
      },
      colorHex: '#C17E42',
      isActive: true,
      dataCostByLevel: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.comportementInsectoide: 3,
          PTibugDataFamily.biomimetisme: 2,
        },
        2: <PTibugDataFamily, int>{
          PTibugDataFamily.comportementInsectoide: 6,
          PTibugDataFamily.biomimetisme: 5,
        },
        3: <PTibugDataFamily, int>{
          PTibugDataFamily.comportementInsectoide: 10,
          PTibugDataFamily.biomimetisme: 9,
        },
      },
      materialCostByLevel: <int, Map<String, int>>{
        1: <String, int>{'Organique': 4, 'Minéral': 2},
        2: <String, int>{'Organique': 7, 'Minéral': 4},
        3: <String, int>{'Organique': 10, 'Minéral': 7},
      },
      energyCostByLevel: <int, int>{1: 2, 2: 4, 3: 6},
    ),
    'filtreur': PTibugTraitDefinition(
      id: 'filtreur',
      displayName: 'Filtreur',
      description: 'Annule 100 % du malus de production du Nuage toxique.',
      effects: const <String, int>{'Protection Nuage toxique': 1},
      gradeMultipliers: const <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3,
      },
      colorHex: '#617E85',
      isActive: true,
      dataCostByLevel: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.toxine: 3,
          PTibugDataFamily.mycelienne: 2,
        },
        2: <PTibugDataFamily, int>{
          PTibugDataFamily.toxine: 6,
          PTibugDataFamily.mycelienne: 5,
        },
        3: <PTibugDataFamily, int>{
          PTibugDataFamily.toxine: 10,
          PTibugDataFamily.mycelienne: 9,
        },
      },
      materialCostByLevel: <int, Map<String, int>>{
        1: <String, int>{'Organique': 3, 'Minéral': 3},
        2: <String, int>{'Organique': 5, 'Minéral': 6},
        3: <String, int>{'Organique': 8, 'Minéral': 9},
      },
      energyCostByLevel: <int, int>{1: 2, 2: 4, 3: 6},
    ),
    'econome': PTibugTraitDefinition(
      id: 'econome',
      displayName: 'Économe',
      description:
          '-20 % Organique et -10 % Énergie par niveau, jusqu’à -60 % / -30 %.',
      effects: const <String, int>{
        'Réduction Organique %': 20,
        'Réduction énergie %': 10
      },
      gradeMultipliers: const <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3,
      },
      colorHex: '#D0A943',
      isActive: true,
      dataCostByLevel: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.energie: 3,
          PTibugDataFamily.biomimetisme: 2,
        },
        2: <PTibugDataFamily, int>{
          PTibugDataFamily.energie: 6,
          PTibugDataFamily.biomimetisme: 5,
        },
        3: <PTibugDataFamily, int>{
          PTibugDataFamily.energie: 10,
          PTibugDataFamily.biomimetisme: 9,
        },
      },
      materialCostByLevel: <int, Map<String, int>>{
        1: <String, int>{'Organique': 2, 'Minéral': 3},
        2: <String, int>{'Organique': 4, 'Minéral': 6},
        3: <String, int>{'Organique': 6, 'Minéral': 9},
      },
      energyCostByLevel: <int, int>{1: 2, 2: 4, 3: 6},
    ),
    'stabilisateur': PTibugTraitDefinition(
      id: 'stabilisateur',
      displayName: 'Stabilisateur',
      description: '+5 % / +10 % / +15 % de régénération de Vigueur du biome local.',
      effects: const <String, int>{'Régénération Vigueur %': 5},
      gradeMultipliers: const <PTibugTraitGrade, int>{
        PTibugTraitGrade.commun: 1,
        PTibugTraitGrade.rare: 2,
        PTibugTraitGrade.avance: 3,
      },
      colorHex: '#5B8D8C',
      isActive: true,
      dataCostByLevel: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 3,
          PTibugDataFamily.energie: 2,
        },
        2: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 6,
          PTibugDataFamily.energie: 5,
        },
        3: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 10,
          PTibugDataFamily.energie: 9,
        },
      },
      materialCostByLevel: <int, Map<String, int>>{
        1: <String, int>{'Organique': 3, 'Minéral': 4},
        2: <String, int>{'Organique': 5, 'Minéral': 7},
        3: <String, int>{'Organique': 8, 'Minéral': 10},
      },
      energyCostByLevel: <int, int>{1: 2, 2: 4, 3: 6},
    ),
  },
  researchPatterns: <String, PTibugResearchPatternConfig>{
    'ptibug-species-scarabe': PTibugResearchPatternConfig(
      id: 'ptibug-species-scarabe',
      displayName: 'Pattern Scarabé',
      category: PTibugPatternCategory.species,
      description: 'Le premier collecteur robuste du refuge.',
      linkedSpecies: PTibugSpecies.scarabe,
      masteryCosts: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.minerale: 4,
          PTibugDataFamily.comportementInsectoide: 3,
        },
      },
    ),
    'ptibug-species-hyme': PTibugResearchPatternConfig(
      id: 'ptibug-species-hyme',
      displayName: 'Pattern Hyme',
      category: PTibugPatternCategory.species,
      description: 'Un collecteur organique rapide.',
      linkedSpecies: PTibugSpecies.hyme,
      masteryCosts: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.organique: 5,
          PTibugDataFamily.comportementInsectoide: 4,
        },
      },
      biomesSuggested: <PTibugBiome>[PTibugBiome.foretHumideRelictuelle],
    ),
    'ptibug-species-arac': PTibugResearchPatternConfig(
      id: 'ptibug-species-arac',
      displayName: 'Pattern Arac',
      category: PTibugPatternCategory.species,
      description: 'Un collecteur agile aux tables de production variables.',
      linkedSpecies: PTibugSpecies.arac,
      masteryCosts: <int, Map<PTibugDataFamily, int>>{
        1: <PTibugDataFamily, int>{
          PTibugDataFamily.biomimetisme: 5,
          PTibugDataFamily.comportementInsectoide: 4,
        },
      },
      biomesSuggested: <PTibugBiome>[PTibugBiome.littoral],
    ),
    for (final trait in <String>[
      'pollinisateur',
      'mineur',
      'decomposeur',
      'recuperateur',
      'capteurIntelligent',
      'filtreur',
      'econome',
      'stabilisateur',
    ])
      'ptibug-trait-$trait': PTibugResearchPatternConfig(
        id: 'ptibug-trait-$trait',
        displayName: 'Pattern ${trait[0].toUpperCase()}${trait.substring(1)}',
        category: PTibugPatternCategory.trait,
        description:
            'Connaissance biologique nécessaire avant la transformation.',
        linkedTraitId: trait,
        requiredTrustLevel: 2,
        requiredBreederLevel: 2,
        masteryCosts: <int, Map<PTibugDataFamily, int>>{
          1: <PTibugDataFamily, int>{
            PTibugDataFamily.comportementInsectoide: 4,
            PTibugDataFamily.biomimetisme: 2,
          },
          2: <PTibugDataFamily, int>{
            PTibugDataFamily.comportementInsectoide: 8,
            PTibugDataFamily.biomimetisme: 5,
          },
          3: <PTibugDataFamily, int>{
            PTibugDataFamily.comportementInsectoide: 14,
            PTibugDataFamily.biomimetisme: 9,
          },
        },
        origin: 'Sourcier du savoir',
      ),
    for (final module in PTibugModuleType.values)
      'ptibug-module-${module.name}': PTibugResearchPatternConfig(
        id: 'ptibug-module-${module.name}',
        displayName: 'Pattern Module ${module.name}',
        category: PTibugPatternCategory.module,
        description: 'Plan d’Atelier pour un module P’TIBUG.',
        linkedModuleType: module,
        requiredTrustLevel: 2,
        requiredBuilderLevel: 1,
        masteryCosts: <int, Map<PTibugDataFamily, int>>{
          1: <PTibugDataFamily, int>{
            PTibugDataFamily.biomimetisme: 4,
            PTibugDataFamily.minerale: 3,
          },
        },
        origin: 'Sourcier du savoir',
      ),
  },
  biomes: <PTibugBiome, PTibugBiomeConfig>{
    PTibugBiome.hautsRefuges: PTibugBiomeConfig(
      displayName: 'Hauts-Refuges',
      risks: <String>['Glissements', 'Vents', 'Anciennes structures'],
      weatherTypes: <String>['heavyRain'],
      dataWeights: <PTibugDataFamily, int>{
        PTibugDataFamily.minerale: 45,
        PTibugDataFamily.biomimetisme: 30,
        PTibugDataFamily.energie: 25,
      },
      localProductionBonus: <PTibugSpecies, Map<String, int>>{
        PTibugSpecies.scarabe: <String, int>{'Minéral': 1},
      },
      nurseryInsectBehaviourWeight: 10,
      aracProductionWeights: <String, int>{
        'Minéral': 60,
        'Organique': 20,
        'Déchets': 20,
      },
    ),
    PTibugBiome.foretHumideRelictuelle: PTibugBiomeConfig(
      displayName: 'Forêt humide relictuelle',
      risks: <String>[
        'Humidité',
        'Spores',
        'Faible visibilité',
        'Toxines biologiques'
      ],
      weatherTypes: <String>['heavyRain', 'toxicCloud'],
      dataWeights: <PTibugDataFamily, int>{
        PTibugDataFamily.organique: 40,
        PTibugDataFamily.mycelienne: 35,
        PTibugDataFamily.biomimetisme: 25,
      },
      localProductionBonus: <PTibugSpecies, Map<String, int>>{
        PTibugSpecies.hyme: <String, int>{'Organique': 1},
      },
      nurseryInsectBehaviourWeight: 10,
      aracProductionWeights: <String, int>{
        'Organique': 60,
        'Déchets': 25,
        'Minéral': 15,
      },
    ),
    PTibugBiome.foretSecheTropicale: PTibugBiomeConfig(
      displayName: 'Forêt sèche tropicale',
      risks: <String>['Chaleur', 'Sécheresse', 'Incendies locaux'],
      weatherTypes: <String>['heatWave'],
      dataWeights: <PTibugDataFamily, int>{
        PTibugDataFamily.organique: 40,
        PTibugDataFamily.energie: 30,
        PTibugDataFamily.biomimetisme: 30,
      },
      localProductionBonus: <PTibugSpecies, Map<String, int>>{
        PTibugSpecies.hyme: <String, int>{'Organique': 1},
      },
      aracProductionWeights: <String, int>{
        'Organique': 50,
        'Minéral': 30,
        'Déchets': 20,
      },
    ),
    PTibugBiome.savaneTropicale: PTibugBiomeConfig(
      displayName: 'Savane tropicale',
      risks: <String>[
        'Exposition',
        'Chaleur',
        'Déchets anciens',
        'Petits organismes'
      ],
      weatherTypes: <String>['heatWave', 'heavyRain'],
      dataWeights: <PTibugDataFamily, int>{
        PTibugDataFamily.organique: 35,
        PTibugDataFamily.biomimetisme: 30,
        PTibugDataFamily.comportementInsectoide: 35,
      },
      localProductionBonus: <PTibugSpecies, Map<String, int>>{
        PTibugSpecies.hyme: <String, int>{'Organique': 1},
      },
      nurseryInsectBehaviourWeight: 15,
      aracProductionWeights: <String, int>{
        'Organique': 45,
        'Minéral': 25,
        'Déchets': 30,
      },
    ),
    PTibugBiome.mangroves: PTibugBiomeConfig(
      displayName: 'Mangroves',
      risks: <String>[
        'Sols instables',
        'Eau stagnante',
        'Biofilms',
        'Salinité'
      ],
      weatherTypes: <String>['heavyRain', 'toxicCloud'],
      dataWeights: <PTibugDataFamily, int>{
        PTibugDataFamily.mycelienne: 40,
        PTibugDataFamily.toxine: 35,
        PTibugDataFamily.organique: 25,
      },
      localProductionBonus: <PTibugSpecies, Map<String, int>>{
        PTibugSpecies.hyme: <String, int>{'Organique': 1},
      },
      nurseryInsectBehaviourWeight: 15,
      aracProductionWeights: <String, int>{
        'Organique': 45,
        'Déchets': 45,
        'Minéral': 10,
      },
    ),
    PTibugBiome.maraisSales: PTibugBiomeConfig(
      displayName: 'Marais salés',
      risks: <String>['Corrosion', 'Toxines', 'Sol fragile', 'Forte salinité'],
      weatherTypes: <String>['toxicCloud', 'heavyRain'],
      dataWeights: <PTibugDataFamily, int>{
        PTibugDataFamily.toxine: 40,
        PTibugDataFamily.minerale: 30,
        PTibugDataFamily.energie: 30,
      },
      localProductionBonus: <PTibugSpecies, Map<String, int>>{
        PTibugSpecies.scarabe: <String, int>{'Minéral': 1},
      },
      nurseryInsectBehaviourWeight: 10,
      aracProductionWeights: <String, int>{
        'Minéral': 40,
        'Déchets': 45,
        'Organique': 15,
      },
    ),
    PTibugBiome.semiDesertGarrigueTropicale: PTibugBiomeConfig(
      displayName: 'Semi-désert / Garrigue tropicale',
      risks: <String>['Chaleur', 'Poussières', 'Vent', 'Manque d’ombre'],
      weatherTypes: <String>['heatWave'],
      dataWeights: <PTibugDataFamily, int>{
        PTibugDataFamily.minerale: 40,
        PTibugDataFamily.energie: 35,
        PTibugDataFamily.biomimetisme: 25,
      },
      localProductionBonus: <PTibugSpecies, Map<String, int>>{
        PTibugSpecies.scarabe: <String, int>{'Minéral': 1},
      },
      aracProductionWeights: <String, int>{
        'Minéral': 55,
        'Déchets': 30,
        'Organique': 15,
      },
    ),
    PTibugBiome.littoral: PTibugBiomeConfig(
      displayName: 'Littoral',
      risks: <String>['Corrosion', 'Embruns', 'Vents', 'Ruissellement'],
      weatherTypes: <String>['heavyRain'],
      dataWeights: <PTibugDataFamily, int>{
        PTibugDataFamily.energie: 40,
        PTibugDataFamily.toxine: 30,
        PTibugDataFamily.minerale: 30,
      },
      localProductionBonus: const <PTibugSpecies, Map<String, int>>{},
      nurseryInsectBehaviourWeight: 10,
      aracProductionWeights: <String, int>{
        'Minéral': 40,
        'Déchets': 45,
        'Organique': 15,
      },
    ),
  },
  dataQualityValues: <PTibugDataQuality, int>{
    PTibugDataQuality.common: 1,
    PTibugDataQuality.sought: 2,
    PTibugDataQuality.rare: 4,
  },
  dataQualityWeights: <PTibugDataQuality, int>{
    PTibugDataQuality.common: 70,
    PTibugDataQuality.sought: 25,
    PTibugDataQuality.rare: 5,
  },
  baseCellChancePercent: 20,
  cellChanceByOrdinal: <int, int>{1: 100, 2: 50, 3: 20},
  neutralCellChancePercent: 0,
  maxCellsByMission: <int, int>{1: 1, 2: 2, 3: 3},
  reservoirCapacityBonusByLevel: <int, int>{1: 15, 2: 18, 3: 20},
  wingsCycleReductionByLevel: <int, double>{1: .10, 2: .15, 3: .20},
  clawProductionBonusByLevel: <int, int>{1: 1, 2: 2, 3: 3},
  moduleFusionEnergyCost: 1,
  moduleMaxLevel: 3,
  capsuleEnergyCost: 1,
  moduleCraftCosts: <PTibugModuleType, Map<String, int>>{
    PTibugModuleType.ailes: <String, int>{'Organique': 6, 'Minéral': 4},
    PTibugModuleType.pinces: <String, int>{'Organique': 4, 'Minéral': 6},
    PTibugModuleType.reservoir: <String, int>{'Organique': 8, 'Minéral': 8},
    PTibugModuleType.reflecteur: <String, int>{'Organique': 10, 'Minéral': 6},
    PTibugModuleType.etancheite: <String, int>{'Organique': 8, 'Minéral': 10},
  },
  moduleCraftEnergyCosts: <PTibugModuleType, int>{
    PTibugModuleType.ailes: 1,
    PTibugModuleType.pinces: 1,
    PTibugModuleType.reservoir: 2,
    PTibugModuleType.reflecteur: 2,
    PTibugModuleType.etancheite: 2,
  },
  moduleCraftMinutes: <PTibugModuleType, int>{
    PTibugModuleType.ailes: 8,
    PTibugModuleType.pinces: 8,
    PTibugModuleType.reservoir: 10,
    PTibugModuleType.reflecteur: 10,
    PTibugModuleType.etancheite: 10,
  },
  nurseryReserveCapacity: 12,
  sourcierCellPricePerDataValue: 3,
  territory: const PTibugTerritoryConfig(
    nurseryMaximumLevel: 6,
    refugeMaximumLevel: 4,
    capacityPerLevel: 1,
    organicAmount: 1,
    organicEveryHours: 4,
    mineralAmount: 1,
    mineralEveryHours: 24,
    energyAmount: 1,
    energyEveryHours: 8,
    moduleEnergyAmount: 1,
    moduleEnergyEveryHours: 8,
    nurseryEnergyAmount: 1,
    nurseryEnergyEveryHours: 4,
    refugeEnergyAmount: 1,
    refugeEnergyEveryHours: 8,
    dataCellStorageCapacity: 3,
    refugeConstructionOrganic: 20,
    refugeConstructionMineral: 10,
    refugeConstructionBioBatteries: 1,
    refugeConstructionMinutes: 1,
    refugeUpgradeOrganicByLevel: <int, int>{2: 30, 3: 60, 4: 120},
    refugeUpgradeMineralByLevel: <int, int>{2: 15, 3: 30, 4: 60},
    refugeUpgradeBioBatteriesByLevel: <int, int>{2: 2, 3: 4, 4: 8},
    refugeUpgradeMinutes: 1,
  ),
  progression: const PTibugProgressionConfig(
    maximumLevel: 6,
    xpRequiredByLevel: <int, int>{1: 100, 2: 200, 3: 300, 4: 400, 5: 500},
    yieldBonusPerLevel: .10,
    baseEnergyPerDay: 3,
    energyReductionPerLevel: 1,
    minimumEnergyPerDay: 1,
    renewalLevel: 3,
    renewalMaterialCost: <String, int>{},
    renewalEnergyCost: 0,
    renewalBioBatteryCost: 0,
    renewalDurationMinutes: 0,
    maximumRenewals: 1,
  ),
  moduleCapacity: const PTibugModuleCapacityConfig(
    initialCapacity: 1,
    maximumUpgrades: 2,
    capacityPerUpgrade: 1,
    materialCostsByLevel: <int, Map<String, int>>{
      1: <String, int>{'Organique': 60, 'Minéral': 30},
      2: <String, int>{'Organique': 120, 'Minéral': 60},
    },
    bioBatteryCostsByLevel: <int, int>{1: 10, 2: 20},
    dataCostsByLevel: <int, Map<PTibugDataFamily, int>>{
      1: <PTibugDataFamily, int>{
        PTibugDataFamily.organique: 10,
        PTibugDataFamily.minerale: 5,
        PTibugDataFamily.mycelienne: 5,
        PTibugDataFamily.toxine: 2,
        PTibugDataFamily.biomimetisme: 10,
        PTibugDataFamily.energie: 5,
        PTibugDataFamily.comportementInsectoide: 10
      },
      2: <PTibugDataFamily, int>{
        PTibugDataFamily.organique: 20,
        PTibugDataFamily.minerale: 10,
        PTibugDataFamily.mycelienne: 10,
        PTibugDataFamily.toxine: 4,
        PTibugDataFamily.biomimetisme: 20,
        PTibugDataFamily.energie: 10,
        PTibugDataFamily.comportementInsectoide: 20
      },
    },
  ),
  weather: const PTibugWeatherConfig(
    productionMalusPercent: 30,
    sensorMaterialPenaltyPercent: 50,
    sensorChanceByLevel: <int, int>{1: 5, 2: 10, 3: 15},
    sensorPityEnabled: false,
    sensorPityCycleThreshold: 0,
    stabilizerRegenerationPercentByLevel: <int, int>{1: 5, 2: 10, 3: 15},
    stabilizerMaximumPercent: 30,
    economyOrganicReductionPercentByLevel: <int, int>{1: 20, 2: 40, 3: 60},
    economyEnergyReductionPercentByLevel: <int, int>{1: 10, 2: 20, 3: 30},
  ),
);

/// Active tuning published by the internal Dashboard. Player-owned P'TIBUG
/// progress is intentionally kept out of this configuration.
PTibugConfig pTibugConfig = defaultPTibugConfig;
