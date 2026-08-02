enum ForageBiome { colline, plaineRiche, bassinMineral, sousBois }

enum ForageDuration { oneHour, twoHours, sixHours, tenHours }

enum ForageIntensity { doux, normal, intensif }

enum ForageMissionType { harvest, research }

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
    required this.revitalizeGain,
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
  final int revitalizeGain;
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
      label: 'Hauts-Refuges',
      tendency: 'mixte',
      baseRewards: <String, int>{'Organique': 4, 'Minéral': 3},
      baseRiskPercent: 45,
      wasteBaseGain: 3,
      wasteHoursPerLevelRegeneration: 3,
      hazards: <ForageHazard>[
        ForageHazard.terrainInstable,
        ForageHazard.droneErrant
      ],
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
    ),
    ForageBiome.bassinMineral: ForageBiomeConfig(
      label: 'Semi-désert / Garrigue tropicale',
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
      label: 'Forêt humide relictuelle',
      tendency: 'Organique / transformation',
      baseRewards: <String, int>{'Organique': 5, 'Minéral': 1},
      baseRiskPercent: 40,
      wasteBaseGain: 4,
      wasteHoursPerLevelRegeneration: 2,
      hazards: <ForageHazard>[
        ForageHazard.pollution,
        ForageHazard.climatDifficile
      ],
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
      ForageIntensity.doux: 4,
      ForageIntensity.normal: 8,
      ForageIntensity.intensif: 16,
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
    revitalizeBaseOrganicCost: 4,
    revitalizeBaseMineralCost: 2,
    revitalizeGain: 10,
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
      // Les Cellules restent une trouvaille occasionnelle pendant une
      // Récolte : moitié moins de chances que le réglage précédent.
      cellChanceMultiplier: .125,
      maximumCellsMultiplier: 1,
      wastePerHour: 1,
    ),
    ForageMissionType.research: ForageMissionTypeConfig(
      label: 'Recherche',
      vigorMultiplier: .20,
      // La Recherche est la voie active d'acquisition des Cellules.
      cellChanceMultiplier: 1.5,
      maximumCellsMultiplier: 1,
      wastePerHour: 2,
    ),
  },
);

LisiereForageConfig lisiereForageConfig = defaultLisiereForageConfig;
