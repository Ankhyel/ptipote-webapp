import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/kernel_progress_config.dart';

void main() {
  test('le Filtre se découvre à ses prérequis Kernel', () {
    final filter = defaultKernelProgressConfig.plans.singleWhere(
      (plan) => plan.id == 'filter',
    );

    expect(filter.workshopRecipeId, 'filter');
    expect(filter.discoverWhenRequirementsMet, isTrue);
  });

  test('chaque recette Atelier versionnée a son Plan Kernel', () {
    final recipeIds = <String>{
      'simpleFurniture',
      'filter',
      'filterCartridge',
      'shadeSuit',
      'termiteVentilation',
      'chloroCanals',
      'filterInstallation',
      'solarLight',
    };
    final linkedRecipeIds = defaultKernelProgressConfig.plans
        .map((plan) => plan.workshopRecipeId)
        .whereType<String>()
        .toSet();

    expect(linkedRecipeIds, containsAll(recipeIds));
  });
}
