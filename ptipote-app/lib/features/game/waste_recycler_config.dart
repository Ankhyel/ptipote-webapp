class WasteRecyclerConfig {
  const WasteRecyclerConfig({
    required this.wasteGenerationCycleMinutes,
    required this.baseWastePerCycle,
    required this.populationPerWasteUnit,
    required this.buildingsPerWasteUnit,
    required this.wasteRewardMinimumPercent,
    required this.wasteRewardMaximumPercent,
    required this.recyclerUnlockCampHeartLevel,
    required this.initialRecyclerLevel,
    required this.recyclerMaxLevel,
    required this.baseWasteTankCapacity,
    required this.wasteTankCapacityPerLevel,
    required this.baseWasteRequired,
    required this.minimumWasteRequired,
    required this.outputResourcesPerCycle,
    required this.energyUnitsPerBioBattery,
    required this.energyCostPerCycle,
    required this.outputStorageCapacity,
    required this.outputStorageCapacityPerLevel,
    required this.pendingWasteCapacity,
    required this.cycleMinutesByLevel,
    required this.outputSplits,
  });

  final int wasteGenerationCycleMinutes;
  final int baseWastePerCycle;
  final int populationPerWasteUnit;
  final int buildingsPerWasteUnit;
  final int wasteRewardMinimumPercent;
  final int wasteRewardMaximumPercent;
  final int recyclerUnlockCampHeartLevel;
  final int initialRecyclerLevel;
  final int recyclerMaxLevel;
  final int baseWasteTankCapacity;
  final int wasteTankCapacityPerLevel;
  final int baseWasteRequired;
  final int minimumWasteRequired;
  final int outputResourcesPerCycle;
  final int energyUnitsPerBioBattery;
  final int energyCostPerCycle;
  final int outputStorageCapacity;
  final int outputStorageCapacityPerLevel;
  final int pendingWasteCapacity;
  final Map<int, int> cycleMinutesByLevel;
  final List<RecyclerOutputSplit> outputSplits;

  int tankCapacity(int level) =>
      baseWasteTankCapacity + (level - 1) * wasteTankCapacityPerLevel;
  int wasteRequired(int level) =>
      (baseWasteRequired - (level - 1)).clamp(minimumWasteRequired, 999);
  int cycleMinutes(int level) => cycleMinutesByLevel[level] ?? 20;
  int outputCapacity(int level) =>
      outputStorageCapacity +
      (level.clamp(1, recyclerMaxLevel) - 1) * outputStorageCapacityPerLevel;
}

class RecyclerOutputSplit {
  const RecyclerOutputSplit(this.organic, this.mineral);
  final int organic;
  final int mineral;
}

const wasteRecyclerConfig = WasteRecyclerConfig(
  wasteGenerationCycleMinutes: 120,
  baseWastePerCycle: 0,
  populationPerWasteUnit: 5,
  buildingsPerWasteUnit: 3,
  wasteRewardMinimumPercent: 15,
  wasteRewardMaximumPercent: 30,
  recyclerUnlockCampHeartLevel: 2,
  initialRecyclerLevel: 1,
  recyclerMaxLevel: 5,
  baseWasteTankCapacity: 34,
  wasteTankCapacityPerLevel: 12,
  baseWasteRequired: 17,
  minimumWasteRequired: 13,
  outputResourcesPerCycle: 10,
  energyUnitsPerBioBattery: 10,
  energyCostPerCycle: 1,
  outputStorageCapacity: 100,
  outputStorageCapacityPerLevel: 20,
  pendingWasteCapacity: 100,
  cycleMinutesByLevel: <int, int>{1: 20, 2: 18, 3: 16, 4: 14, 5: 12},
  outputSplits: <RecyclerOutputSplit>[
    RecyclerOutputSplit(7, 3),
    RecyclerOutputSplit(6, 4),
    RecyclerOutputSplit(5, 5),
    RecyclerOutputSplit(4, 6),
    RecyclerOutputSplit(3, 7),
  ],
);
