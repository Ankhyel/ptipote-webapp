import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/tower_operations_config.dart';
import 'package:ptipote_app/features/game/waste_recycler_config.dart';

void main() {
  group('building energy conversion configuration', () {
    test('keeps a configurable conversion for every supported level', () {
      expect(defaultWasteRecyclerConfig.energyUnitsForBuildingLevel(1), 100);
      expect(defaultWasteRecyclerConfig.energyUnitsForBuildingLevel(6), 100);
      expect(
        defaultWasteRecyclerConfig.energyUnitsForBuildingLevel(99),
        defaultWasteRecyclerConfig.energyUnitsForBuildingLevel(6),
      );
    });
  });

  group('building repair configuration', () {
    test('uses a common per-level cost table with batteries, piles and kits',
        () {
      final levelOne =
          defaultTowerOperationsConfig.buildingViability.repairCostsForLevel(1);
      final levelThree =
          defaultTowerOperationsConfig.buildingViability.repairCostsForLevel(3);

      expect(levelOne['Organique'], 1);
      expect(levelOne['Minéral'], 3);
      expect(levelOne['Bio-batteries'], 0);
      expect(levelOne['Bio-piles'], 10);
      expect(levelOne['Kit de réparation domestique'], 0);
      expect(levelThree['Organique'], 3);
      expect(levelThree['Minéral'], 9);
    });
  });
}
