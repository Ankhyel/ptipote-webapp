import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/market_config.dart';
import 'package:ptipote_app/features/game/security_tower_config.dart';
import 'package:ptipote_app/features/game/waste_recycler_config.dart';
import 'package:ptipote_app/features/game/workshop_config.dart';
import 'package:ptipote_app/features/game/zone0_game_state.dart';

void main() {
  test('un chantier termine une seule fois apres un retour hors ligne', () {
    final startedAt = DateTime(2026, 7, 17, 10);
    final project = ConstructionProject(
      projectId: 'atelier',
      targetId: 'atelier',
      targetType: 'building',
      currentLevel: 1,
      targetLevel: 2,
      requirements: <String, int>{'Minéral': 20},
      depositedMaterials: <String, int>{'Minéral': 20},
      constructionDuration: const Duration(minutes: 30),
      state: ConstructionProjectState.upgrading,
      startedAt: startedAt,
      endsAt: startedAt.add(const Duration(minutes: 30)),
    );

    expect(project.completeAt(startedAt.add(const Duration(minutes: 29))),
        isFalse);
    expect(
        project.completeAt(startedAt.add(const Duration(minutes: 31))), isTrue);
    expect(project.currentLevel, 2);
    expect(project.depositedMaterials, isEmpty);
    expect(
        project.completeAt(startedAt.add(const Duration(hours: 2))), isFalse);
  });

  test('les effets de niveau restent bornes et progressifs', () {
    expect(workshopConfig.buildingSpeedBonusForLevel(1), 0);
    expect(workshopConfig.buildingSpeedBonusForLevel(3), 0.10);
    expect(wasteRecyclerConfig.outputCapacity(2),
        wasteRecyclerConfig.outputStorageCapacity + 20);
    expect(securityTowerConfig.securityGainForLevel(3), 9);
    expect(marketConfig.slotsForLevel(2), 6);
    expect(marketConfig.maxRequestsForLevel(2), 4);
  });
}
