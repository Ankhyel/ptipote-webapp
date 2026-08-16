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
    required this.energyUnitsPerBioBatteryByBuildingLevel,
    required this.energyCostPerCycle,
    required this.outputStorageCapacity,
    required this.outputStorageCapacityPerLevel,
    required this.pendingWasteCapacity,
    required this.cycleMinutesByLevel,
    required this.outputSplits,
    required this.wastePerResidentPerDay,
    required this.wastePerPtibotePerDay,
    required this.wastePerPtibugPerDay,
    required this.wasteHistoryRetentionDays,
    required this.standardOrganicRatio,
    required this.standardMineralRatio,
    required this.standardOtherRatio,
    required this.biologicalOrganicRatio,
    required this.biologicalMineralRatio,
    required this.biologicalOtherRatio,
    required this.otherOutputResource,
    required this.biologicalOrientationModuleCost,
    required this.organicRecyclerModuleCost,
    required this.mineralRecyclerModuleCost,
    required this.recyclerModuleRefundPercent,
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

  /// Legacy global value kept as a fallback for old remote configurations.
  final int energyUnitsPerBioBattery;
  final Map<int, int> energyUnitsPerBioBatteryByBuildingLevel;
  final int energyCostPerCycle;
  final int outputStorageCapacity;
  final int outputStorageCapacityPerLevel;
  final int pendingWasteCapacity;
  final Map<int, int> cycleMinutesByLevel;
  final List<RecyclerOutputSplit> outputSplits;
  final double wastePerResidentPerDay;
  final double wastePerPtibotePerDay;
  final double wastePerPtibugPerDay;
  final int wasteHistoryRetentionDays;
  final int standardOrganicRatio;
  final int standardMineralRatio;
  final int standardOtherRatio;
  final int biologicalOrganicRatio;
  final int biologicalMineralRatio;
  final int biologicalOtherRatio;
  final String otherOutputResource;
  final Map<String, int> biologicalOrientationModuleCost;
  final Map<String, int> organicRecyclerModuleCost;
  final Map<String, int> mineralRecyclerModuleCost;
  final int recyclerModuleRefundPercent;

  int tankCapacity(int level) =>
      baseWasteTankCapacity + (level - 1) * wasteTankCapacityPerLevel;
  int wasteRequired(int level) =>
      (baseWasteRequired - (level - 1)).clamp(minimumWasteRequired, 999);
  int cycleMinutes(int level) => cycleMinutesByLevel[level] ?? 20;
  int outputCapacity(int level) =>
      outputStorageCapacity +
      (level.clamp(1, recyclerMaxLevel) - 1) * outputStorageCapacityPerLevel;

  int energyUnitsForBuildingLevel(int level) {
    final safeLevel = level < 1 ? 1 : level;
    return energyUnitsPerBioBatteryByBuildingLevel[safeLevel] ??
        energyUnitsPerBioBatteryByBuildingLevel[6] ??
        energyUnitsPerBioBattery;
  }
}

class RecyclerOutputSplit {
  const RecyclerOutputSplit(this.organic, this.mineral);
  final int organic;
  final int mineral;
}

const WasteRecyclerConfig defaultWasteRecyclerConfig = WasteRecyclerConfig(
  wasteGenerationCycleMinutes: 120,
  baseWastePerCycle: 0,
  populationPerWasteUnit: 5,
  buildingsPerWasteUnit: 3,
  wasteRewardMinimumPercent: 15,
  wasteRewardMaximumPercent: 30,
  recyclerUnlockCampHeartLevel: 2,
  initialRecyclerLevel: 1,
  recyclerMaxLevel: 5,
  baseWasteTankCapacity: 50,
  wasteTankCapacityPerLevel: 12,
  baseWasteRequired: 17,
  minimumWasteRequired: 13,
  outputResourcesPerCycle: 10,
  energyUnitsPerBioBattery: 100,
  energyUnitsPerBioBatteryByBuildingLevel: <int, int>{
    1: 100,
    2: 100,
    3: 100,
    4: 100,
    5: 100,
    6: 100,
  },
  energyCostPerCycle: 1,
  outputStorageCapacity: 50,
  outputStorageCapacityPerLevel: 20,
  pendingWasteCapacity: 100,
  cycleMinutesByLevel: <int, int>{1: 20, 2: 18, 3: 16, 4: 14, 5: 12},
  outputSplits: <RecyclerOutputSplit>[
    // Each standard cycle chooses one of these matter-only distributions.
    // The 20/80 to 50/50 range is mirrored by the resolver so either
    // Organique or Minéral can be the dominant material.
    RecyclerOutputSplit(2, 8),
    RecyclerOutputSplit(3, 7),
    RecyclerOutputSplit(4, 6),
    RecyclerOutputSplit(5, 5),
  ],
  wastePerResidentPerDay: .5,
  wastePerPtibotePerDay: .25,
  wastePerPtibugPerDay: .1,
  wasteHistoryRetentionDays: 7,
  standardOrganicRatio: 50,
  standardMineralRatio: 50,
  standardOtherRatio: 0,
  // The biological orientation is the explicit exception: it weights the
  // same material-only output towards Organique.
  biologicalOrganicRatio: 70,
  biologicalMineralRatio: 30,
  biologicalOtherRatio: 0,
  // Retained for backwards-compatible batch snapshots only. No current
  // recycler output uses a third resource.
  otherOutputResource: 'Autre',
  biologicalOrientationModuleCost: <String, int>{
    'Organique': 10,
    'Minéral': 10,
    'Mycélium': 5
  },
  organicRecyclerModuleCost: <String, int>{'Organique': 40, 'Minéral': 10},
  mineralRecyclerModuleCost: <String, int>{'Organique': 10, 'Minéral': 40},
  recyclerModuleRefundPercent: 50,
);

WasteRecyclerConfig wasteRecyclerConfig = defaultWasteRecyclerConfig;
