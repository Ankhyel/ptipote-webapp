import 'dart:math' as math;

/// Runtime-tunable everyday progression rules.  It deliberately contains only
/// shared values: player progress remains in [PtipoteV2Profile].
class PtipoteDailyLifeConfig {
  const PtipoteDailyLifeConfig({
    this.autoSleepThreshold = 30,
    this.autoEatThreshold = 20,
    this.energyMaxBonusPerLevel = 15,
    this.hungerMaxBonusPerLevel = 5,
    this.materialMax = 30,
    this.vitalMax = 20,
    this.attachmentMax = 50,
    this.furnitureBonusPerUniqueType = 2.5,
    this.furnitureMax = 10,
    this.otherPtipoteBonus = 10,
    this.homeLevelBonusPerLevel = 2.5,
    this.homeLevelBonusMax = 10,
    this.vitalLowThreshold = 30,
    this.vitalHighThreshold = 70,
    this.vitalMidBonus = 5,
    this.vitalHighBonus = 10,
    this.attachmentDecayPerHour = 1,
    this.hugAttachmentGain = 5,
    this.trainingAttachmentGain = 20,
    this.walkAttachmentGain = 30,
    this.movementLives = 3,
    this.movementSequenceLength = 10,
    this.movementInputWindowMs = 1000,
    this.movementBaseIntervalMs = 2000,
    this.movementIntervalReductionPerLevelMs = 50,
    this.movementXpPerLevel = 10,
    this.hideAndSeekWeight = 1,
    this.catchMeWeight = 1,
    this.artisanLevel1BaseReduction = .05,
    this.artisanLevel2BaseReduction = .10,
    this.artisanLevel3BaseReduction = .15,
    this.artisanPtipoteLevelReduction = .01,
    this.vendorLevel1BaseBonus = .05,
    this.vendorLevel2BaseBonus = .10,
    this.vendorLevel3BaseBonus = .15,
    this.vendorPtipoteLevelBonus = .01,
    this.legacyAttachmentInitialValue = 25,
  });

  final int autoSleepThreshold;
  final int autoEatThreshold;
  final int energyMaxBonusPerLevel;
  final int hungerMaxBonusPerLevel;
  final double materialMax;
  final double vitalMax;
  final double attachmentMax;
  final double furnitureBonusPerUniqueType;
  final double furnitureMax;
  final double otherPtipoteBonus;
  final double homeLevelBonusPerLevel;
  final double homeLevelBonusMax;
  final int vitalLowThreshold;
  final int vitalHighThreshold;
  final double vitalMidBonus;
  final double vitalHighBonus;
  final double attachmentDecayPerHour;
  final double hugAttachmentGain;
  final double trainingAttachmentGain;
  final double walkAttachmentGain;
  final int movementLives;
  final int movementSequenceLength;
  final int movementInputWindowMs;
  final int movementBaseIntervalMs;
  final int movementIntervalReductionPerLevelMs;
  final int movementXpPerLevel;
  final double hideAndSeekWeight;
  final double catchMeWeight;
  final double artisanLevel1BaseReduction;
  final double artisanLevel2BaseReduction;
  final double artisanLevel3BaseReduction;
  final double artisanPtipoteLevelReduction;
  final double vendorLevel1BaseBonus;
  final double vendorLevel2BaseBonus;
  final double vendorLevel3BaseBonus;
  final double vendorPtipoteLevelBonus;
  final double legacyAttachmentInitialValue;

  double materialFurnitureBonus(int uniqueTypes) => math.min(
      furnitureMax, math.max(0, uniqueTypes) * furnitureBonusPerUniqueType);
  double homeBonus(int level) =>
      math.min(homeLevelBonusMax, math.max(0, level) * homeLevelBonusPerLevel);
  double vitalBonusFor(int value, int maxValue) {
    final percent = maxValue <= 0 ? 0 : value * 100 / maxValue;
    if (percent < vitalLowThreshold) return 0;
    if (percent < vitalHighThreshold) return vitalMidBonus;
    return vitalHighBonus;
  }

  int maxEnergyForLevel(int base, int level) =>
      base + math.max(0, level - 1) * energyMaxBonusPerLevel;
  int maxHungerForLevel(int base, int level) =>
      base + math.max(0, level - 1) * hungerMaxBonusPerLevel;
  double artisanReduction(int artisanLevel, int ptipoteLevel) {
    final base = switch (artisanLevel.clamp(0, 3)) {
      1 => artisanLevel1BaseReduction,
      2 => artisanLevel2BaseReduction,
      3 => artisanLevel3BaseReduction,
      _ => 0.0,
    };
    return (base + math.max(0, ptipoteLevel) * artisanPtipoteLevelReduction)
        .clamp(0.0, .95);
  }

