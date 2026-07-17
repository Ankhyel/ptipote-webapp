class WorkshopConfig {
  const WorkshopConfig({
    required this.recipes,
    required this.vitalityCostPerUnit,
    required this.levelSpeedBonusPercent,
    required this.maxLevelSpeedBonusPercent,
    required this.buildingLevelSpeedBonusPercent,
    required this.maxBuildingSpeedBonusPercent,
    required this.slotsPerLevel,
  });

  final List<WorkshopRecipe> recipes;
  final int vitalityCostPerUnit;
  final double levelSpeedBonusPercent;
  final double maxLevelSpeedBonusPercent;
  final double buildingLevelSpeedBonusPercent;
  final double maxBuildingSpeedBonusPercent;
  final int slotsPerLevel;

  int slotsForLevel(int level) => level.clamp(1, 99) * slotsPerLevel;

  double buildingSpeedBonusForLevel(int level) =>
      ((level.clamp(1, 99) - 1) * buildingLevelSpeedBonusPercent)
          .clamp(0, maxBuildingSpeedBonusPercent);

  WorkshopRecipe recipe(String id) =>
      recipes.firstWhere((item) => item.id == id);
}

class WorkshopRecipe {
  const WorkshopRecipe({
    required this.id,
    required this.displayName,
    required this.category,
    required this.ingredients,
    required this.resultItem,
    required this.resultAmount,
    required this.durationMinutes,
    required this.stackLimit,
    required this.sellable,
    required this.baseSaleValue,
    required this.isEquipment,
  });

  final String id;
  final String displayName;
  final String category;
  final Map<String, int> ingredients;
  final String resultItem;
  final int resultAmount;
  final int durationMinutes;
  final int stackLimit;
  final bool sellable;
  final int baseSaleValue;
  final bool isEquipment;
}

const WorkshopConfig defaultWorkshopConfig = WorkshopConfig(
  vitalityCostPerUnit: 5,
  levelSpeedBonusPercent: 0.01,
  maxLevelSpeedBonusPercent: 0.15,
  buildingLevelSpeedBonusPercent: 0.05,
  maxBuildingSpeedBonusPercent: 0.20,
  slotsPerLevel: 1,
  recipes: <WorkshopRecipe>[
    WorkshopRecipe(
        id: 'filter',
        displayName: 'Filtre',
        category: 'Protection',
        ingredients: <String, int>{'Organique': 2, 'Minéral': 1},
        resultItem: 'Filtre',
        resultAmount: 1,
        durationMinutes: 2,
        stackLimit: 10,
        sellable: true,
        baseSaleValue: 3,
        isEquipment: false),
    WorkshopRecipe(
        id: 'filterCartridge',
        displayName: 'Cartouche de filtration',
        category: 'Consommable',
        ingredients: <String, int>{'Filtre': 1, 'Organique': 1, 'Minéral': 1},
        resultItem: 'Cartouche de filtration',
        resultAmount: 1,
        durationMinutes: 1,
        stackLimit: 10,
        sellable: true,
        baseSaleValue: 4,
        isEquipment: false),
    WorkshopRecipe(
        id: 'shadeSuit',
        displayName: 'Tenue ombragée',
        category: 'Équipement',
        ingredients: <String, int>{'Organique': 4, 'Minéral': 2},
        resultItem: 'Tenue ombragée',
        resultAmount: 1,
        durationMinutes: 5,
        stackLimit: 1,
        sellable: true,
        baseSaleValue: 8,
        isEquipment: true),
    WorkshopRecipe(
        id: 'simpleFurniture',
        displayName: 'Meuble simple',
        category: 'Habitat',
        ingredients: <String, int>{'Organique': 3, 'Minéral': 2},
        resultItem: 'Meuble simple',
        resultAmount: 1,
        durationMinutes: 3,
        stackLimit: 1,
        sellable: true,
        baseSaleValue: 5,
        isEquipment: true),
    WorkshopRecipe(
        id: 'termiteVentilation',
        displayName: 'Ventilation Termite',
        category: 'Installation',
        ingredients: <String, int>{'Organique': 6, 'Minéral': 4},
        resultItem: 'Ventilation Termite',
        resultAmount: 1,
        durationMinutes: 8,
        stackLimit: 1,
        sellable: true,
        baseSaleValue: 12,
        isEquipment: true),
    WorkshopRecipe(
        id: 'solarLight',
        displayName: 'Lumière solaire',
        category: 'Installation',
        ingredients: <String, int>{'Organique': 5, 'Minéral': 5},
        resultItem: 'Lumière solaire',
        resultAmount: 1,
        durationMinutes: 8,
        stackLimit: 1,
        sellable: true,
        baseSaleValue: 12,
        isEquipment: true),
  ],
);

WorkshopConfig workshopConfig = defaultWorkshopConfig;
