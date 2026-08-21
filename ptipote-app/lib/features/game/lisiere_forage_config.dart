enum ForageBiome { colline, plaineRiche, bassinMineral, sousBois }

enum ForageDuration { oneHour, twoHours, sixHours, tenHours }

enum ForageIntensity { doux, normal, intensif }

enum ForageMissionType { harvest, research }

/// Richesse naturelle utilisée par la récolte de Mycélium. Les identifiants
/// de biome restent inchangés : seule leur configuration évolue.
enum MyceliumRichness { none, medium, rich }

class ForageMissionTypeConfig {
  const ForageMissionTypeConfig({
    required this.label,
    required this.vigorMultiplier,
    required this.cellChanceMultiplier,
    required this.maximumCellsMultiplier,
    required this.wastePerHour,
  });

  final String label;
  final double vigorMultiplier;
  final double cellChanceMultiplier;
  final double maximumCellsMultiplier;
  final int wastePerHour;
}

enum ForageHazard {
  none,
  pollution,
  droneErrant,
  climatDifficile,
  terrainInstable,
}

class LisiereForageConfig {
  const LisiereForageConfig({
    required this.forageTimeScale,
    required this.refugeSafetyFallback,
    required this.minimumMissionRisk,
    required this.securityRiskReductionFactor,
    required this.wasteLevelMax,
    required this.wasteMultiplierPerLevel,
    required this.wasteHoursPerLevelDepletion,
    required this.organicBonusAtZeroWaste,
    required this.inventorySlotLimit,
    required this.inventoryStackLimit,
    required this.xpGainByDuration,
    required this.intensityXpMultiplier,
    required this.biomes,
    required this.durations,
    required this.intensities,
    required this.biomass,
    required this.missionTypes,
    required this.territoryBuildings,
    required this.myceliumExploration,
  });

  final int forageTimeScale;
  final int refugeSafetyFallback;
  final int minimumMissionRisk;
  final double securityRiskReductionFactor;
  final int wasteLevelMax;
  final double wasteMultiplierPerLevel;
  final double wasteHoursPerLevelDepletion;
  final double organicBonusAtZeroWaste;
  final int inventorySlotLimit;
  final int inventoryStackLimit;
  final Map<ForageDuration, int> xpGainByDuration;
  final Map<ForageIntensity, double> intensityXpMultiplier;
  final Map<ForageBiome, ForageBiomeConfig> biomes;
  final Map<ForageDuration, ForageDurationConfig> durations;
  final Map<ForageIntensity, ForageIntensityConfig> intensities;
  final BiomassConfig biomass;
  final Map<ForageMissionType, ForageMissionTypeConfig> missionTypes;
  final LisiereTerritoryBuildingsConfig territoryBuildings;
  final MyceliumExplorationConfig myceliumExploration;
}

class MyceliumExplorationConfig {
  const MyceliumExplorationConfig({
    required this.yieldByRichness,
    required this.mycelialTypeGatherBonus,
  });

  final Map<MyceliumRichness, int> yieldByRichness;
  final double mycelialTypeGatherBonus;
}

/// Configuration centralisée des bâtiments attachés à un biome. Il n'y a pas
/// de coordonnées libres : une zone ne possède qu'un seul emplacement.
class LisiereTerritoryBuildingsConfig {
  const LisiereTerritoryBuildingsConfig({
    required this.slotsPerZone,
    required this.biofermenter,
  });
  final int slotsPerZone;
  final BiofermenterConfig biofermenter;
}

/// Réglages communs aux modules de production des bâtiments territoriaux.
/// Le multiplicateur ne concerne volontairement que la synergie P'TIBUG : la
/// production de base d'un bâtiment reste toujours modeste et stable.
class BiomeProductionSynergyConfig {
  const BiomeProductionSynergyConfig({
    required this.ptibugBonusPerDay,
    required this.maxEligiblePtibugs,
    required this.mainModuleMultipliers,
    required this.secondarySlotCount,
    required this.securityFloors,
    required this.researchFloors,
    required this.weatherDamageReductions,
    required this.standardModuleBuild,
    required this.weatherModuleBuild,
  });

