import 'dart:math' as math;

class MarketConfig {
  const MarketConfig({
    required this.constructionCost,
    required this.requiredCampHeartLevel,
    required this.requiredPopulation,
    required this.saleSlotsPerLevel,
    required this.valuePerBioBattery,
    required this.vitalityCostPerTick,
    required this.vitalityTickMinutes,
    required this.requestChance,
    required this.maxActiveRequests,
    required this.requestMinReturnMinutes,
    required this.requestMaxReturnMinutes,
    required this.saleValues,
    required this.maxActiveRequestsBonusPerLevel,
    required this.maximumLevel,
    required this.manualSlotsByLevel,
    required this.allowDuplicateStacks,
    required this.stackQuantityLimit,
    required this.distributorConstructionCost,
    required this.distributorConstructionMinutes,
    required this.distributorEnergyCapacity,
    required this.distributorEnergyPerBioBattery,
    required this.distributorDailyEnergyByLevel,
    required this.distributorSlotsByLevel,
    required this.distributorBreakDenominatorByLevel,
    required this.distributorRepairMinutesByLevel,
    required this.distributorRepairCost,
    required this.confidenceSuccessGain,
    required this.confidenceFailurePenalty,
    required this.confidenceMaxPaymentBonusPercent,
    required this.maxActiveLicenses,
    required this.licenseCostBioBatteries,
    required this.licenseChangeCostBioBatteries,
    required this.licenseDirectedRatioPercent,
    required this.specializedShopSlotsByMarketLevel,
    required this.firstShopFree,
    required this.residentsPerHourlyRequest,
    required this.requestJitterMinPercent,
    required this.requestJitterMaxPercent,
    required this.distributorResponseDelayMinutes,
    required this.weatherRequestRatioPercent,
    required this.weatherRequestPopulationDivisor,
    required this.weatherRequestItems,
    required this.requestBasePerHourByLevel,
    required this.requestMinimumSpacingMinutes,
    required this.economicActivityWellbeingMaxPercent,
    required this.economicActivityHeartLevelPercent,
    required this.economicActivityHeartLevelCapPercent,
    required this.economicActivityMarketLevelPercent,
    required this.economicActivityMarketLevelCapPercent,
    required this.economicActivityWeatherPercent,
    required this.requestCategoryWeights,
    required this.requestPriceBioPiles,
    required this.specializedShopGainBonusPercent,
    required this.baseStorePricePenaltyPercent,
  });

  final Map<String, int> constructionCost;
  final int requiredCampHeartLevel;
  final int requiredPopulation;
  final int saleSlotsPerLevel;
  final int valuePerBioBattery;
  final int vitalityCostPerTick;
  final int vitalityTickMinutes;
  final double requestChance;
  final int maxActiveRequests;
  final int requestMinReturnMinutes;
  final int requestMaxReturnMinutes;
  final Map<String, int> saleValues;
  final int maxActiveRequestsBonusPerLevel;
  final int maximumLevel;
  final Map<int, int> manualSlotsByLevel;
  final bool allowDuplicateStacks;
  final int stackQuantityLimit;
  final Map<String, int> distributorConstructionCost;
  final int distributorConstructionMinutes;
  final int distributorEnergyCapacity;
  final int distributorEnergyPerBioBattery;
  final Map<int, int> distributorDailyEnergyByLevel;
  final Map<int, int> distributorSlotsByLevel;
  final Map<int, int> distributorBreakDenominatorByLevel;
  final Map<int, int> distributorRepairMinutesByLevel;
  final Map<String, int> distributorRepairCost;
  final int confidenceSuccessGain;
  final int confidenceFailurePenalty;
  final double confidenceMaxPaymentBonusPercent;
  final int maxActiveLicenses;
  final int licenseCostBioBatteries;
  final int licenseChangeCostBioBatteries;
  final int licenseDirectedRatioPercent;
  final Map<int, int> specializedShopSlotsByMarketLevel;
  final bool firstShopFree;
  final int residentsPerHourlyRequest;
  final int requestJitterMinPercent;
  final int requestJitterMaxPercent;
  final int distributorResponseDelayMinutes;
  final int weatherRequestRatioPercent;
  final int weatherRequestPopulationDivisor;
  final Map<String, List<String>> weatherRequestItems;
  final Map<int, int> requestBasePerHourByLevel;
  final int requestMinimumSpacingMinutes;
  final int economicActivityWellbeingMaxPercent;
  final int economicActivityHeartLevelPercent;
  final int economicActivityHeartLevelCapPercent;
  final int economicActivityMarketLevelPercent;
  final int economicActivityMarketLevelCapPercent;
  final Map<String, int> economicActivityWeatherPercent;
  final Map<String, int> requestCategoryWeights;
  final Map<String, int> requestPriceBioPiles;
  final int specializedShopGainBonusPercent;
  final int baseStorePricePenaltyPercent;

  int slotsForLevel(int level) =>
      manualSlotsByLevel[level.clamp(0, maximumLevel)] ??
      level.clamp(0, 99) * saleSlotsPerLevel;

  int distributorSlotsForLevel(int level) =>
      distributorSlotsByLevel[level.clamp(1, 3)] ?? 0;

  int distributorEnergyPerDayForLevel(int level) =>
      distributorDailyEnergyByLevel[level.clamp(1, 3)] ?? 0;

  int distributorBreakDenominatorForLevel(int level) =>
      distributorBreakDenominatorByLevel[level.clamp(1, 3)] ?? 1;

