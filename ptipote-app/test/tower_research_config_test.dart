import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/lisiere_forage_config.dart';
import 'package:ptipote_app/features/game/tower_operations_config.dart';

void main() {
  group('Tour de recherche', () {
    final research = defaultTowerOperationsConfig.research;

    test('applique les chances de Cellules demandées par mission', () {
      expect(research.cellChanceFor(ForageMissionType.harvest, 1), 50);
      expect(research.cellChanceFor(ForageMissionType.harvest, 2), 25);
      expect(research.cellChanceFor(ForageMissionType.harvest, 3), 0);

      expect(research.cellChanceFor(ForageMissionType.research, 1), 100);
      expect(research.cellChanceFor(ForageMissionType.research, 2), 75);
      expect(research.cellChanceFor(ForageMissionType.research, 3), 50);
      expect(research.cellChanceFor(ForageMissionType.research, 4), 25);
      expect(research.cellChanceFor(ForageMissionType.research, 5), 0);
    });

    test('expose les valeurs, paliers et cadence de connaissance validés', () {
      expect(research.harvestValueSevenEightChance, 25);
      expect(research.harvestValueNineChance, 0);
      expect(research.researchValueSevenEightChance, 75);
      expect(research.researchValueNineChance, 50);
      expect(research.progressPerHour, 5);
      expect(research.cellChancePerHour, 10);
      expect(research.progressDecayPerDay, 2);
      expect(research.cellChanceRevealPercent, 25);
      expect(research.valueChanceRevealPercent, 50);
      expect(research.familyRevealPercent, 65);
      expect(research.fullRevealPercent, 85);
    });
  });
}