  final double ptibugBonusPerDay;
  final int maxEligiblePtibugs;
  final Map<int, double> mainModuleMultipliers;
  final int secondarySlotCount;
  final Map<int, int> securityFloors;
  final Map<int, int> researchFloors;
  final Map<int, double> weatherDamageReductions;
  final BiomeSecondaryModuleBuildConfig standardModuleBuild;
  final BiomeSecondaryModuleBuildConfig weatherModuleBuild;
}

/// Coûts explicites et durées des chantiers de modules territoriaux. Les
/// ressources physiques et les Données restent volontairement séparées.
class BiomeSecondaryModuleBuildConfig {
  const BiomeSecondaryModuleBuildConfig({
    required this.resourceCostsByLevel,
    required this.dataCostsByLevel,
    required this.durationMinutesByLevel,
  });

  final Map<int, Map<String, int>> resourceCostsByLevel;
  final Map<int, Map<String, int>> dataCostsByLevel;
  final Map<int, int> durationMinutesByLevel;
}

class BiofermenterConfig {
  const BiofermenterConfig({
    required this.passiveOrganicPerDayByLevel,
    required this.constructionCost,
    required this.upgradeCosts,
    required this.passiveProductionMultiplier,
    required this.vatCount,
    required this.vatEfficiencyMultiplier,
    required this.lithocultureMineralPerCycle,
    required this.lithocultureOrganicPerCycle,
    required this.lithocultureCycleMinutes,
    required this.normalMineralPerOrganic,
    required this.mineralBasinMineralPerOrganic,
    required this.wasteCanReplaceMineral,
    required this.mineralEquivalentPerWaste,
    required this.maxWasteSharePerBatch,
    required this.edibleForestEnabled,
    required this.edibleForestCost,
    required this.pollinatorTraitId,
    required this.bonusPerPollinator,
    required this.maxPollinatorsCounted,
    required this.futureScarabeHookEnabled,
    required this.futureScarabeMineralPerOrganic,
    required this.constructionMinutesByLevel,
    required this.edibleForestConstructionMinutes,
    required this.mycelialNetworkEnabled,
    required this.mycelialNetworkCost,
    required this.mycelialNetworkConstructionMinutes,
    required this.baseMyceliumPerDay,
    required this.myceliumBiomeMultipliers,
    required this.mycelialTraitId,
    required this.mycelialTraitBonusPerPTibug,
    required this.maxMycelialPTibugsCounted,
    required this.calciumBasinEnabled,
    required this.calciumBasinCost,
    required this.calciumBasinConstructionMinutes,
    required this.lithocultureTankBaseCapacity,
    required this.lithocultureTankCapacityPerLevel,
    required this.calciumOrganicBaseCapacity,
    required this.calciumOrganicCapacityPerLevel,
    required this.calciumWaterBaseCapacity,
    required this.calciumWaterCapacityPerLevel,
    required this.calciumMineralReserveBaseCapacity,
    required this.calciumMineralReserveCapacityPerLevel,
    required this.calciumMineralPerTenStoredPerHour,
    required this.calciumOrganicPerActiveHour,
    required this.calciumWaterPerActiveHour,
    required this.calciumMinerTraitBonusPerPTibug,
    required this.calciumEligibleTraitIds,
    required this.biomeSynergy,
    required this.mineralBasinProductionPerDay,
    required this.mineralBasinWaterCapacity,
    required this.mineralBasinOrganicCapacity,
    required this.mineralBasinWaterConsumptionPerDay,
    required this.mineralBasinOrganicConsumptionPerDay,
    required this.rainRefillsMineralBasinWater,
  });
  final Map<int, double> passiveOrganicPerDayByLevel;
  final Map<String, int> constructionCost;
  final Map<int, Map<String, int>> upgradeCosts;
  final double passiveProductionMultiplier;
  final int vatCount;
  final double vatEfficiencyMultiplier;

