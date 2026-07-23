enum ForageBiome { colline, plaineRiche, bassinMineral, sousBois }

enum ForageDuration { oneHour, twoHours, sixHours, tenHours }

enum ForageIntensity { doux, normal, intensif }

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
    required this.vitalityMultiplier,
    required this.riskModifierPercent,
    required this.zoneFatigueLabel,
  });

  final String label;
  final double rewardMultiplier;
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
      label: 'Colline',
      tendency: 'mixte',
      baseRewards: <String, int>{'Organique': 4, 'Minéral': 3},
      baseRiskPercent: 45,
      wasteBaseGain: 3,
      hazards: <ForageHazard>[
        ForageHazard.terrainInstable,
        ForageHazard.droneErrant
      ],
    ),
    ForageBiome.plaineRiche: ForageBiomeConfig(
      label: 'Plaine',
      tendency: 'départ / restauration',
      baseRewards: <String, int>{'Organique': 2, 'Minéral': 1},
      baseRiskPercent: 30,
      wasteBaseGain: 2,
      restorationLevel: 0,
      restorationStage: 'Plaine desséchée',
      hazards: <ForageHazard>[
        ForageHazard.climatDifficile,
        ForageHazard.droneErrant
      ],
    ),
    ForageBiome.bassinMineral: ForageBiomeConfig(
      label: 'Bassin minéral',
      tendency: 'Minéral',
      baseRewards: <String, int>{'Organique': 1, 'Minéral': 5},
      baseRiskPercent: 35,
      wasteBaseGain: 3,
      hazards: <ForageHazard>[
        ForageHazard.terrainInstable,
        ForageHazard.droneErrant
      ],
    ),
    ForageBiome.sousBois: ForageBiomeConfig(
      label: 'Sous-bois',
      tendency: 'Organique / transformation',
      baseRewards: <String, int>{'Organique': 5, 'Minéral': 1},
      baseRiskPercent: 40,
      wasteBaseGain: 4,
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
      vitalityMultiplier: 0.75,
      riskModifierPercent: -5,
      zoneFatigueLabel: 'faible',
    ),
    ForageIntensity.normal: ForageIntensityConfig(
      label: 'Normal',
      rewardMultiplier: 1,
      vitalityMultiplier: 1,
      riskModifierPercent: 0,
      zoneFatigueLabel: 'normale',
    ),
    ForageIntensity.intensif: ForageIntensityConfig(
      label: 'Intensif',
      rewardMultiplier: 1.35,
      vitalityMultiplier: 1.25,
      riskModifierPercent: 10,
      zoneFatigueLabel: 'forte',
    ),
  },
);

LisiereForageConfig lisiereForageConfig = defaultLisiereForageConfig;
