enum CraftSection { cuisine, atelier }

class CraftConfig {
  const CraftConfig({required this.recipes});

  final List<CraftRecipe> recipes;

  CraftRecipe get simpleMealRecipe => recipes.firstWhere(
        (recipe) => recipe.id == 'simpleMeal',
        orElse: () => defaultCraftConfig.recipes.first,
      );

  CraftRecipe get vitalityDrinkRecipe => recipes.firstWhere(
        (recipe) => recipe.id == 'vitalityDrink',
        orElse: () => defaultCraftConfig.recipes[1],
      );
}

class CraftRecipe {
  const CraftRecipe({
    required this.id,
    required this.displayName,
    required this.craftSection,
    required this.ingredients,
    required this.contextIngredients,
    required this.cuisineLevel,
    required this.atelierLevel,
    required this.kernelTrustLevel,
    required this.breederLevel,
    required this.builderLevel,
    required this.restorerLevel,
    required this.resultItem,
    required this.resultAmount,
    required this.isConsumable,
    required this.hungerRestore,
    required this.vitalityRestore,
    this.durationMinutes = 1,
    this.isEquipment = false,
    this.energyCost = 0,
    this.stackLimit = 1,
  });

  final String id;
  final String displayName;
  final CraftSection craftSection;
  final Map<String, int> ingredients;
  final Map<String, int> contextIngredients;
  final int cuisineLevel;
  final int atelierLevel;
  final int kernelTrustLevel;
  final int breederLevel;
  final int builderLevel;
  final int restorerLevel;
  final String resultItem;
  final int resultAmount;
  final bool isConsumable;
  final int hungerRestore;
  final int vitalityRestore;
  final int durationMinutes;
  final bool isEquipment;
  final int energyCost;
  final int stackLimit;
}

const defaultCraftConfig = CraftConfig(
  recipes: <CraftRecipe>[
    CraftRecipe(
      id: 'simpleMeal',
      displayName: 'Repas simple',
      craftSection: CraftSection.cuisine,
      ingredients: <String, int>{'Organique': 2},
      contextIngredients: <String, int>{'Eau': 1},
      cuisineLevel: 1,
      atelierLevel: 0,
      kernelTrustLevel: 1,
      breederLevel: 1,
      builderLevel: 1,
      restorerLevel: 1,
      resultItem: 'Repas simple',
      resultAmount: 1,
      isConsumable: true,
      hungerRestore: 35,
      vitalityRestore: 5,
      durationMinutes: 2,
      stackLimit: 10,
    ),
    CraftRecipe(
      id: 'vitalityDrink',
      displayName: 'Boisson tonique',
      craftSection: CraftSection.cuisine,
      ingredients: <String, int>{'Organique': 3},
      contextIngredients: <String, int>{'Eau': 4},
      cuisineLevel: 2,
      atelierLevel: 0,
      kernelTrustLevel: 1,
      breederLevel: 1,
      builderLevel: 1,
      restorerLevel: 1,
      resultItem: 'Boisson tonique',
      resultAmount: 2,
      isConsumable: true,
      hungerRestore: 5,
      vitalityRestore: 15,
      durationMinutes: 3,
      stackLimit: 10,
    ),
    CraftRecipe(
      id: 'filter',
      displayName: 'Filtre',
      craftSection: CraftSection.atelier,
      ingredients: <String, int>{'Organique': 2, 'Minéral': 1},
      contextIngredients: <String, int>{},
      cuisineLevel: 0,
      atelierLevel: 1,
      kernelTrustLevel: 2,
      breederLevel: 1,
      builderLevel: 1,
      restorerLevel: 1,
      resultItem: 'Filtre',
      resultAmount: 1,
      isConsumable: false,
      hungerRestore: 0,
      vitalityRestore: 0,
      durationMinutes: 2,
      stackLimit: 10,
    ),
    CraftRecipe(
      id: 'filterCartridge',
      displayName: 'Cartouche de filtration',
      craftSection: CraftSection.atelier,
      ingredients: <String, int>{'Filtre': 1, 'Organique': 1, 'Minéral': 1},
      contextIngredients: <String, int>{},
      cuisineLevel: 0,
      atelierLevel: 1,
      kernelTrustLevel: 2,
      breederLevel: 1,
      builderLevel: 1,
      restorerLevel: 2,
      resultItem: 'Cartouche de filtration',
      resultAmount: 1,
      isConsumable: false,
      hungerRestore: 0,
      vitalityRestore: 0,
      durationMinutes: 1,
      stackLimit: 10,
    ),
    CraftRecipe(
      id: 'shadeSuit',
      displayName: 'Tenue ombragée',
      craftSection: CraftSection.atelier,
      ingredients: <String, int>{'Organique': 4, 'Minéral': 2},
      contextIngredients: <String, int>{},
      cuisineLevel: 0,
      atelierLevel: 1,
      kernelTrustLevel: 2,
      breederLevel: 1,
      builderLevel: 2,
      restorerLevel: 1,
      resultItem: 'Tenue ombragée',
      resultAmount: 1,
      isConsumable: false,
      hungerRestore: 0,
      vitalityRestore: 0,
      durationMinutes: 5,
      isEquipment: true,
      stackLimit: 1,
    ),
    CraftRecipe(
      id: 'simpleFurniture',
      displayName: 'Meuble simple',
      craftSection: CraftSection.atelier,
      ingredients: <String, int>{'Organique': 3, 'Minéral': 2},
      contextIngredients: <String, int>{},
      cuisineLevel: 0,
      atelierLevel: 1,
      kernelTrustLevel: 1,
      breederLevel: 1,
      builderLevel: 1,
      restorerLevel: 1,
      resultItem: 'Meuble simple',
      resultAmount: 1,
      isConsumable: false,
      hungerRestore: 0,
      vitalityRestore: 0,
      durationMinutes: 3,
      isEquipment: true,
      stackLimit: 1,
    ),
    CraftRecipe(
      id: 'termiteVentilation',
      displayName: 'Ventilation Termite',
      craftSection: CraftSection.atelier,
      ingredients: <String, int>{'Organique': 6, 'Minéral': 4},
      contextIngredients: <String, int>{},
      cuisineLevel: 0,
      atelierLevel: 1,
      kernelTrustLevel: 3,
      breederLevel: 1,
      builderLevel: 2,
      restorerLevel: 1,
      resultItem: 'Ventilation Termite',
      resultAmount: 1,
      isConsumable: false,
      hungerRestore: 0,
      vitalityRestore: 0,
      durationMinutes: 8,
      isEquipment: true,
      stackLimit: 1,
    ),
    CraftRecipe(
      id: 'solarLight',
      displayName: 'Lumière solaire',
      craftSection: CraftSection.atelier,
      ingredients: <String, int>{'Organique': 5, 'Minéral': 5},
      contextIngredients: <String, int>{},
      cuisineLevel: 0,
      atelierLevel: 1,
      kernelTrustLevel: 3,
      breederLevel: 1,
      builderLevel: 2,
      restorerLevel: 1,
      resultItem: 'Lumière solaire',
      resultAmount: 1,
      isConsumable: false,
      hungerRestore: 0,
      vitalityRestore: 0,
      durationMinutes: 8,
      isEquipment: true,
      stackLimit: 1,
    ),
  ],
);

CraftConfig craftConfig = defaultCraftConfig;