  /// Champs legacy conservés uniquement pour lire les anciennes sauvegardes.
  /// Aucun cycle Lithoculture ne peut encore être lancé.
  final int lithocultureMineralPerCycle;
  final int lithocultureOrganicPerCycle;
  final int lithocultureCycleMinutes;
  final int normalMineralPerOrganic;
  final int mineralBasinMineralPerOrganic;
  final bool wasteCanReplaceMineral;
  final double mineralEquivalentPerWaste;
  final double maxWasteSharePerBatch;
  final bool edibleForestEnabled;
  final Map<String, int> edibleForestCost;
  final String pollinatorTraitId;
  final double bonusPerPollinator;
  final int maxPollinatorsCounted;
  final bool futureScarabeHookEnabled;
  final int futureScarabeMineralPerOrganic;
  final Map<int, int> constructionMinutesByLevel;
  final int edibleForestConstructionMinutes;
  final bool mycelialNetworkEnabled;
  final Map<String, int> mycelialNetworkCost;
  final int mycelialNetworkConstructionMinutes;
  final double baseMyceliumPerDay;
  final Map<MyceliumRichness, double> myceliumBiomeMultipliers;
  final String mycelialTraitId;
  final double mycelialTraitBonusPerPTibug;
  final int maxMycelialPTibugsCounted;
  final bool calciumBasinEnabled;
  final Map<String, int> calciumBasinCost;
  final int calciumBasinConstructionMinutes;
  final int lithocultureTankBaseCapacity;
  final int lithocultureTankCapacityPerLevel;
  final int calciumOrganicBaseCapacity;
  final int calciumOrganicCapacityPerLevel;
  final int calciumWaterBaseCapacity;
  final int calciumWaterCapacityPerLevel;
  final int calciumMineralReserveBaseCapacity;
  final int calciumMineralReserveCapacityPerLevel;
  final int calciumMineralPerTenStoredPerHour;
  final int calciumOrganicPerActiveHour;
  final int calciumWaterPerActiveHour;
  final int calciumMinerTraitBonusPerPTibug;
  final List<String> calciumEligibleTraitIds;

  final BiomeProductionSynergyConfig biomeSynergy;
  final Map<int, double> mineralBasinProductionPerDay;
  final Map<int, int> mineralBasinWaterCapacity;
  final Map<int, int> mineralBasinOrganicCapacity;
  final Map<int, double> mineralBasinWaterConsumptionPerDay;
  final Map<int, double> mineralBasinOrganicConsumptionPerDay;
  final bool rainRefillsMineralBasinWater;
}

class BiomassTierConfig {
  const BiomassTierConfig({
    required this.minimumPercent,
    required this.maximumPercent,
    required this.multiplier,
  });

  final int minimumPercent;
  final int maximumPercent;
  final double multiplier;

  bool contains(int percent) =>
      percent >= minimumPercent && percent <= maximumPercent;
}

class BiomassVisualStateConfig {
  const BiomassVisualStateConfig({
    required this.minimumPercent,
    required this.maximumPercent,
    required this.label,
    required this.icon,
  });

  final int minimumPercent;
  final int maximumPercent;
  final String label;
  final String icon;

  bool contains(int percent) =>
      percent >= minimumPercent && percent <= maximumPercent;
}

class BiomassConfig {
  const BiomassConfig({
    required this.maximumPercent,
    required this.missionConsumptionByIntensity,
    required this.resourceYieldTiers,
    required this.recoveryHoursPerPoint,
    required this.recoveryTiers,
    required this.revitalizeBaseOrganicCost,
    required this.revitalizeBaseMineralCost,
    required this.revitalizeBaseMyceliumCost,
    required this.revitalizeGain,
    required this.revitalizeCooldownHours,
    required this.revitalizeCostTiers,
    required this.ptibugYieldTiers,
    required this.visualStates,
  });

  final int maximumPercent;
  final Map<ForageIntensity, int> missionConsumptionByIntensity;
  final List<BiomassTierConfig> resourceYieldTiers;
  final double recoveryHoursPerPoint;
  final List<BiomassTierConfig> recoveryTiers;
  final int revitalizeBaseOrganicCost;
  final int revitalizeBaseMineralCost;
  final int revitalizeBaseMyceliumCost;
  final int revitalizeGain;
  final int revitalizeCooldownHours;
  final List<BiomassTierConfig> revitalizeCostTiers;
  final List<BiomassTierConfig> ptibugYieldTiers;
  final List<BiomassVisualStateConfig> visualStates;
}

class ForageBiomeConfig {
  const ForageBiomeConfig({
    required this.label,
    required this.tendency,
    required this.baseRewards,
    required this.baseRiskPercent,
    this.restorationLevel = 0,
    this.restorationStage = 'base',
    this.organicRewardModifier = 0,
    this.mineralRewardModifier = 0,
    this.riskModifier = 0,
    this.linkedPtipoteRefugeBonus = 0,
    this.wasteBaseGain = 0,
    this.wasteHoursPerLevelRegeneration = 0,
    this.myceliumRichness = MyceliumRichness.none,
    this.hazards = const <ForageHazard>[],
  });

