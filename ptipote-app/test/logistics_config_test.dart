import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/logistics_config.dart';

void main() {
  test('la Logistique suit les paliers validés sans concepts de véhicules', () {
    expect(defaultLogisticsConfig.requiredCampHeartLevel, 2);
    expect(defaultLogisticsConfig.forLevel(1).storageBonus, 100);
    expect(defaultLogisticsConfig.forLevel(2).storageBonus, 200);
    expect(defaultLogisticsConfig.forLevel(3).storageBonus, 300);
    expect(defaultLogisticsConfig.forLevel(4).storageBonus, 400);
    expect(defaultLogisticsConfig.forLevel(3).queueCapacity, 3);
    expect(defaultLogisticsConfig.forLevel(3).parallelConstructionCapacity, 1);
    expect(defaultLogisticsConfig.forLevel(4).parallelConstructionCapacity, 2);
  });

  test('le seuil et la durée de maintenance restent configurables', () {
    expect(defaultLogisticsConfig.defaultRepairThreshold, 70);
    expect(defaultLogisticsConfig.autoRepairDurationMinutes, 20);
    expect(defaultLogisticsConfig.forLevel(4).repairKitCapacity, 30);
    expect(defaultLogisticsConfig.forLevel(4).ptipoteSlots, 2);
  });
}
