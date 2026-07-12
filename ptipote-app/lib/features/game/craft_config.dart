class CraftConfig {
  const CraftConfig({required this.recipes});

  final List<CraftRecipe> recipes;

  CraftRecipe get simpleMealRecipe {
    return recipes.firstWhere(
      (recipe) => recipe.id == 'simpleMeal',
      orElse: () => recipes.first,
    );
  }
}

class CraftRecipe {
  const CraftRecipe({
    required this.id,
    required this.displayName,
    required this.ingredients,
    required this.resultItem,
    required this.resultAmount,
    required this.isConsumable,
    required this.hungerRestore,
    required this.vitalityRestore,
  });

  final String id;
  final String displayName;
  final Map<String, int> ingredients;
  final String resultItem;
  final int resultAmount;
  final bool isConsumable;
  final int hungerRestore;
  final int vitalityRestore;
}

const craftConfig = CraftConfig(
  recipes: <CraftRecipe>[
    CraftRecipe(
      id: 'simpleMeal',
      displayName: 'Repas simple',
      ingredients: <String, int>{'Organique': 2},
      resultItem: 'Repas simple',
      resultAmount: 1,
      isConsumable: true,
      hungerRestore: 20,
      vitalityRestore: 15,
    ),
  ],
);