  int distributorRepairMinutesForLevel(int level) =>
      distributorRepairMinutesByLevel[level.clamp(1, 3)] ?? 30;

  int maxRequestsForLevel(int level) =>
      maxActiveRequests +
      (level.clamp(1, 99) - 1) * maxActiveRequestsBonusPerLevel;

  int licenseSlotsForLevel(int level) => level >= 4
      ? 2
      : level >= 2
          ? 1
          : 0;

  int specializedShopSlotsForLevel(int level) =>
      specializedShopSlotsByMarketLevel[level.clamp(1, maximumLevel)] ?? 0;

  int requestBasePerHourForLevel(int level) =>
      requestBasePerHourByLevel[level.clamp(1, maximumLevel)] ?? 0;

  Duration residentRequestInterval(int population, math.Random random) {
    final requestsPerHour =
        math.max(1, population ~/ math.max(1, residentsPerHourlyRequest));
    final baseMinutes = 60 / requestsPerHour;
    final min = requestJitterMinPercent.clamp(0, 100) / 100;
    final max =
        requestJitterMaxPercent.clamp(requestJitterMinPercent, 100) / 100;
    final amplitude = min + random.nextDouble() * (max - min);
    // Alternate around the target interval instead of only delaying every
    // request: the population target therefore remains meaningful over time.
    final signedJitter = random.nextBool() ? amplitude : -amplitude;
    return Duration(
      minutes: math.max(1, (baseMinutes * (1 + signedJitter)).round()),
    );
  }
}

const MarketConfig defaultMarketConfig = MarketConfig(
  constructionCost: <String, int>{'Organique': 6, 'Minéral': 6},
  requiredCampHeartLevel: 1,
  requiredPopulation: 5,
  saleSlotsPerLevel: 3,
  valuePerBioBattery: 5,
  vitalityCostPerTick: 5,
  vitalityTickMinutes: 20,
  requestChance: 0.35,
  maxActiveRequests: 3,
  requestMinReturnMinutes: 10,
  requestMaxReturnMinutes: 30,
  saleValues: <String, int>{
    'Organique': 10,
    'Minéral': 10,
    'Repas simple': 2,
    'Filtre': 1,
    'Cartouche de filtration': 2,
    'Tenue ombragée': 2,
    'Meuble simple': 2,
    'Ventilation Termite': 3,
    'Lumière solaire': 3,
  },
  maxActiveRequestsBonusPerLevel: 1,
  maximumLevel: 4,
  manualSlotsByLevel: <int, int>{1: 3, 2: 6, 3: 6, 4: 6},
  allowDuplicateStacks: true,
  stackQuantityLimit: 10,
  distributorConstructionCost: <String, int>{'Organique': 20, 'Minéral': 10},
  distributorConstructionMinutes: 1,
  distributorEnergyCapacity: 100,
  distributorEnergyPerBioBattery: 10,
  distributorDailyEnergyByLevel: <int, int>{1: 10, 2: 8, 3: 6},
  distributorSlotsByLevel: <int, int>{1: 2, 2: 3, 3: 4},
  distributorBreakDenominatorByLevel: <int, int>{1: 6, 2: 12, 3: 24},
  distributorRepairMinutesByLevel: <int, int>{1: 30, 2: 20, 3: 10},
  distributorRepairCost: <String, int>{'Organique': 1, 'Minéral': 1},
  confidenceSuccessGain: 5,
  confidenceFailurePenalty: 2,
  confidenceMaxPaymentBonusPercent: 30,
  maxActiveLicenses: 2,
  licenseCostBioBatteries: 30,
  licenseChangeCostBioBatteries: 10,
  licenseDirectedRatioPercent: 80,
  specializedShopSlotsByMarketLevel: <int, int>{1: 1, 2: 3, 3: 5, 4: 7},
  firstShopFree: true,
  residentsPerHourlyRequest: 3,
  requestJitterMinPercent: 10,
  requestJitterMaxPercent: 30,
  distributorResponseDelayMinutes: 1,
  weatherRequestRatioPercent: 80,
  weatherRequestPopulationDivisor: 3,
  weatherRequestItems: <String, List<String>>{
    'heatWave': <String>['Tenue ombragée', 'Repas simple'],
    'heavyRain': <String>['Ventilation Termite'],
    'toxicCloud': <String>['Cartouche de filtration', 'Filtre'],
  },
  requestBasePerHourByLevel: <int, int>{1: 2, 2: 4, 3: 6, 4: 10},
  requestMinimumSpacingMinutes: 2,
  economicActivityWellbeingMaxPercent: 30,
  economicActivityHeartLevelPercent: 10,
  economicActivityHeartLevelCapPercent: 40,
  economicActivityMarketLevelPercent: 5,
  economicActivityMarketLevelCapPercent: 20,
  economicActivityWeatherPercent: <String, int>{
    'calm': 10,
    'moderate': 5,
    'strong': 3,
    'severe': 0,
  },
  requestCategoryWeights: <String, int>{
    'food': 60,
    'materials': 20,
    'clothing': 15,
    'furniture': 5,
  },
  requestPriceBioPiles: <String, int>{
    'Boisson tonique': 2,
    'Repas simple': 5,
    'Organique': 10,
    'Minéral': 10,
    'Tenue ombragée': 20,
    'Filtre': 7,
    'Cartouche de filtration': 13,
    'Meuble simple': 30,
    'Ventilation Termite': 50,
    'Lumière solaire': 50,
  },
  specializedShopGainBonusPercent: 30,
  baseStorePricePenaltyPercent: 50,
);

MarketConfig marketConfig = defaultMarketConfig;
