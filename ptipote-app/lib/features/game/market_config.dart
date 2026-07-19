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

  int slotsForLevel(int level) => level.clamp(0, 99) * saleSlotsPerLevel;

  double saleIntervalMultiplierForLevel(int level) =>
      (1 - (level.clamp(1, 99) - 1) * saleIntervalReductionPerLevel).clamp(
        0.5,
        1.0,
      );

  int maxRequestsForLevel(int level) =>
      maxActiveRequests +
      (level.clamp(1, 99) - 1) * maxActiveRequestsBonusPerLevel;
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
);

MarketConfig marketConfig = defaultMarketConfig;