  double vendorBonus(int vendorLevel, int ptipoteLevel) {
    final base = switch (vendorLevel.clamp(0, 3)) {
      1 => vendorLevel1BaseBonus,
      2 => vendorLevel2BaseBonus,
      3 => vendorLevel3BaseBonus,
      _ => 0.0,
    };
    return math.max(
        0, base + math.max(0, ptipoteLevel) * vendorPtipoteLevelBonus);
  }

  Map<String, dynamic> toDashboardMap() => <String, dynamic>{
        'v3AutoSleepThreshold': autoSleepThreshold,
        'v3AutoEatThreshold': autoEatThreshold,
        'v3EnergyMaxBonusPerLevel': energyMaxBonusPerLevel,
        'v3HungerMaxBonusPerLevel': hungerMaxBonusPerLevel,
        'v3MaterialMax': materialMax,
        'v3VitalMax': vitalMax,
        'v3AttachmentMax': attachmentMax,
        'v3FurnitureBonusPerUniqueType': furnitureBonusPerUniqueType,
        'v3FurnitureMax': furnitureMax,
        'v3OtherPtipoteBonus': otherPtipoteBonus,
        'v3HomeLevelBonusPerLevel': homeLevelBonusPerLevel,
        'v3HomeLevelBonusMax': homeLevelBonusMax,
        'v3VitalLowThreshold': vitalLowThreshold,
        'v3VitalHighThreshold': vitalHighThreshold,
        'v3VitalMidBonus': vitalMidBonus,
        'v3VitalHighBonus': vitalHighBonus,
        'v3AttachmentDecayPerHour': attachmentDecayPerHour,
        'v3HugAttachmentGain': hugAttachmentGain,
        'v3TrainingAttachmentGain': trainingAttachmentGain,
        'v3WalkAttachmentGain': walkAttachmentGain,
        'v3MovementLives': movementLives,
        'v3MovementSequenceLength': movementSequenceLength,
        'v3MovementInputWindowMs': movementInputWindowMs,
        'v3MovementBaseIntervalMs': movementBaseIntervalMs,
        'v3MovementIntervalReductionPerLevelMs':
            movementIntervalReductionPerLevelMs,
        'v3MovementXpPerLevel': movementXpPerLevel,
        'v3HideAndSeekWeight': hideAndSeekWeight,
        'v3CatchMeWeight': catchMeWeight,
        'v3ArtisanLevel1BaseReduction': artisanLevel1BaseReduction,
        'v3ArtisanLevel2BaseReduction': artisanLevel2BaseReduction,
        'v3ArtisanLevel3BaseReduction': artisanLevel3BaseReduction,
        'v3ArtisanPtipoteLevelReduction': artisanPtipoteLevelReduction,
        'v3VendorLevel1BaseBonus': vendorLevel1BaseBonus,
        'v3VendorLevel2BaseBonus': vendorLevel2BaseBonus,
        'v3VendorLevel3BaseBonus': vendorLevel3BaseBonus,
        'v3VendorPtipoteLevelBonus': vendorPtipoteLevelBonus,
        'v3LegacyAttachmentInitialValue': legacyAttachmentInitialValue,
      };

