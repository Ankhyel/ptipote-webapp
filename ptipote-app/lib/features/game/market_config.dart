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

  int slotsForLevel(int level) => level.clamp(0, 99) * saleSlotsPerLevel;
}

const marketConfig = MarketConfig(
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
    'Organique': 1,
    'Minéral': 1,
    'Repas simple': 2,
    'Filtre': 3,
    'Cartouche de filtration': 4,
    'Tenue ombragée': 8,
    'Meuble simple': 5,
    'Ventilation Termite': 12,
    'Lumière solaire': 12,
  },
);
