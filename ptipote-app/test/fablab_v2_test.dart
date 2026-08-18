import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/fablab_config.dart';
import 'package:ptipote_app/features/game/fablab_v2.dart';
import 'package:ptipote_app/features/game/remote_zone0_settings.dart';

void main() {
  group('FabLab V2 configuration', () {
    tearDown(() => applyRemoteZone0Settings(null));

    test('uses the validated shared-storage tables', () {
      expect(defaultFablabConfig.fablabStorageForLevel(1), 100);
      expect(defaultFablabConfig.fablabStorageForLevel(4), 350);
      // Legacy saves can still carry the pre-V2 FabLab N5. It maps to the
      // highest current storage tier instead of dropping the FabLab capacity.
      expect(defaultFablabConfig.fablabStorageForLevel(5), 350);
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

    test('does not let an unversioned legacy Dashboard restore the old cap',
        () {
      applyRemoteZone0Settings(<String, dynamic>{
        'fablab': <String, dynamic>{
          'fablabMaxLevel': 5,
          'fablabStorageByLevel': <String, int>{
            '1': 100,
            '2': 200,
            '3': 200,
            '4': 200,
            '5': 200,
          },
          'houseStorageByLevel': <String, int>{
            '1': 100,
            '2': 100,
            '3': 100,
            '4': 100,
          },
        },
      });

      expect(fablabConfig.schemaVersion, 2);
      expect(fablabConfig.fablabMaxLevel, 4);
      expect(fablabConfig.fablabStorageForLevel(5), 350);
      expect(fablabConfig.houseStorageForLevel(4), 200);
    });
  });
}
