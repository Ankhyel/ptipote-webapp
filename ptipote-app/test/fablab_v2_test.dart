import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/fablab_config.dart';
import 'package:ptipote_app/features/game/fablab_v2.dart';

void main() {
  group('FabLab V2 configuration', () {
    test('uses the validated shared-storage tables', () {
      expect(defaultFablabConfig.fablabStorageForLevel(1), 100);
      expect(defaultFablabConfig.fablabStorageForLevel(4), 400);
      expect(defaultFablabConfig.houseStorageForLevel(1), 100);
      expect(defaultFablabConfig.houseStorageForLevel(4), 200);
    });

    test('unlocks the finite room queue at level two', () {
      expect(
        defaultFablabConfig.queueCapacityFor(FabLabRoom.kitchen, 1),
        0,
      );
      expect(
        defaultFablabConfig.queueCapacityFor(FabLabRoom.kitchen, 2),
        1,
      );
      expect(
        defaultFablabConfig.queueCapacityFor(FabLabRoom.workshop, 4),
        3,
      );
      expect(
        defaultFablabConfig.roomSupportsMarketRestock(
          FabLabRoom.workshop,
          4,
        ),
        isTrue,
      );
    });

    test('keeps recycler capacities and module access per vat', () {
      expect(defaultFablabConfig.recyclerInputForLevel(1), 18);
      expect(defaultFablabConfig.recyclerInputForLevel(4), 12);
      expect(defaultFablabConfig.recyclerVatCapacityFor(0, 4), 60);
      expect(defaultFablabConfig.recyclerVatCapacityFor(1, 3), 20);
      expect(defaultFablabConfig.recyclerVatSupportsModule(1, 3), isFalse);
      expect(defaultFablabConfig.recyclerVatSupportsModule(1, 4), isTrue);
    });
  });
}
