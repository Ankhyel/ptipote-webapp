class CampGeneratorConfig {
  const CampGeneratorConfig({
    required this.organicCapacityLevel1,
    required this.mineralCapacityLevel1,
    required this.organicCapacityPerLevel,
    required this.mineralCapacityPerLevel,
    required this.organicCostPerCycle,
    required this.mineralCostPerCycle,
    required this.bioBatteriesPerCycle,
    required this.cycleMinutesByLevel,
    required this.minimumCycleMinutes,
  });

  final int organicCapacityLevel1;
  final int mineralCapacityLevel1;
  final int organicCapacityPerLevel;
  final int mineralCapacityPerLevel;
  final int organicCostPerCycle;
  final int mineralCostPerCycle;
  final int bioBatteriesPerCycle;
  final List<int> cycleMinutesByLevel;
  final int minimumCycleMinutes;

  int organicCapacity(int level) =>
      organicCapacityLevel1 + (level.clamp(1, 5) - 1) * organicCapacityPerLevel;

  int mineralCapacity(int level) =>
      mineralCapacityLevel1 + (level.clamp(1, 5) - 1) * mineralCapacityPerLevel;

  int cycleMinutes(int level) {
    final index = level.clamp(1, cycleMinutesByLevel.length) - 1;
    return cycleMinutesByLevel[index].clamp(minimumCycleMinutes, 1440);
  }
}

const campGeneratorConfig = CampGeneratorConfig(
  // Four level-1 production paliers: 5 Organique + 1 Minéral each.
  organicCapacityLevel1: 20,
  mineralCapacityLevel1: 4,
  organicCapacityPerLevel: 10,
  mineralCapacityPerLevel: 2,
  organicCostPerCycle: 5,
  mineralCostPerCycle: 1,
  bioBatteriesPerCycle: 1,
  cycleMinutesByLevel: <int>[60, 50, 40, 35, 30],
  minimumCycleMinutes: 30,
);
