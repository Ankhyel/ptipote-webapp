import 'dart:math' as math;

class MarketConfig {
  const MarketConfig({
    required this.constructionCost,
    required this.requiredCampHeartLevel,
    required this.requiredPopulation,
    required this.saleSlotsPerLevel,
    required this.baseSaleIntervalMinutes,
    required this.valuePerBioBattery,
    required this.ptipoteIntervalMultiplier,
    required this.vitalityCostPerTick,
    required this.vitalityTickMinutes,
    required this.requestChance,
    required this.maxActiveRequests,
    required this.requestMinReturnMinutes,
    required this.requestMaxReturnMinutes,
    required this.saleValues,
    required this.saleIntervalReductionPerLevel,
    required this.maxActiveRequestsBonusPerLevel,
    required this.saleIntervalPopulationImpactPercent,
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
    required this.shopSlots,
    required this.maxConstructibleShops,
    required this.firstShopFree,
    required this.residentsPerHourlyRequest,
    required this.requestJitterMinPercent,
    required this.requestJitterMaxPercent,
    required this.distributorResponseDelayMinutes,
  });

  final Map<String, int> constructionCost;
  final int requiredCampHeartLevel;
  final int requiredPopulation;
  final int saleSlotsPerLevel;
  final int baseSaleIntervalMinutes;
  final int valuePerBioBattery;
  final double ptipoteIntervalMultiplier;
  final int vitalityCostPerTick;
  final int vitalityTickMinutes;
  final double requestChance;
  final int maxActiveRequests;
  final int requestMinReturnMinutes;
  final int requestMaxReturnMinutes;
  final Map<String, int> saleValues;
  final double saleIntervalReductionPerLevel;
  final int maxActiveRequestsBonusPerLevel;
  final int saleIntervalPopulationImpactPercent;
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
  final int shopSlots;
  final int maxConstructibleShops;
  final bool firstShopFree;
  final int residentsPerHourlyRequest;
  final int requestJitterMinPercent;
  final int requestJitterMaxPercent;
  final int distributorResponseDelayMinutes;

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

  double saleIntervalMultiplierForLevel(int level) =>
      (1 - (level.clamp(1, 99) - 1) * saleIntervalReductionPerLevel).clamp(
        0.5,
        1.0,
      );

  int maxRequestsForLevel(int level) =>
      maxActiveRequests +
      (level.clamp(1, 99) - 1) * maxActiveRequestsBonusPerLevel;

  int licenseSlotsForLevel(int level) => level >= 4 ? 2 : level >= 2 ? 1 : 0;

  Duration residentRequestInterval(int population, math.Random random) {
    final requestsPerHour = math.max(1, population ~/ math.max(1, residentsPerHourlyRequest));
    final baseMinutes = 60 / requestsPerHour;
    final min = requestJitterMinPercent.clamp(0, 100) / 100;
    final max = requestJitterMaxPercent.clamp(requestJitterMinPercent, 100) / 100;
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
  baseSaleIntervalMinutes: 10,
  valuePerBioBattery: 5,
  ptipoteIntervalMultiplier: 0.9,
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
  saleIntervalReductionPerLevel: 0.10,
  maxActiveRequestsBonusPerLevel: 1,
  saleIntervalPopulationImpactPercent: 100,
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
  shopSlots: 6,
  maxConstructibleShops: 2,
  firstShopFree: true,
  residentsPerHourlyRequest: 3,
  requestJitterMinPercent: 10,
  requestJitterMaxPercent: 30,
  distributorResponseDelayMinutes: 1,
);

MarketConfig marketConfig = defaultMarketConfig;