  final String label;
  final String tendency;
  final Map<String, int> baseRewards;
  final int baseRiskPercent;
  final int restorationLevel;
  final String restorationStage;
  final double organicRewardModifier;
  final double mineralRewardModifier;
  final int riskModifier;
  final int linkedPtipoteRefugeBonus;
  final int wasteBaseGain;

  /// Real-time hours required to regenerate one waste level in this biome.
  final double wasteHoursPerLevelRegeneration;
  final MyceliumRichness myceliumRichness;
  final List<ForageHazard> hazards;
}

class ForageDurationConfig {
  const ForageDurationConfig({
    required this.label,
    required this.theoreticalHours,
    required this.baseVitalityCost,
  });

  final String label;
  final int theoreticalHours;
  final int baseVitalityCost;

  Duration realDuration(int forageTimeScale) {
    final minutes = (theoreticalHours * 60 / forageTimeScale).round();
    return Duration(minutes: minutes);
  }
}

class ForageIntensityConfig {
  const ForageIntensityConfig({
    required this.label,
    required this.rewardMultiplier,
    required this.timeMultiplier,
    required this.vitalityMultiplier,
    required this.riskModifierPercent,
    required this.zoneFatigueLabel,
  });

  final String label;
  final double rewardMultiplier;

  /// Real mission duration multiplier. Intensive runs finish faster; Douce
  /// runs take longer while consuming less Biomass.
  final double timeMultiplier;
  final double vitalityMultiplier;
  final int riskModifierPercent;
  final String zoneFatigueLabel;
}

