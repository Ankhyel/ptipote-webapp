class FablabConfig {
  const FablabConfig({
    required this.constructionCostLevel1Organic,
    required this.constructionCostLevel1Mineral,
    required this.baseGlobalStockCapacity,
    required this.stockCapacityBonusPerFablabLevel,
    required this.fablabMaxLevel,
    required this.cuisineMaxLevel,
    required this.atelierMaxLevel,
    required this.cuisineUnlockLevel,
    required this.atelierUnlockCampHeartLevel,
    required this.recyclerUnlockCampHeartLevel,
    required this.simpleMealOrganicCost,
    required this.simpleMealOutputAmount,
  });

  final int constructionCostLevel1Organic;
  final int constructionCostLevel1Mineral;
  final int baseGlobalStockCapacity;
  final int stockCapacityBonusPerFablabLevel;
  final int fablabMaxLevel;
  final int cuisineMaxLevel;
  final int atelierMaxLevel;
  final int cuisineUnlockLevel;
  final int atelierUnlockCampHeartLevel;
  final int recyclerUnlockCampHeartLevel;
  final int simpleMealOrganicCost;
  final int simpleMealOutputAmount;

  Map<String, int> get constructionCostLevel1 {
    return <String, int>{
      'Organique': constructionCostLevel1Organic,
      'Minéral': constructionCostLevel1Mineral,
    };
  }
}

const FablabConfig defaultFablabConfig = FablabConfig(
  constructionCostLevel1Organic: 8,
  constructionCostLevel1Mineral: 4,
  baseGlobalStockCapacity: 100,
  stockCapacityBonusPerFablabLevel: 100,
  fablabMaxLevel: 5,
  cuisineMaxLevel: 5,
  atelierMaxLevel: 5,
  cuisineUnlockLevel: 1,
  atelierUnlockCampHeartLevel: 1,
  recyclerUnlockCampHeartLevel: 2,
  simpleMealOrganicCost: 2,
  simpleMealOutputAmount: 1,
);

FablabConfig fablabConfig = defaultFablabConfig;
