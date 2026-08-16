class FablabRoomLevelConfig {
  const FablabRoomLevelConfig({
    required this.workers,
    required this.manualSlots,
    required this.quantities,
    required this.recipeTier,
    required this.queueCapacity,
    required this.marketRestock,
    this.categories = const <String>[],
  });

  final int workers;
  final int manualSlots;
  final List<int> quantities;
  final int recipeTier;
  final int queueCapacity;
  final bool marketRestock;
  final List<String> categories;
}

class FablabConfig {
  const FablabConfig({
    required this.constructionCostLevel1Organic,
    required this.constructionCostLevel1Mineral,
    required this.baseGlobalStockCapacity,
    required this.stockCapacityBonusPerFablabLevel,
    required this.fablabStorageByLevel,
    required this.houseStorageByLevel,
    required this.recyclerInputByLevel,
    required this.recyclerVatOneCapacityByLevel,
    required this.recyclerVatTwoCapacityByLevel,
    required this.recyclerSpecializedMinimumOutOfTen,
    required this.kitchenRoomLevels,
    required this.workshopRoomLevels,
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
  final Map<int, int> fablabStorageByLevel;
  final Map<int, int> houseStorageByLevel;
  final Map<int, int> recyclerInputByLevel;
  final Map<int, int> recyclerVatOneCapacityByLevel;
  final Map<int, int> recyclerVatTwoCapacityByLevel;
  final int recyclerSpecializedMinimumOutOfTen;
  final Map<int, FablabRoomLevelConfig> kitchenRoomLevels;
  final Map<int, FablabRoomLevelConfig> workshopRoomLevels;
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
  fablabStorageByLevel: <int, int>{1: 100, 2: 200, 3: 300, 4: 350},
  houseStorageByLevel: <int, int>{1: 100, 2: 125, 3: 150, 4: 200},
  recyclerInputByLevel: <int, int>{1: 18, 2: 16, 3: 14, 4: 12},
  recyclerVatOneCapacityByLevel: <int, int>{1: 20, 2: 40, 3: 40, 4: 60},
  recyclerVatTwoCapacityByLevel: <int, int>{3: 20, 4: 40},
  recyclerSpecializedMinimumOutOfTen: 6,
  kitchenRoomLevels: <int, FablabRoomLevelConfig>{
    1: FablabRoomLevelConfig(
        workers: 1,
        manualSlots: 1,
        quantities: <int>[1, 5, 10],
        recipeTier: 1,
        queueCapacity: 0,
        marketRestock: false),
    2: FablabRoomLevelConfig(
        workers: 2,
        manualSlots: 1,
        quantities: <int>[1, 5, 10, 25],
        recipeTier: 2,
        queueCapacity: 1,
        marketRestock: false),
    3: FablabRoomLevelConfig(
        workers: 3,
        manualSlots: 1,
        quantities: <int>[1, 5, 10, 25, 50],
        recipeTier: 3,
        queueCapacity: 2,
        marketRestock: false),
    4: FablabRoomLevelConfig(
        workers: 4,
        manualSlots: 1,
        quantities: <int>[1, 5, 10, 25, 50],
        recipeTier: 4,
        queueCapacity: 3,
        marketRestock: true),
  },
  workshopRoomLevels: <int, FablabRoomLevelConfig>{
    1: FablabRoomLevelConfig(
        workers: 1,
        manualSlots: 1,
        quantities: <int>[1, 5, 10],
        recipeTier: 1,
        queueCapacity: 0,
        marketRestock: false,
        categories: <String>['filters', 'consumables']),
    2: FablabRoomLevelConfig(
        workers: 2,
        manualSlots: 1,
        quantities: <int>[1, 5, 10, 25],
        recipeTier: 2,
        queueCapacity: 1,
        marketRestock: false,
        categories: <String>[
          'filters',
          'consumables',
          'structures',
          'outfits'
        ]),
    3: FablabRoomLevelConfig(
        workers: 3,
        manualSlots: 1,
        quantities: <int>[1, 5, 10, 25, 50],
        recipeTier: 3,
        queueCapacity: 2,
        marketRestock: false,
        categories: <String>[
          'filters',
          'consumables',
          'structures',
          'outfits',
          'furniture',
          'armatures',
          'modules'
        ]),
    4: FablabRoomLevelConfig(
        workers: 4,
        manualSlots: 1,
        quantities: <int>[1, 5, 10, 25, 50],
        recipeTier: 4,
        queueCapacity: 3,
        marketRestock: true,
        categories: <String>[
          'filters',
          'consumables',
          'structures',
          'outfits',
          'furniture',
          'armatures',
          'modules',
          'mycelialRecipes'
        ]),
  },
  fablabMaxLevel: 4,
  cuisineMaxLevel: 4,
  atelierMaxLevel: 4,
  cuisineUnlockLevel: 1,
  atelierUnlockCampHeartLevel: 1,
  recyclerUnlockCampHeartLevel: 2,
  simpleMealOrganicCost: 2,
  simpleMealOutputAmount: 1,
);

FablabConfig fablabConfig = defaultFablabConfig;
