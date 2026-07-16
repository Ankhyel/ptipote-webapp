class CraftConfig {
  const CraftConfig({required this.recipes});

  final List<CraftRecipe> recipes;

  CraftRecipe get simpleMealRecipe {
    return recipes.firstWhere(
      (recipe) => recipe.id == 'simpleMeal',
      orElse: () => recipes.first,
    );
  }

  CraftRecipe get vitalityDrinkRecipe {
    return recipes.firstWhere(
      (recipe) => recipe.id == 'vitalityDrink',
      orElse: () => recipes.first,
    );
  }
}

enum FoodType { meal, drink }

class CraftRecipe {
  const CraftRecipe({
    required this.id,
    required this.displayName,
    required this.ingredients,
    required this.contextIngredients,
    required this.cuisineLevel,
    required this.resultItem,
    required this.resultAmount,
    required this.isConsumable,
    required this.foodType,
    required this.hungerRestore,
    required this.vitalityRestore,
    this.isEquipment = false,
    this.energyCost = 0,
  });

  final String id;
  final String displayName;
  final Map<String, int> ingredients;
  final Map<String, int> contextIngredients;
  final int cuisineLevel;
  final String resultItem;
  final int resultAmount;
  final bool isConsumable;
  final FoodType foodType;
  final int hungerRestore;
  final int vitalityRestore;
  final bool isEquipment;
  final int energyCost;
}

const craftConfig = CraftConfig(
  recipes: <CraftRecipe>[
    CraftRecipe(
      id: 'simpleMeal',
      displayName: 'Repas simple',
      ingredients: <String, int>{'Organique': 2},
      contextIngredients: <String, int>{'Eau': 1},
      cuisineLevel: 1,
      resultItem: 'Repas simple',
      resultAmount: 1,
      isConsumable: true,
      foodType: FoodType.meal,
      hungerRestore: 35,
      vitalityRestore: 5,
    ),
    CraftRecipe(
      id: 'vitalityDrink',
      displayName: 'Boisson tonique',
      ingredients: <String, int>{'Organique': 3},
      contextIngredients: <String, int>{'Eau': 4},
      cuisineLevel: 2,
      resultItem: 'Boisson tonique',
      resultAmount: 2,
      isConsumable: true,
      foodType: FoodType.drink,
      hungerRestore: 5,
      vitalityRestore: 15,
    ),
  ],
);
