class WorkshopConfig {
  const WorkshopConfig({
    required this.vitalityCostPerUnit,
    required this.levelSpeedBonusPercent,
    required this.maxLevelSpeedBonusPercent,
    required this.buildingLevelSpeedBonusPercent,
    required this.maxBuildingSpeedBonusPercent,
    required this.slotsPerLevel,
    required this.ptipoteCraftTimeReductionPercent,
  });

  final int vitalityCostPerUnit;
  final double levelSpeedBonusPercent;
  final double maxLevelSpeedBonusPercent;
  final double buildingLevelSpeedBonusPercent;
  final double maxBuildingSpeedBonusPercent;
  final int slotsPerLevel;
  /// Applied to every craft handled by a P’TIPOTE, independently of level.
  final double ptipoteCraftTimeReductionPercent;

  int slotsForLevel(int level) => level.clamp(1, 99) * slotsPerLevel;

  double buildingSpeedBonusForLevel(int level) =>
      ((level.clamp(1, 99) - 1) * buildingLevelSpeedBonusPercent)
          .clamp(0, maxBuildingSpeedBonusPercent);
}

const WorkshopConfig defaultWorkshopConfig = WorkshopConfig(
  vitalityCostPerUnit: 5,
  levelSpeedBonusPercent: 0.01,
  maxLevelSpeedBonusPercent: 0.15,
  buildingLevelSpeedBonusPercent: 0.05,
  maxBuildingSpeedBonusPercent: 0.20,
  slotsPerLevel: 1,
  ptipoteCraftTimeReductionPercent: 0.20,
);

WorkshopConfig workshopConfig = defaultWorkshopConfig;
