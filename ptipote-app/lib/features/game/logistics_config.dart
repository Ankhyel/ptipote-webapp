/// Dashboard-tunable rules for the Camp Logistics building.  It deliberately
/// contains no vehicle or transport concepts: those are future extensions.
class LogisticsLevelConfig {
  const LogisticsLevelConfig({
    required this.storageBonus,
    required this.repairKitCapacity,
    required this.ptipoteSlots,
    required this.queueEnabled,
    required this.queueCapacity,
    required this.parallelConstructionCapacity,
  });

  final int storageBonus;
  final int repairKitCapacity;
  final int ptipoteSlots;
  final bool queueEnabled;
  final int queueCapacity;

  /// Number of queued construction projects that may run at once.  This is
  /// deliberately independent from maintenance posts.
  final int parallelConstructionCapacity;
}

class LogisticsConfig {
  const LogisticsConfig({
    required this.requiredCampHeartLevel,
    required this.levels,
    required this.autoRepairEnabled,
    required this.defaultRepairThreshold,
    required this.minimumRepairThreshold,
    required this.maximumRepairThreshold,
    required this.autoRepairDurationMinutes,
  });

  final int requiredCampHeartLevel;
  final Map<int, LogisticsLevelConfig> levels;
  final bool autoRepairEnabled;
  final int defaultRepairThreshold;
  final int minimumRepairThreshold;
  final int maximumRepairThreshold;
  final int autoRepairDurationMinutes;

  LogisticsLevelConfig forLevel(int level) =>
      levels[level.clamp(1, 4).toInt()] ?? levels[4]!;
}

const LogisticsConfig defaultLogisticsConfig = LogisticsConfig(
  requiredCampHeartLevel: 2,
  autoRepairEnabled: true,
  defaultRepairThreshold: 70,
  minimumRepairThreshold: 1,
  maximumRepairThreshold: 99,
  autoRepairDurationMinutes: 20,
  levels: <int, LogisticsLevelConfig>{
    1: LogisticsLevelConfig(
      storageBonus: 100,
      repairKitCapacity: 5,
      ptipoteSlots: 1,
      queueEnabled: false,
      queueCapacity: 0,
      parallelConstructionCapacity: 0,
    ),
    2: LogisticsLevelConfig(
      storageBonus: 200,
      repairKitCapacity: 10,
      ptipoteSlots: 1,
      queueEnabled: false,
      queueCapacity: 0,
      parallelConstructionCapacity: 0,
    ),
    3: LogisticsLevelConfig(
      storageBonus: 300,
      repairKitCapacity: 20,
      ptipoteSlots: 1,
      queueEnabled: true,
      queueCapacity: 3,
      parallelConstructionCapacity: 1,
    ),
    4: LogisticsLevelConfig(
      storageBonus: 400,
      repairKitCapacity: 30,
      ptipoteSlots: 2,
      queueEnabled: true,
      queueCapacity: 3,
      parallelConstructionCapacity: 2,
    ),
  },
);

LogisticsConfig logisticsConfig = defaultLogisticsConfig;