const LisiereForageConfig defaultLisiereForageConfig = LisiereForageConfig(
  forageTimeScale: 6,
  refugeSafetyFallback: 0,
  minimumMissionRisk: 5,
  securityRiskReductionFactor: 0.4,
  wasteLevelMax: 10,
  wasteMultiplierPerLevel: 0.15,
  wasteHoursPerLevelDepletion: 1,
  organicBonusAtZeroWaste: 0.30,
  inventorySlotLimit: 10,
  inventoryStackLimit: 10,
  xpGainByDuration: <ForageDuration, int>{
    ForageDuration.oneHour: 10,
    ForageDuration.twoHours: 18,
    ForageDuration.sixHours: 45,
    ForageDuration.tenHours: 75,
  },
  intensityXpMultiplier: <ForageIntensity, double>{
    ForageIntensity.doux: 0.85,
    ForageIntensity.normal: 1,
    ForageIntensity.intensif: 1.20,
  },
  biomes: <ForageBiome, ForageBiomeConfig>{
    ForageBiome.colline: ForageBiomeConfig(
      label: 'Forêt sèche',
      tendency: 'mixte',
      baseRewards: <String, int>{'Organique': 4, 'Minéral': 3},
      baseRiskPercent: 45,
      wasteBaseGain: 3,
      wasteHoursPerLevelRegeneration: 3,
      hazards: <ForageHazard>[
        ForageHazard.terrainInstable,
        ForageHazard.droneErrant
      ],
      myceliumRichness: MyceliumRichness.medium,
    ),
    ForageBiome.plaineRiche: ForageBiomeConfig(
      label: 'Savane tropicale',
      tendency: 'départ / restauration',
      baseRewards: <String, int>{'Organique': 2, 'Minéral': 1},
      baseRiskPercent: 30,
      wasteBaseGain: 2,
      wasteHoursPerLevelRegeneration: 1,
      restorationLevel: 0,
      restorationStage: 'Savane tropicale desséchée',
      hazards: <ForageHazard>[
        ForageHazard.climatDifficile,
        ForageHazard.droneErrant
      ],
      myceliumRichness: MyceliumRichness.medium,
    ),
    ForageBiome.bassinMineral: ForageBiomeConfig(
      label: 'Bassin minéral',
      tendency: 'Minéral',
      baseRewards: <String, int>{'Organique': 1, 'Minéral': 5},
      baseRiskPercent: 35,
      wasteBaseGain: 3,
      wasteHoursPerLevelRegeneration: 2,
      hazards: <ForageHazard>[
        ForageHazard.terrainInstable,
        ForageHazard.droneErrant
      ],
    ),
    ForageBiome.sousBois: ForageBiomeConfig(
      label: 'Forêt humide',
      tendency: 'Organique / transformation',
      baseRewards: <String, int>{'Organique': 5, 'Minéral': 1},
      baseRiskPercent: 40,
      wasteBaseGain: 4,
      wasteHoursPerLevelRegeneration: 2,
      hazards: <ForageHazard>[
        ForageHazard.pollution,
        ForageHazard.climatDifficile
      ],
      myceliumRichness: MyceliumRichness.rich,
    ),
  },
  durations: <ForageDuration, ForageDurationConfig>{
    ForageDuration.oneHour: ForageDurationConfig(
      label: '1h',
      theoreticalHours: 1,
      baseVitalityCost: 15,
    ),
    ForageDuration.twoHours: ForageDurationConfig(
      label: '2h',
      theoreticalHours: 2,
      baseVitalityCost: 25,
    ),
    ForageDuration.sixHours: ForageDurationConfig(
      label: '6h',
      theoreticalHours: 6,
      baseVitalityCost: 55,
    ),
    ForageDuration.tenHours: ForageDurationConfig(
      label: '10h',
      theoreticalHours: 10,
      baseVitalityCost: 80,
    ),
  },
  intensities: <ForageIntensity, ForageIntensityConfig>{
    ForageIntensity.doux: ForageIntensityConfig(
      label: 'Doux',
      rewardMultiplier: 0.75,
      timeMultiplier: 1.25,
      vitalityMultiplier: 0.75,
      riskModifierPercent: -5,
      zoneFatigueLabel: 'faible',
    ),
    ForageIntensity.normal: ForageIntensityConfig(
      label: 'Normal',
      rewardMultiplier: 1,
      timeMultiplier: 1,
      vitalityMultiplier: 1,
      riskModifierPercent: 0,
      zoneFatigueLabel: 'normale',
    ),
    ForageIntensity.intensif: ForageIntensityConfig(
      label: 'Intensif',
      rewardMultiplier: 1.35,
      timeMultiplier: .75,
      vitalityMultiplier: 1.25,
      riskModifierPercent: 10,
      zoneFatigueLabel: 'forte',
    ),
  },
  biomass: BiomassConfig(
    maximumPercent: 100,
    missionConsumptionByIntensity: <ForageIntensity, int>{
      ForageIntensity.doux: 2,
      ForageIntensity.normal: 4,
      ForageIntensity.intensif: 8,
    },
    resourceYieldTiers: <BiomassTierConfig>[
      BiomassTierConfig(minimumPercent: 50, maximumPercent: 100, multiplier: 1),
      BiomassTierConfig(
          minimumPercent: 20, maximumPercent: 49, multiplier: .75),
      BiomassTierConfig(minimumPercent: 0, maximumPercent: 19, multiplier: .5),
    ],
    // Vigueur recoveries are intentionally slow: one point takes two hours
    // at the healthy tier (half the former recovery rate).
    recoveryHoursPerPoint: 2,
    recoveryTiers: <BiomassTierConfig>[
      BiomassTierConfig(minimumPercent: 50, maximumPercent: 100, multiplier: 1),
      BiomassTierConfig(minimumPercent: 30, maximumPercent: 49, multiplier: 2),
      BiomassTierConfig(minimumPercent: 20, maximumPercent: 29, multiplier: 4),
      BiomassTierConfig(minimumPercent: 10, maximumPercent: 19, multiplier: 8),
      BiomassTierConfig(minimumPercent: 0, maximumPercent: 9, multiplier: 16),
    ],
    revitalizeBaseOrganicCost: 10,
    revitalizeBaseMineralCost: 10,
    revitalizeBaseMyceliumCost: 10,
    revitalizeGain: 15,
    revitalizeCooldownHours: 24,
    revitalizeCostTiers: <BiomassTierConfig>[
      BiomassTierConfig(minimumPercent: 50, maximumPercent: 100, multiplier: 1),
      BiomassTierConfig(minimumPercent: 30, maximumPercent: 49, multiplier: 2),
      BiomassTierConfig(minimumPercent: 10, maximumPercent: 29, multiplier: 3),
      BiomassTierConfig(minimumPercent: 0, maximumPercent: 9, multiplier: 4),
    ],
    ptibugYieldTiers: <BiomassTierConfig>[
      BiomassTierConfig(minimumPercent: 50, maximumPercent: 100, multiplier: 1),
      BiomassTierConfig(
          minimumPercent: 20, maximumPercent: 49, multiplier: .75),
      BiomassTierConfig(minimumPercent: 0, maximumPercent: 19, multiplier: .5),
    ],
    visualStates: <BiomassVisualStateConfig>[
      BiomassVisualStateConfig(
          minimumPercent: 80,
          maximumPercent: 100,
          label: 'Luxuriante',
          icon: '🌿'),
      BiomassVisualStateConfig(
          minimumPercent: 50, maximumPercent: 79, label: 'Stable', icon: '🌱'),
      BiomassVisualStateConfig(
          minimumPercent: 20, maximumPercent: 49, label: 'Fragile', icon: '🍂'),
      BiomassVisualStateConfig(
          minimumPercent: 0, maximumPercent: 19, label: 'Épuisée', icon: '🪨'),
    ],
  ),
  missionTypes: const <ForageMissionType, ForageMissionTypeConfig>{
    ForageMissionType.harvest: ForageMissionTypeConfig(
      label: 'Récolte',
      vigorMultiplier: 1,
      // Les Capsules ne sont jamais obtenues en Récolte. The technical field
      // remains for save/dashboard compatibility with the shared engine.
      cellChanceMultiplier: 0,
      maximumCellsMultiplier: 1,
      wastePerHour: 1,
    ),
    ForageMissionType.research: ForageMissionTypeConfig(
      label: 'Recherche',
      vigorMultiplier: .20,
      // La Recherche de la Tour est la voie active d'acquisition des Capsules.
      cellChanceMultiplier: 1.5,
      maximumCellsMultiplier: 1,
      wastePerHour: 2,
    ),
  },
  territoryBuildings: LisiereTerritoryBuildingsConfig(
    slotsPerZone: 1,
    biofermenter: BiofermenterConfig(
      passiveOrganicPerDayByLevel: const <int, double>{
        1: 12,
        2: 18,
        3: 24,
        4: 30
      },
      // Valeurs provisoires : elles restent exposées au Dashboard.
      constructionCost: const <String, int>{'Organique': 20, 'Minéral': 20},
      upgradeCosts: const <int, Map<String, int>>{
        2: <String, int>{'Organique': 30, 'Minéral': 30},
        3: <String, int>{'Organique': 45, 'Minéral': 45},
        4: <String, int>{'Organique': 60, 'Minéral': 60},
      },
      passiveProductionMultiplier: 1,
      vatCount: 1,
      vatEfficiencyMultiplier: 1,
      lithocultureMineralPerCycle: 10,
      lithocultureOrganicPerCycle: 3,
      lithocultureCycleMinutes: 60,
      normalMineralPerOrganic: 3,
      mineralBasinMineralPerOrganic: 2,
      wasteCanReplaceMineral: true,
      mineralEquivalentPerWaste: 1,
      maxWasteSharePerBatch: 1,
      edibleForestEnabled: true,
      edibleForestCost: const <String, int>{
        'Organique': 20,
        'Minéral': 10,
        'Mycélium': 10
      },
      pollinatorTraitId: 'pollinisateur',
      bonusPerPollinator: .10,
      maxPollinatorsCounted: 3,
      futureScarabeHookEnabled: false,
      futureScarabeMineralPerOrganic: 4,
      constructionMinutesByLevel: const <int, int>{
        1: 60,
        2: 120,
        3: 180,
        4: 240
      },
      edibleForestConstructionMinutes: 60,
      mycelialNetworkEnabled: true,
      mycelialNetworkCost: const <String, int>{
        'Organique': 20,
        'Minéral': 10,
        'Mycélium': 10,
      },
      mycelialNetworkConstructionMinutes: 60,
      baseMyceliumPerDay: 8,
      myceliumBiomeMultipliers: const <MyceliumRichness, double>{
        MyceliumRichness.none: 1,
        MyceliumRichness.medium: 1.25,
        MyceliumRichness.rich: 1.5,
      },
      mycelialTraitId: 'decomposeur',
      mycelialTraitBonusPerPTibug: .10,
      maxMycelialPTibugsCounted: 3,
      calciumBasinEnabled: true,
      calciumBasinCost: const <String, int>{
        'Organique': 20,
        'Minéral': 20,
        'Mycélium': 10,
      },
      calciumBasinConstructionMinutes: 60,
      lithocultureTankBaseCapacity: 30,
      lithocultureTankCapacityPerLevel: 10,
      calciumOrganicBaseCapacity: 9,
      calciumOrganicCapacityPerLevel: 3,
      calciumWaterBaseCapacity: 30,
      calciumWaterCapacityPerLevel: 10,
      calciumMineralReserveBaseCapacity: 30,
      calciumMineralReserveCapacityPerLevel: 10,
      calciumMineralPerTenStoredPerHour: 1,
      calciumOrganicPerActiveHour: 1,
      calciumWaterPerActiveHour: 2,
      calciumMinerTraitBonusPerPTibug: 1,
      calciumEligibleTraitIds: const <String>['mineur', 'lithoculture'],
      biomeSynergy: const BiomeProductionSynergyConfig(
        ptibugBonusPerDay: 3,
        maxEligiblePtibugs: 3,
        mainModuleMultipliers: <int, double>{1: 1, 2: 2, 3: 3},
        secondarySlotCount: 2,
        securityFloors: <int, int>{1: 20, 2: 35, 3: 50},
        researchFloors: <int, int>{1: 20, 2: 35, 3: 50},
        weatherDamageReductions: <int, double>{1: .15, 2: .30, 3: .50},
        standardModuleBuild: BiomeSecondaryModuleBuildConfig(
          resourceCostsByLevel: <int, Map<String, int>>{
            1: <String, int>{'Minéral': 10, 'Organique': 30},
            2: <String, int>{'Minéral': 20, 'Organique': 40},
            3: <String, int>{'Minéral': 25, 'Organique': 45},
          },
          dataCostsByLevel: <int, Map<String, int>>{
            1: <String, int>{'biomimetisme': 10, 'energie': 10},
            2: <String, int>{'energie': 10, 'mycelienne': 5},
            3: <String, int>{'mycelienne': 10},
          },
          durationMinutesByLevel: <int, int>{1: 60, 2: 120, 3: 180},
        ),
        weatherModuleBuild: BiomeSecondaryModuleBuildConfig(
          resourceCostsByLevel: <int, Map<String, int>>{
            1: <String, int>{'Minéral': 10, 'Organique': 30},
            2: <String, int>{'Minéral': 20, 'Organique': 40},
            3: <String, int>{'Minéral': 25, 'Organique': 45},
          },
          dataCostsByLevel: <int, Map<String, int>>{
            1: <String, int>{
              'biomimetisme': 10,
              'energie': 5,
              'toxine': 2,
            },
            2: <String, int>{'energie': 5, 'mycelienne': 2, 'toxine': 2},
            3: <String, int>{'mycelienne': 5, 'toxine': 5},
          },
          durationMinutesByLevel: <int, int>{1: 60, 2: 120, 3: 180},
        ),
      ),
      // Le ratio reste volontairement identique au N1 : les niveaux
      // supérieurs accélèrent la biominéralisation sans créer une nouvelle
      // ressource ni une consommation cachée.
      mineralBasinProductionPerDay: const <int, double>{
        1: 12,
        2: 15,
        3: 18,
      },
      mineralBasinWaterCapacity: const <int, int>{1: 24, 2: 36, 3: 48},
      mineralBasinOrganicCapacity: const <int, int>{1: 12, 2: 18, 3: 24},
      mineralBasinWaterConsumptionPerDay: const <int, double>{
        1: 24,
        2: 18,
        3: 12,
      },
      mineralBasinOrganicConsumptionPerDay: const <int, double>{
        1: 18,
        2: 12,
        3: 6,
      },
      rainRefillsMineralBasinWater: true,
    ),
  ),
  myceliumExploration: const MyceliumExplorationConfig(
    yieldByRichness: <MyceliumRichness, int>{
      MyceliumRichness.none: 0,
      MyceliumRichness.medium: 2,
      MyceliumRichness.rich: 3,
    },
    mycelialTypeGatherBonus: .50,
  ),
);

LisiereForageConfig lisiereForageConfig = defaultLisiereForageConfig;