  factory PtipoteDailyLifeConfig.fromDashboardMap(Map<String, dynamic> raw) {
    const fallback = PtipoteDailyLifeConfig();
    int i(String key, int value) => (raw[key] as num?)?.round() ?? value;
    double d(String key, double value) =>
        (raw[key] as num?)?.toDouble() ?? value;
    return PtipoteDailyLifeConfig(
      autoSleepThreshold:
          i('v3AutoSleepThreshold', fallback.autoSleepThreshold),
      autoEatThreshold: i('v3AutoEatThreshold', fallback.autoEatThreshold),
      energyMaxBonusPerLevel:
          i('v3EnergyMaxBonusPerLevel', fallback.energyMaxBonusPerLevel),
      hungerMaxBonusPerLevel:
          i('v3HungerMaxBonusPerLevel', fallback.hungerMaxBonusPerLevel),
      materialMax: d('v3MaterialMax', fallback.materialMax),
      vitalMax: d('v3VitalMax', fallback.vitalMax),
      attachmentMax: d('v3AttachmentMax', fallback.attachmentMax),
      furnitureBonusPerUniqueType: d('v3FurnitureBonusPerUniqueType',
          fallback.furnitureBonusPerUniqueType),
      furnitureMax: d('v3FurnitureMax', fallback.furnitureMax),
      otherPtipoteBonus: d('v3OtherPtipoteBonus', fallback.otherPtipoteBonus),
      homeLevelBonusPerLevel:
          d('v3HomeLevelBonusPerLevel', fallback.homeLevelBonusPerLevel),
      homeLevelBonusMax: d('v3HomeLevelBonusMax', fallback.homeLevelBonusMax),
      vitalLowThreshold: i('v3VitalLowThreshold', fallback.vitalLowThreshold),
      vitalHighThreshold:
          i('v3VitalHighThreshold', fallback.vitalHighThreshold),
      vitalMidBonus: d('v3VitalMidBonus', fallback.vitalMidBonus),
      vitalHighBonus: d('v3VitalHighBonus', fallback.vitalHighBonus),
      attachmentDecayPerHour:
          d('v3AttachmentDecayPerHour', fallback.attachmentDecayPerHour),
      hugAttachmentGain: d('v3HugAttachmentGain', fallback.hugAttachmentGain),
      trainingAttachmentGain:
          d('v3TrainingAttachmentGain', fallback.trainingAttachmentGain),
      walkAttachmentGain:
          d('v3WalkAttachmentGain', fallback.walkAttachmentGain),
      movementLives: i('v3MovementLives', fallback.movementLives),
      movementSequenceLength:
          i('v3MovementSequenceLength', fallback.movementSequenceLength),
      movementInputWindowMs:
          i('v3MovementInputWindowMs', fallback.movementInputWindowMs),
      movementBaseIntervalMs:
          i('v3MovementBaseIntervalMs', fallback.movementBaseIntervalMs),
      movementIntervalReductionPerLevelMs: i(
          'v3MovementIntervalReductionPerLevelMs',
          fallback.movementIntervalReductionPerLevelMs),
      movementXpPerLevel:
          i('v3MovementXpPerLevel', fallback.movementXpPerLevel),
      hideAndSeekWeight: d('v3HideAndSeekWeight', fallback.hideAndSeekWeight),
      catchMeWeight: d('v3CatchMeWeight', fallback.catchMeWeight),
      artisanLevel1BaseReduction: d(
          'v3ArtisanLevel1BaseReduction', fallback.artisanLevel1BaseReduction),
      artisanLevel2BaseReduction: d(
          'v3ArtisanLevel2BaseReduction', fallback.artisanLevel2BaseReduction),
      artisanLevel3BaseReduction: d(
          'v3ArtisanLevel3BaseReduction', fallback.artisanLevel3BaseReduction),
      artisanPtipoteLevelReduction: d('v3ArtisanPtipoteLevelReduction',
          fallback.artisanPtipoteLevelReduction),
      vendorLevel1BaseBonus:
          d('v3VendorLevel1BaseBonus', fallback.vendorLevel1BaseBonus),
      vendorLevel2BaseBonus:
          d('v3VendorLevel2BaseBonus', fallback.vendorLevel2BaseBonus),
      vendorLevel3BaseBonus:
          d('v3VendorLevel3BaseBonus', fallback.vendorLevel3BaseBonus),
      vendorPtipoteLevelBonus:
          d('v3VendorPtipoteLevelBonus', fallback.vendorPtipoteLevelBonus),
      legacyAttachmentInitialValue: d('v3LegacyAttachmentInitialValue',
          fallback.legacyAttachmentInitialValue),
    );
  }
}

PtipoteDailyLifeConfig ptipoteDailyLifeConfig = const PtipoteDailyLifeConfig();

void applyRemotePtipoteDailyLifeConfig(Map<String, dynamic>? values) {
  ptipoteDailyLifeConfig = values == null
      ? const PtipoteDailyLifeConfig()
      : PtipoteDailyLifeConfig.fromDashboardMap(values);
}

class PtipoteHappinessBreakdown {
  const PtipoteHappinessBreakdown(
      {required this.furniture,
      required this.company,
      required this.homeLevel,
      required this.hunger,
      required this.sleep,
      required this.attachment});
  final double furniture;
  final double company;
  final double homeLevel;
  final double hunger;
  final double sleep;
  final double attachment;
  double get material => furniture + company + homeLevel;
  double get vital => hunger + sleep;
  double get total => (material + vital + attachment).clamp(0, 100).toDouble();
}
