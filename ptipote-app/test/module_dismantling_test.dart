import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/module_dismantling.dart';
import 'package:ptipote_app/features/game/zone0_game_state.dart';

void main() {
  group('ModuleDismantlingService', () {
    test('refunds only physical materials with floor rounding', () {
      expect(
        ModuleDismantlingService.refundFor(
          const <String, int>{
            'Organique': 5,
            'Minéral': 7,
            'Réflecteur thermique': 3,
          },
          percent: 50,
        ),
        const <String, int>{
          'Organique': 2,
          'Minéral': 3,
          'Réflecteur thermique': 1,
        },
      );
    });

    test('does not expose zero-value refunds and accumulates paid snapshots',
        () {
      final snapshot = ModuleDismantlingService.accumulate(
        const <String, int>{'Organique': 10, 'Minéral': 5},
        const <String, int>{'Organique': 20, 'Mycélium': 1},
      );
      expect(snapshot,
          const <String, int>{'Organique': 30, 'Minéral': 5, 'Mycélium': 1});
      expect(
        ModuleDismantlingService.refundFor(snapshot, percent: 50),
        const <String, int>{'Organique': 15, 'Minéral': 2},
      );
    });

    test('keeps a personal module cost snapshot when an inventory stack saves',
        () {
      final stack = Zone0InventoryStack(
        resource: 'Protection thermique P’TIPOTE',
        amount: 1,
        unitPhysicalCostSnapshots: <Map<String, int>?>[
          <String, int>{
            'Organique': 10,
            'Minéral': 5,
            'Réflecteur thermique': 5,
          },
        ],
      );

      final saved = stack.toFirebase();
      expect(
        saved['unitPhysicalCostSnapshots'],
        <Map<String, int>>[
          <String, int>{
            'Organique': 10,
            'Minéral': 5,
            'Réflecteur thermique': 5,
          },
        ],
      );

      final restored = Zone0InventoryStack.fromFirebase(saved);
      expect(restored.resource, stack.resource);
      expect(restored.amount, 1);
      expect(
        restored.unitPhysicalCostSnapshots,
        <Map<String, int>?>[
          <String, int>{
            'Organique': 10,
            'Minéral': 5,
            'Réflecteur thermique': 5,
          },
        ],
      );
    });
  });
}
