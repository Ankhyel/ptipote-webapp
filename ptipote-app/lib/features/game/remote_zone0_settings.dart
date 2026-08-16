import 'building_construction_config.dart';
import 'camp_generator_config.dart';
import 'camp_heart_config.dart';
import 'community_roles_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'housing_config.dart';
import 'kernel_config.dart';
import 'kernel_progress_config.dart';
import 'lisiere_forage_config.dart';
import 'market_config.dart';
import 'ptibug_config.dart';
import 'resident_economy_config.dart';
import 'security_tower_config.dart';
import 'tower_operations_config.dart';
import 'workshop_config.dart';
import 'waste_recycler_config.dart';

/// Applies Dashboard tuning without ever reading or writing player progress.
/// Invalid or incomplete values fall back to the versioned Dart defaults.
void applyRemoteZone0Settings(Map<String, dynamic>? raw) {
  campHeartConfig = _campHeart(raw?['campHeart']);
  lisiereForageConfig = _lisiere(raw?['lisiere']);
  securityTowerConfig = _tower(raw?['tower']);
  towerOperationsConfig = _towerOperations(raw?['towerOperations']);
  fablabConfig = _fablab(raw?['fablab']);
  workshopConfig = _workshop(raw?['workshop']);
  craftConfig = _craft(raw?['craft']);
  kernelConfig = _kernel(raw?['kernel']);
  kernelProgressConfig = _kernelProgress(raw?['kernelProgress']);
  marketConfig = _market(raw?['market']);
  housingConfig = _housing(raw?['housing']);
  communityRolesConfig = _communityRoles(raw?['communityRoles']);
  residentEconomyConfig = _residentEconomy(raw?['residentEconomy']);
  pTibugConfig = _ptibug(raw?['ptibug']);
  buildingConstructionConfig =
      _buildingConstruction(raw?['buildingConstruction']);
  campGeneratorConfig = _campGenerator(raw?['campGenerator']);
  wasteRecyclerConfig = _wasteRecycler(raw?['wasteRecycler']);
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

int _int(Object? value, int fallback) =>
    value is num && value.isFinite ? value.round() : fallback;
double _double(Object? value, double fallback) =>
    value is num && value.isFinite ? value.toDouble() : fallback;
String _string(Object? value, String fallback) =>
    value is String && value.trim().isNotEmpty ? value : fallback;
bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;

Map<String, int> _resourceMap(Object? value, Map<String, int> fallback) {
  final raw = _map(value);
  if (raw == null) return Map<String, int>.from(fallback);
  final result = Map<String, int>.from(fallback);
  for (final entry in raw.entries) {
    if (entry.value is num && (entry.value as num).isFinite) {
      result[entry.key] = _int(entry.value, result[entry.key] ?? 0);
    }
  }
  return result;
}

Map<int, Map<String, int>> _dataRequirementsByLevel(
  Object? value,
  Map<int, Map<String, int>> fallback,
) {
  final raw = _map(value);
  final result = <int, Map<String, int>>{
    for (final entry in fallback.entries)
      entry.key: Map<String, int>.from(entry.value),
  };
  if (raw == null) return result;
  for (final entry in raw.entries) {
    final level = int.tryParse(entry.key);
    if (level == null || level < 1) continue;
    result[level] = _resourceMap(entry.value, result[level] ?? const {});
  }
  return result;
}

BuildingConstructionConfig _buildingConstruction(Object? value) {
  final raw = _map(value);
  const base = defaultBuildingConstructionConfig;
  if (raw == null) return base;
  final projects = _map(raw['projects']);
  return BuildingConstructionConfig(
    mineralCostMultiplier:
        _double(raw['mineralCostMultiplier'], base.mineralCostMultiplier),
    defaultDurationMinutes:
        _int(raw['defaultDurationMinutes'], base.defaultDurationMinutes),
    projects: <String, BuildingProjectDefinition>{
      for (final entry in base.projects.entries)
        entry.key: () {
          final project = _map(projects?[entry.key]);
          return BuildingProjectDefinition(
            id: _string(project?['id'], entry.value.id),
            label: _string(project?['label'], entry.value.label),
            baseRequirements: _resourceMap(
              project?['baseRequirements'],
              entry.value.baseRequirements,
            ),
            requiredData: _resourceMap(
              project?['requiredData'],
              entry.value.requiredData,
            ),
            requiredDataByLevel: _dataRequirementsByLevel(
              project?['requiredDataByLevel'],
              entry.value.requiredDataByLevel,
            ),
            bypassBiomimicryRequirement:
                project?['bypassBiomimicryRequirement'] == true,
            durationMinutes:
                _int(project?['durationMinutes'], entry.value.durationMinutes),
          );
        }(),
    },
  );
}

CampGeneratorConfig _campGenerator(Object? value) {
  final raw = _map(value);
  const base = defaultCampGeneratorConfig;
  if (raw == null) return base;
  final cycleMinutes = raw['cycleMinutesByLevel'] as List?;
  return CampGeneratorConfig(
    organicCapacityLevel1:
        _int(raw['organicCapacityLevel1'], base.organicCapacityLevel1),
    mineralCapacityLevel1:
        _int(raw['mineralCapacityLevel1'], base.mineralCapacityLevel1),
    organicCapacityPerLevel:
        _int(raw['organicCapacityPerLevel'], base.organicCapacityPerLevel),
    mineralCapacityPerLevel:
        _int(raw['mineralCapacityPerLevel'], base.mineralCapacityPerLevel),
    organicCostPerCycle:
        _int(raw['organicCostPerCycle'], base.organicCostPerCycle),
    mineralCostPerCycle:
        _int(raw['mineralCostPerCycle'], base.mineralCostPerCycle),
    bioBatteriesPerCycle:
        _int(raw['bioBatteriesPerCycle'], base.bioBatteriesPerCycle),
    cycleMinutesByLevel: cycleMinutes == null
        ? List<int>.from(base.cycleMinutesByLevel)
        : List<int>.generate(
            base.cycleMinutesByLevel.length,
            (index) => _int(cycleMinutes.elementAtOrNull(index),
                base.cycleMinutesByLevel[index]),
          ),
    minimumCycleMinutes:
        _int(raw['minimumCycleMinutes'], base.minimumCycleMinutes),
  );
}

WasteRecyclerConfig _wasteRecycler(Object? value) {
  final raw = _map(value);
  const base = defaultWasteRecyclerConfig;
  if (raw == null) return base;
  final cycleMinutes = _map(raw['cycleMinutesByLevel']);
  final outputSplits = raw['outputSplits'] as List?;
  final orientationCost = _map(raw['biologicalOrientationModuleCost']);
  final organicModuleCost = _map(raw['organicRecyclerModuleCost']);
  final mineralModuleCost = _map(raw['mineralRecyclerModuleCost']);
  return WasteRecyclerConfig(
    wasteGenerationCycleMinutes: _int(
        raw['wasteGenerationCycleMinutes'], base.wasteGenerationCycleMinutes),
    baseWastePerCycle: _int(raw['baseWastePerCycle'], base.baseWastePerCycle),
    populationPerWasteUnit:
        _int(raw['populationPerWasteUnit'], base.populationPerWasteUnit),
    buildingsPerWasteUnit:
        _int(raw['buildingsPerWasteUnit'], base.buildingsPerWasteUnit),
    wasteRewardMinimumPercent:
        _int(raw['wasteRewardMinimumPercent'], base.wasteRewardMinimumPercent),
    wasteRewardMaximumPercent:
        _int(raw['wasteRewardMaximumPercent'], base.wasteRewardMaximumPercent),
    recyclerUnlockCampHeartLevel: _int(
        raw['recyclerUnlockCampHeartLevel'], base.recyclerUnlockCampHeartLevel),
    initialRecyclerLevel:
        _int(raw['initialRecyclerLevel'], base.initialRecyclerLevel),
    recyclerMaxLevel: _int(raw['recyclerMaxLevel'], base.recyclerMaxLevel),
    baseWasteTankCapacity:
        _int(raw['baseWasteTankCapacity'], base.baseWasteTankCapacity),
    wasteTankCapacityPerLevel:
        _int(raw['wasteTankCapacityPerLevel'], base.wasteTankCapacityPerLevel),
    baseWasteRequired: _int(raw['baseWasteRequired'], base.baseWasteRequired),
    minimumWasteRequired:
        _int(raw['minimumWasteRequired'], base.minimumWasteRequired),
    outputResourcesPerCycle:
        _int(raw['outputResourcesPerCycle'], base.outputResourcesPerCycle),
    energyUnitsPerBioBattery:
        _int(raw['energyUnitsPerBioBattery'], base.energyUnitsPerBioBattery),
    energyUnitsPerBioBatteryByBuildingLevel: <int, int>{
      for (final entry in base.energyUnitsPerBioBatteryByBuildingLevel.entries)
        entry.key: _int(
          _map(raw['energyUnitsPerBioBatteryByBuildingLevel'])?['${entry.key}'],
          entry.value,
        ),
    },
    energyCostPerCycle:
        _int(raw['energyCostPerCycle'], base.energyCostPerCycle),
    outputStorageCapacity:
        _int(raw['outputStorageCapacity'], base.outputStorageCapacity),
    outputStorageCapacityPerLevel: _int(raw['outputStorageCapacityPerLevel'],
        base.outputStorageCapacityPerLevel),
    pendingWasteCapacity:
        _int(raw['pendingWasteCapacity'], base.pendingWasteCapacity),
    cycleMinutesByLevel: <int, int>{
      for (final entry in base.cycleMinutesByLevel.entries)
        entry.key: _int(cycleMinutes?['${entry.key}'], entry.value),
    },
    outputSplits: outputSplits == null
        ? List<RecyclerOutputSplit>.from(base.outputSplits)
        : List<RecyclerOutputSplit>.generate(base.outputSplits.length, (index) {
            final split = outputSplits.elementAtOrNull(index);
            final fallback = base.outputSplits[index];
            return RecyclerOutputSplit(
              _int(
                  split is Map
                      ? split['organic']
                      : split is List
                          ? split.elementAtOrNull(0)
                          : null,
                  fallback.organic),
              _int(
                  split is Map
                      ? split['mineral']
                      : split is List
                          ? split.elementAtOrNull(1)
                          : null,
                  fallback.mineral),
            );
          }),
    wastePerResidentPerDay:
        _double(raw['wastePerResidentPerDay'], base.wastePerResidentPerDay),
    wastePerPtibotePerDay:
        _double(raw['wastePerPtibotePerDay'], base.wastePerPtibotePerDay),
    wastePerPtibugPerDay:
        _double(raw['wastePerPtibugPerDay'], base.wastePerPtibugPerDay),
    wasteHistoryRetentionDays:
        _int(raw['wasteHistoryRetentionDays'], base.wasteHistoryRetentionDays),
    standardOrganicRatio:
        _int(raw['standardOrganicRatio'], base.standardOrganicRatio),
    standardMineralRatio:
        _int(raw['standardMineralRatio'], base.standardMineralRatio),
    // Water is contextual to Cuisine and must never come back as an
    // inventory output through an older remote Dashboard document.
    standardOtherRatio: 0,
    biologicalOrganicRatio:
        _int(raw['biologicalOrganicRatio'], base.biologicalOrganicRatio),
    biologicalMineralRatio:
        _int(raw['biologicalMineralRatio'], base.biologicalMineralRatio),
    biologicalOtherRatio: 0,
    otherOutputResource: 'Autre',
    biologicalOrientationModuleCost: <String, int>{
      for (final entry in base.biologicalOrientationModuleCost.entries)
        entry.key: _int(orientationCost?[entry.key], entry.value),
    },
    organicRecyclerModuleCost: <String, int>{
      for (final entry in base.organicRecyclerModuleCost.entries)
        entry.key: _int(organicModuleCost?[entry.key], entry.value),
    },
    mineralRecyclerModuleCost: <String, int>{
      for (final entry in base.mineralRecyclerModuleCost.entries)
        entry.key: _int(mineralModuleCost?[entry.key], entry.value),
    },
    recyclerModuleRefundPercent: _int(
        raw['recyclerModuleRefundPercent'], base.recyclerModuleRefundPercent),
  );
}

KernelConfig _kernel(Object? value) {
  final raw = _map(value);
  const base = defaultKernelConfig;
  if (raw == null) return base;
  final capacities = _map(raw['populationCapacityByCampHeartLevel']);
  final missions = raw['missions'] is List ? raw['missions'] as List : const [];
  final plans = raw['plans'] is List ? raw['plans'] as List : const [];
  final planById = <String, Map<String, dynamic>>{
    for (final item in plans)
      if (_map(item) case final map?) _string(map['id'], ''): map,
  };
  return KernelConfig(
    startingPopulation: _int(
      raw['startingPopulation'],
      base.startingPopulation,
    ),
    startingWellbeing: _int(raw['startingWellbeing'], base.startingWellbeing),
    startingBioBatteries: _int(
      raw['startingBioBatteries'],
      base.startingBioBatteries,
    ),
    maxRefugeRequests: _int(raw['maxRefugeRequests'], base.maxRefugeRequests),
    populationCapacityByCampHeartLevel: <int, int>{
      for (final entry in base.populationCapacityByCampHeartLevel.entries)
        entry.key: _int(capacities?['${entry.key}'], entry.value),
    },
    wellbeingRedThreshold: _int(
      raw['wellbeingRedThreshold'],
      base.wellbeingRedThreshold,
    ),
    wellbeingOrangeThreshold: _int(
      raw['wellbeingOrangeThreshold'],
      base.wellbeingOrangeThreshold,
    ),
    missions: () {
      final parsed = missions
          .map(_map)
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => _kernelMission(
              item,
              base.missions
                  .where((mission) => mission.id == item['id'])
                  .firstOrNull,
            ),
          )
          .whereType<KernelMissionConfig>()
          .toList();
      if (parsed.isEmpty) return base.missions;
      return <KernelMissionConfig>[
        ...parsed,
        ...base.missions.where(
          (fallback) => !parsed.any((mission) => mission.id == fallback.id),
        ),
      ];
    }(),
    plans: base.plans.map((fallback) {
      final item = planById[fallback.id];
      return KernelPlanConfig(
        id: fallback.id,
        title: _string(item?['title'], fallback.title),
        description: _string(item?['description'], fallback.description),
        requiredCampHeartLevel: _int(
          item?['requiredCampHeartLevel'],
          fallback.requiredCampHeartLevel,
        ),
      );
    }).toList(),
  );
}

KernelMissionConfig? _kernelMission(
  Map<String, dynamic> raw,
  KernelMissionConfig? fallback,
) {
  final id = _string(raw['id'], fallback?.id ?? '');
  if (id.isEmpty) return null;
  final requestedItem = _string(raw['requestedItem'], '');
  final rewardPatternId = _string(raw['rewardPatternId'], '');
  final weatherType = _string(raw['weatherType'], '');
  return KernelMissionConfig(
    id: id,
    type: _kernelMissionType(
      raw['type'],
      fallback?.type ?? KernelMissionType.refugeRequest,
    ),
    title: _string(raw['title'], fallback?.title ?? id),
    description: _string(raw['description'], fallback?.description ?? ''),
    conditionType: _kernelMissionCondition(
      raw['conditionType'],
      fallback?.conditionType ?? KernelMissionConditionType.requirementsMet,
    ),
    requiredAmount: _int(raw['requiredAmount'], fallback?.requiredAmount ?? 1),
    populationReward: _int(
      raw['populationReward'],
      fallback?.populationReward ?? 0,
    ),
    bioBatteryReward: _int(
      raw['bioBatteryReward'],
      fallback?.bioBatteryReward ?? 0,
    ),
    xpReward: _int(raw['xpReward'], fallback?.xpReward ?? 0),
    mailMessage: _string(
      raw['mailMessage'],
      fallback?.mailMessage ?? 'Mission Kernel terminée.',
    ),
    requiredBuildingLevels: _positiveMap(raw['requiredBuildingLevels']),
    requiredKernelTrustLevel: _int(
      raw['requiredKernelTrustLevel'],
      fallback?.requiredKernelTrustLevel ?? 1,
    ),
    requiredBreederLevel: _int(
      raw['requiredBreederLevel'],
      fallback?.requiredBreederLevel ?? 1,
    ),
    requiredBuilderLevel: _int(
      raw['requiredBuilderLevel'],
      fallback?.requiredBuilderLevel ?? 1,
    ),
    requiredRestorerLevel: _int(
      raw['requiredRestorerLevel'],
      fallback?.requiredRestorerLevel ?? 1,
    ),
    requestedItem: requestedItem.isEmpty ? null : requestedItem,
    requestedAmount: _int(
      raw['requestedAmount'],
      fallback?.requestedAmount ?? 0,
    ),
    resourceRewards: _positiveMap(raw['resourceRewards']),
    rewardPatternId: rewardPatternId.isEmpty ? null : rewardPatternId,
    weatherType: weatherType.isEmpty ? null : weatherType,
    weatherDemandOptions: _stringList(raw['weatherDemandOptions']),
  );
}

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().where((item) => item.trim().isNotEmpty).toList()
    : const <String>[];

Map<String, int> _positiveMap(Object? value) {
  final raw = _map(value);
  if (raw == null) return const <String, int>{};
  return <String, int>{
    for (final entry in raw.entries)
      if (entry.value is num && (entry.value as num) > 0)
        entry.key: (entry.value as num).round(),
  };
}

KernelMissionType _kernelMissionType(
  Object? value,
  KernelMissionType fallback,
) =>
    KernelMissionType.values.where((type) => type.name == value).firstOrNull ??
    fallback;

KernelMissionConditionType _kernelMissionCondition(
  Object? value,
  KernelMissionConditionType fallback,
) =>
    KernelMissionConditionType.values
        .where((type) => type.name == value)
        .firstOrNull ??
    fallback;

KernelProgressConfig _kernelProgress(Object? value) {
  final raw = _map(value);
  const base = defaultKernelProgressConfig;
  if (raw == null) return base;
  final rawRewards = _map(raw['eventRewards']);
  final rawPlans = raw['plans'] is List ? raw['plans'] as List : const [];
  final planById = <String, Map<String, dynamic>>{
    for (final item in rawPlans)
      if (_map(item) case final map?) _string(map['id'], ''): map,
  };
  return KernelProgressConfig(
    trustXpRequiredBase: _int(
      raw['trustXpRequiredBase'],
      base.trustXpRequiredBase,
    ),
    axisXpRequiredBase: _int(
      raw['axisXpRequiredBase'],
      base.axisXpRequiredBase,
    ),
    xpRequiredMultiplier: _double(
      raw['xpRequiredMultiplier'],
      base.xpRequiredMultiplier,
    ),
    eventRewards: <KernelProgressEventType, KernelProgressReward>{
      for (final event in KernelProgressEventType.values)
        event: _kernelReward(
          _map(rawRewards?[event.name]),
          base.eventRewards[event]!,
        ),
    },
    plans: base.plans.map((fallback) {
      final item = planById[fallback.id];
      return KernelTechnologyPlanConfig(
        id: fallback.id,
        title: _string(item?['title'], fallback.title),
        description: _string(item?['description'], fallback.description),
        category: fallback.category,
        iconName: fallback.iconName,
        origin: _string(item?['origin'], fallback.origin),
        kernelText: _string(item?['kernelText'], fallback.kernelText),
        discoveryEvent: _kernelEvent(
          item?['discoveryEvent'],
          fallback.discoveryEvent,
        ),
        discoveryThreshold: _int(
          item?['discoveryThreshold'],
          fallback.discoveryThreshold,
        ),
        requiredTrustLevel: _int(
          item?['requiredTrustLevel'],
          fallback.requiredTrustLevel,
        ),
        requiredAxis: _kernelAxis(item?['requiredAxis'], fallback.requiredAxis),
        requiredAxisLevel: _int(
          item?['requiredAxisLevel'],
          fallback.requiredAxisLevel,
        ),
        requiredBreederLevel: _int(
          item?['requiredBreederLevel'],
          fallback.requiredBreederLevel,
        ),
        requiredBuilderLevel: _int(
          item?['requiredBuilderLevel'],
          fallback.requiredBuilderLevel,
        ),
        requiredRestorerLevel: _int(
          item?['requiredRestorerLevel'],
          fallback.requiredRestorerLevel,
        ),
        requiredBuildingLevels: _resourceMap(
          item?['requiredBuildingLevels'],
          fallback.requiredBuildingLevels,
        ),
        dataRequirements: _resourceMap(
          item?['dataRequirements'],
          fallback.dataRequirements,
        ),
        workshopRecipeId: _string(
          item?['workshopRecipeId'],
          fallback.workshopRecipeId ?? '',
        ).isEmpty
            ? null
            : _string(
                item?['workshopRecipeId'],
                fallback.workshopRecipeId ?? '',
              ),
        initialState: _kernelPlanState(
          item?['initialState'] ?? item?['state'],
          fallback.initialState,
        ),
        discoverWhenRequirementsMet:
            item?['discoverWhenRequirementsMet'] is bool
                ? item!['discoverWhenRequirementsMet'] as bool
                : fallback.discoverWhenRequirementsMet,
      );
    }).toList(),
  );
}

Map<int, int> _levelMap(Object? value, Map<int, int> fallback) {
  final raw = _map(value);
  if (raw == null) return fallback;
  return <int, int>{
    for (final entry in fallback.entries)
      entry.key: _int(raw['${entry.key}'], entry.value),
  };
}

TowerResearchConfig _towerResearch(Object? value, TowerResearchConfig base) {
  final raw = _map(value);
  if (raw == null) return base;
  return TowerResearchConfig(
    researchEnabled: _bool(raw['researchEnabled'], base.researchEnabled),
    researchRequiresPtipote:
        _bool(raw['researchRequiresPtipote'], base.researchRequiresPtipote),
    toxicCloudGuaranteeEnabled: _bool(
      raw['toxicCloudGuaranteeEnabled'],
      base.toxicCloudGuaranteeEnabled,
    ),
    toxicCapsuleGuaranteedAmount: _int(
      raw['toxicCapsuleGuaranteedAmount'],
      base.toxicCapsuleGuaranteedAmount,
    ),
    harvestCellChanceByOrdinal: _levelMap(
        raw['harvestCellChanceByOrdinal'], base.harvestCellChanceByOrdinal),
    researchCellChanceByOrdinal: _levelMap(
        raw['researchCellChanceByOrdinal'], base.researchCellChanceByOrdinal),
    harvestValueSevenEightChance: _int(
        raw['harvestValueSevenEightChance'], base.harvestValueSevenEightChance),
    harvestValueNineChance:
        _int(raw['harvestValueNineChance'], base.harvestValueNineChance),
    researchValueSevenEightChance: _int(raw['researchValueSevenEightChance'],
        base.researchValueSevenEightChance),
    researchValueNineChance:
        _int(raw['researchValueNineChance'], base.researchValueNineChance),
    progressPerHour: _int(raw['progressPerHour'], base.progressPerHour),
    cellChancePerHour: _int(raw['cellChancePerHour'], base.cellChancePerHour),
    progressDecayPerDay:
        _int(raw['progressDecayPerDay'], base.progressDecayPerDay),
    cellChanceRevealPercent:
        _int(raw['cellChanceRevealPercent'], base.cellChanceRevealPercent),
    valueChanceRevealPercent:
        _int(raw['valueChanceRevealPercent'], base.valueChanceRevealPercent),
    familyRevealPercent:
        _int(raw['familyRevealPercent'], base.familyRevealPercent),
    fullRevealPercent: _int(raw['fullRevealPercent'], base.fullRevealPercent),
  );
}

Map<int, int> _intLevels(
  Object? value,
  Map<int, int> fallback,
  int maxLevel,
) {
  final raw = _map(value);
  if (raw == null) return fallback;
  return <int, int>{
    for (var level = 1; level <= maxLevel; level++)
      level: _int(raw['$level'], fallback[level] ?? 0),
  };
}

Map<int, double> _doubleLevelMap(
  Object? value,
  Map<int, double> fallback,
) {
  final raw = _map(value);
  if (raw == null) return fallback;
  return <int, double>{
    for (final entry in fallback.entries)
      entry.key: _double(raw['${entry.key}'], entry.value),
  };
}

PTibugPatternCategory _ptibugPatternCategory(
  Object? value,
  PTibugPatternCategory fallback,
) =>
    PTibugPatternCategory.values
        .where((category) => category.name == value)
        .firstOrNull ??
    fallback;

PTibugSpecies? _ptibugSpecies(Object? value) =>
    PTibugSpecies.values.where((species) => species.name == value).firstOrNull;

PTibugModuleType? _ptibugModuleType(Object? value) =>
    PTibugModuleType.values.where((type) => type.name == value).firstOrNull;

PTibugBiome? _ptibugBiome(Object? value) =>
    PTibugBiome.values.where((biome) => biome.name == value).firstOrNull;

Map<PTibugDataFamily, int> _dataFamilyMap(
  Object? value,
  Map<PTibugDataFamily, int> fallback,
) {
  final raw = _map(value);
  if (raw == null) return fallback;
  return <PTibugDataFamily, int>{
    for (final family in PTibugDataFamily.values)
      if (raw[family.name] is num || fallback.containsKey(family))
        family: _int(raw[family.name], fallback[family] ?? 0),
  };
}

Map<int, Map<PTibugDataFamily, int>> _dataCostsByLevel(
  Object? value,
  Map<int, Map<PTibugDataFamily, int>> fallback,
  int maxLevel,
) {
  final raw = _map(value);
  if (raw == null) return fallback;
  return <int, Map<PTibugDataFamily, int>>{
    for (var level = 1; level <= maxLevel; level++)
      level: _dataFamilyMap(raw['$level'], fallback[level] ?? const {}),
  };
}

Map<int, Map<String, int>> _materialCostsByLevel(
  Object? value,
  Map<int, Map<String, int>> fallback,
  int maxLevel,
) {
  final raw = _map(value);
  if (raw == null) return fallback;
  return <int, Map<String, int>>{
    for (var level = 1; level <= maxLevel; level++)
      level: _resourceMap(raw['$level'], fallback[level] ?? const {}),
  };
}

PTibugResearchPatternConfig _researchPattern(
  String id,
  Map<String, dynamic>? raw,
  PTibugResearchPatternConfig? fallback,
) {
  final maxLevel = _int(raw?['maxLevel'], fallback?.masteryCosts.length ?? 3);
  return PTibugResearchPatternConfig(
    id: _string(raw?['id'], fallback?.id ?? id),
    displayName: _string(raw?['displayName'], fallback?.displayName ?? id),
    category: _ptibugPatternCategory(
      raw?['category'],
      fallback?.category ?? PTibugPatternCategory.advancedTechnology,
    ),
    description: _string(raw?['description'], fallback?.description ?? ''),
    masteryCosts: _dataCostsByLevel(
      raw?['masteryCosts'],
      fallback?.masteryCosts ?? const <int, Map<PTibugDataFamily, int>>{},
      maxLevel,
    ),
    linkedSpecies:
        _ptibugSpecies(raw?['linkedSpecies']) ?? fallback?.linkedSpecies,
    linkedTraitId: _string(
      raw?['linkedTraitId'],
      fallback?.linkedTraitId ?? '',
    ).isEmpty
        ? null
        : _string(raw?['linkedTraitId'], fallback?.linkedTraitId ?? ''),
    linkedModuleType: _ptibugModuleType(raw?['linkedModuleType']) ??
        fallback?.linkedModuleType,
    requiredTrustLevel: _int(
      raw?['requiredTrustLevel'],
      fallback?.requiredTrustLevel ?? 1,
    ),
    requiredBreederLevel: _int(
      raw?['requiredBreederLevel'],
      fallback?.requiredBreederLevel ?? 0,
    ),
    requiredBuilderLevel: _int(
      raw?['requiredBuilderLevel'],
      fallback?.requiredBuilderLevel ?? 0,
    ),
    requiredRestorerLevel: _int(
      raw?['requiredRestorerLevel'],
      fallback?.requiredRestorerLevel ?? 0,
    ),
    origin: _string(raw?['origin'], fallback?.origin ?? 'Kernel'),
    biomesSuggested: raw?['biomesSuggested'] is List
        ? (raw!['biomesSuggested'] as List)
            .map(_ptibugBiome)
            .whereType<PTibugBiome>()
            .toList()
        : fallback?.biomesSuggested ?? const <PTibugBiome>[],
  );
}

PTibugBiomeConfig _biomeConfig(
  Map<String, dynamic>? raw,
  PTibugBiomeConfig fallback,
) {
  final rawBonuses = _map(raw?['localProductionBonus']);
  return PTibugBiomeConfig(
    displayName: _string(raw?['displayName'], fallback.displayName),
    risks: raw?['risks'] is List
        ? (raw!['risks'] as List).whereType<String>().toList()
        : fallback.risks,
    dataWeights: _dataFamilyMap(raw?['dataWeights'], fallback.dataWeights),
    localProductionBonus: <PTibugSpecies, Map<String, int>>{
      for (final species in PTibugSpecies.values)
        if (_map(rawBonuses?[species.name]) != null ||
            fallback.localProductionBonus.containsKey(species))
          species: _resourceMap(
            rawBonuses?[species.name],
            fallback.localProductionBonus[species] ?? const <String, int>{},
          ),
    },
    nurseryInsectBehaviourWeight: _int(
      raw?['nurseryInsectBehaviourWeight'],
      fallback.nurseryInsectBehaviourWeight,
    ),
    aracProductionWeights: _resourceMap(
      raw?['aracProductionWeights'],
      fallback.aracProductionWeights,
    ),
    weatherTypes: raw?['weatherTypes'] is List
        ? (raw!['weatherTypes'] as List).whereType<String>().toList()
        : fallback.weatherTypes,
  );
}

PTibugConfig _ptibug(Object? value) {
  final raw = _map(value);
  final base = defaultPTibugConfig;
  if (raw == null) return base;
  final rawSpecies = _map(raw['species']);
  final rawPatterns = _map(raw['patterns']);
  final rawPrices = _map(raw['sourcierPatternPrices']);
  final rawTraits = _map(raw['traitDefinitions']);
  final rawResearchPatterns = _map(raw['researchPatterns']);
  final rawBiomes = _map(raw['biomes']);
  final rawQualityValues = _map(raw['dataQualityValues']);
  final rawQualityWeights = _map(raw['dataQualityWeights']);
  final rawModuleCraftCosts = _map(raw['moduleCraftCosts']);
  final rawModuleCraftEnergyCosts = _map(raw['moduleCraftEnergyCosts']);
  final rawModuleCraftMinutes = _map(raw['moduleCraftMinutes']);
  final rawTerritory = _map(raw['territory']);
  final rawProgression = _map(raw['progression']);
  final rawModuleCapacity = _map(raw['moduleCapacity']);
  final rawWeather = _map(raw['weather']);
  final rawCultivation = _map(raw['cultivation']);
  final rawValuation = _map(raw['valuation']);
  final rawAppearance = _map(raw['appearance']);
  final rawAspectMatrixExtractor = _map(raw['aspectMatrixExtractor']);
  return PTibugConfig(
    nurseryRequirements: _resourceMap(
      raw['nurseryRequirements'],
      base.nurseryRequirements,
    ),
    nurseryDurationMinutes: _int(
      raw['nurseryDurationMinutes'],
      base.nurseryDurationMinutes,
    ),
    slotsByLevel: _levelMap(raw['slotsByLevel'], base.slotsByLevel),
    moduleSlotsByLevel: _levelMap(
      raw['moduleSlotsByLevel'],
      base.moduleSlotsByLevel,
    ),
    productionCycleMinutes: _int(
      raw['productionCycleMinutes'],
      base.productionCycleMinutes,
    ),
    carryingCapacity: _int(raw['carryingCapacity'], base.carryingCapacity),
    storageMultiplier: _int(
      raw['storageMultiplier'],
      base.storageMultiplier,
    ),
    xpPerCycle: _int(raw['xpPerCycle'], base.xpPerCycle),
    wingsCycleReduction: _double(
      raw['wingsCycleReduction'],
      base.wingsCycleReduction,
    ),
    clawProductionBonus: _int(
      raw['clawProductionBonus'],
      base.clawProductionBonus,
    ),
    reservoirCapacityBonus: _int(
      raw['reservoirCapacityBonus'],
      base.reservoirCapacityBonus,
    ),
    appearance: PTibugAppearanceConfig(
      primaryColorsBySpecies: <PTibugSpecies, List<String>>{
        for (final species in PTibugSpecies.values)
          species: () {
            final configured =
                _map(rawAppearance?['primaryColorsBySpecies'])?[species.name];
            return configured is List
                ? configured.whereType<String>().toList()
                : List<String>.from(
                    base.appearance.primaryColorsBySpecies[species] ??
                        const <String>[],
                  );
          }(),
      },
      motifBySpecies: <PTibugSpecies, String>{
        for (final species in PTibugSpecies.values)
          species: _string(
            _map(rawAppearance?['motifBySpecies'])?[species.name],
            base.appearance.motifBySpecies[species] ?? '',
          ),
      },
      animationNamesBySpecies: <PTibugSpecies, List<String>>{
        for (final species in PTibugSpecies.values)
          species: () {
            final configured =
                _map(rawAppearance?['animationNamesBySpecies'])?[species.name];
            return configured is List
                ? configured.whereType<String>().toList()
                : List<String>.from(
                    base.appearance.animationNamesBySpecies[species] ??
                        const <String>[],
                  );
          }(),
      },
      motifChancePercent: _int(
        rawAppearance?['motifChancePercent'],
        base.appearance.motifChancePercent,
      ).clamp(0, 100).toInt(),
    ),
    aspectMatrixExtractor: PTibugAspectMatrixExtractorConfig(
      moduleCountByLevel: _levelMap(
        rawAspectMatrixExtractor?['moduleCountByLevel'],
        base.aspectMatrixExtractor.moduleCountByLevel,
      ),
      matricesPerModuleByLevel: <int, List<int>>{
        for (final level in <int>[1, 2, 3, 4])
          level: (_map(rawAspectMatrixExtractor?['matricesPerModuleByLevel'])?[
                      '$level'] as List?)
                  ?.map((value) => _int(value, 1))
                  .toList() ??
              List<int>.from(
                  base.aspectMatrixExtractor.matricesPerModuleByLevel[level] ??
                      const <int>[1]),
      },
      durationMinutesByLevel: _levelMap(
        rawAspectMatrixExtractor?['durationMinutesByLevel'],
        base.aspectMatrixExtractor.durationMinutesByLevel,
      ),
      mineralCostPerModule: _int(
        rawAspectMatrixExtractor?['mineralCostPerModule'],
        base.aspectMatrixExtractor.mineralCostPerModule,
      ),
      organicCostPerModule: _int(
        rawAspectMatrixExtractor?['organicCostPerModule'],
        base.aspectMatrixExtractor.organicCostPerModule,
      ),
      nurseryEnergyCostPerModule: _int(
        rawAspectMatrixExtractor?['nurseryEnergyCostPerModule'],
        base.aspectMatrixExtractor.nurseryEnergyCostPerModule,
      ),
    ),
    ptibugPresenceInsectoidBonusWeight: _int(
      raw['ptibugPresenceInsectoidBonusWeight'],
      base.ptibugPresenceInsectoidBonusWeight,
    ),
    species: <PTibugSpecies, PTibugSpeciesConfig>{
      for (final entry in base.species.entries)
        entry.key: () {
          final item = _map(rawSpecies?[entry.key.name]);
          final fallback = entry.value;
          return PTibugSpeciesConfig(
            displayName: _string(item?['displayName'], fallback.displayName),
            styles: item?['styles'] is List
                ? (item?['styles'] as List).whereType<String>().toList()
                : fallback.styles,
            creationCost: _resourceMap(
              item?['creationCost'],
              fallback.creationCost,
            ),
            creationEnergyCost: _int(
              item?['creationEnergyCost'],
              fallback.creationEnergyCost,
            ),
            creationBioBatteryCost: _int(
              item?['creationBioBatteryCost'],
              fallback.creationBioBatteryCost,
            ),
            futureMyceliumCost: _int(
              item?['futureMyceliumCost'],
              fallback.futureMyceliumCost,
            ),
            creationMinutes: _int(
              item?['creationMinutes'],
              fallback.creationMinutes,
            ),
          );
        }(),
    },
    patterns: <PTibugSpecies, PTibugPatternConfig>{
      for (final entry in base.patterns.entries)
        entry.key: () {
          final item = _map(rawPatterns?[entry.key.name]);
          final fallback = entry.value;
          return PTibugPatternConfig(
            species: entry.key,
            kernelPlanId: _string(item?['kernelPlanId'], fallback.kernelPlanId),
            description: _string(item?['description'], fallback.description),
          );
        }(),
    },
    sourcierPatternPrices: <PTibugSpecies, int>{
      for (final entry in base.sourcierPatternPrices.entries)
        entry.key: _int(rawPrices?[entry.key.name], entry.value),
    },
    traitDefinitions: <String, PTibugTraitDefinition>{
      for (final id in <String>{
        ...base.traitDefinitions.keys,
        ...?rawTraits?.keys.where((key) => key != 'eclaireur'),
      })
        id: () {
          final item = _map(rawTraits?[id]);
          final fallback = base.traitDefinitions[id];
          final maxLevel = _int(item?['maxLevel'], fallback?.maxLevel ?? 3);
          final rawEffects = _resourceMap(
            item?['effects'],
            fallback?.effects ?? const <String, int>{},
          );
          final rawGrades = _map(item?['gradeMultipliers']);
          return PTibugTraitDefinition(
            id: _string(item?['id'], fallback?.id ?? id),
            displayName: _string(
              item?['displayName'],
              fallback?.displayName ?? id,
            ),
            description: _string(
              item?['description'],
              fallback?.description ?? '',
            ),
            effects: rawEffects,
            gradeMultipliers: <PTibugTraitGrade, int>{
              for (final grade in PTibugTraitGrade.values)
                grade: _int(
                  rawGrades?[grade.name],
                  fallback?.gradeMultipliers[grade] ?? 1,
                ),
            },
            colorHex: _string(
              item?['colorHex'],
              fallback?.colorHex ?? '#817D66',
            ),
            isActive: item?['isActive'] is bool
                ? item!['isActive'] as bool
                : fallback?.isActive ?? true,
            dataCostByLevel: _dataCostsByLevel(
              item?['dataCostByLevel'],
              fallback?.dataCostByLevel ??
                  const <int, Map<PTibugDataFamily, int>>{},
              maxLevel,
            ),
            materialCostByLevel: _materialCostsByLevel(
              item?['materialCostByLevel'],
              fallback?.materialCostByLevel ?? const <int, Map<String, int>>{},
              maxLevel,
            ),
            energyCostByLevel: _intLevels(
              item?['energyCostByLevel'],
              fallback?.energyCostByLevel ?? const <int, int>{},
              maxLevel,
            ),
            maxLevel: maxLevel,
          );
        }(),
    },
    researchPatterns: <String, PTibugResearchPatternConfig>{
      for (final id in <String>{
        ...base.researchPatterns.keys,
        ...?rawResearchPatterns?.keys.where(
          (key) => key != 'ptibug-trait-eclaireur',
        ),
      })
        id: _researchPattern(
          id,
          _map(rawResearchPatterns?[id]),
          base.researchPatterns[id],
        ),
    },
    biomes: <PTibugBiome, PTibugBiomeConfig>{
      for (final entry in base.biomes.entries)
        entry.key: _biomeConfig(
          _map(rawBiomes?[entry.key.name]),
          entry.value,
        ),
    },
    dataQualityValues: <PTibugDataQuality, int>{
      for (final quality in PTibugDataQuality.values)
        quality: _int(
          rawQualityValues?[quality.name],
          base.dataQualityValues[quality] ?? 1,
        ),
    },
    dataQualityWeights: <PTibugDataQuality, int>{
      for (final quality in PTibugDataQuality.values)
        quality: _int(
          rawQualityWeights?[quality.name],
          base.dataQualityWeights[quality] ?? 0,
        ),
    },
    baseCellChancePercent: _int(
      raw['baseCellChancePercent'],
      base.baseCellChancePercent,
    ),
    cellChanceByOrdinal: _levelMap(
      raw['cellChanceByOrdinal'],
      base.cellChanceByOrdinal,
    ),
    // Neutral Cells are retired. Keep the field in the Dart model only to
    // read old remote configurations without re-enabling the feature.
    neutralCellChancePercent: 0,
    maxCellsByMission: _levelMap(
      raw['maxCellsByMission'],
      base.maxCellsByMission,
    ),
    reservoirCapacityBonusByLevel: _levelMap(
      raw['reservoirCapacityBonusByLevel'],
      base.reservoirCapacityBonusByLevel,
    ),
    wingsCycleReductionByLevel: _doubleLevelMap(
      raw['wingsCycleReductionByLevel'],
      base.wingsCycleReductionByLevel,
    ),
    clawProductionBonusByLevel: _levelMap(
      raw['clawProductionBonusByLevel'],
      base.clawProductionBonusByLevel,
    ),
    moduleFusionEnergyCost: _int(
      raw['moduleFusionEnergyCost'],
      base.moduleFusionEnergyCost,
    ),
    moduleMaxLevel: _int(raw['moduleMaxLevel'], base.moduleMaxLevel),
    capsuleEnergyCost: _int(raw['capsuleEnergyCost'], base.capsuleEnergyCost),
    moduleCraftCosts: <PTibugModuleType, Map<String, int>>{
      for (final type in PTibugModuleType.values)
        type: _resourceMap(
          rawModuleCraftCosts?[type.name],
          base.moduleCraftCosts[type] ?? const <String, int>{},
        ),
    },
    moduleCraftEnergyCosts: <PTibugModuleType, int>{
      for (final type in PTibugModuleType.values)
        type: _int(
          rawModuleCraftEnergyCosts?[type.name],
          base.moduleCraftEnergyCosts[type] ?? 0,
        ),
    },
    moduleCraftMinutes: <PTibugModuleType, int>{
      for (final type in PTibugModuleType.values)
        type: _int(
          rawModuleCraftMinutes?[type.name],
          base.moduleCraftMinutes[type] ?? 1,
        ),
    },
    cultivation: PTibugCultivationConfig(
      armatureMinutes: _int(
          rawCultivation?['armatureMinutes'], base.cultivation.armatureMinutes),
      activeHours:
          _int(rawCultivation?['activeHours'], base.cultivation.activeHours),
      tankSlotsPerNurseryLevel: _int(
          rawCultivation?['tankSlotsPerNurseryLevel'],
          base.cultivation.tankSlotsPerNurseryLevel),
      tankConstructionCost: _resourceMap(
          rawCultivation?['tankConstructionCost'],
          base.cultivation.tankConstructionCost),
      tankConstructionBioBatteries: _int(
          rawCultivation?['tankConstructionBioBatteries'],
          base.cultivation.tankConstructionBioBatteries),
      tankConstructionMinutes: _int(rawCultivation?['tankConstructionMinutes'],
          base.cultivation.tankConstructionMinutes),
      targetAutonomyHours: _int(rawCultivation?['targetAutonomyHours'],
          base.cultivation.targetAutonomyHours),
      energyPerActiveHour: <PTibugSpecies, double>{
        for (final species in PTibugSpecies.values)
          species: _double(
              _map(rawCultivation?['energyPerActiveHour'])?[species.name],
              base.cultivation.energyPerActiveHour[species] ?? 1),
      },
      organicPerActiveHour: <PTibugSpecies, double>{
        for (final species in PTibugSpecies.values)
          species: _double(
              _map(rawCultivation?['organicPerActiveHour'])?[species.name],
              base.cultivation.organicPerActiveHour[species] ?? 0),
      },
      mineralPerActiveHour: <PTibugSpecies, double>{
        for (final species in PTibugSpecies.values)
          species: _double(
              _map(rawCultivation?['mineralPerActiveHour'])?[species.name],
              base.cultivation.mineralPerActiveHour[species] ?? 0),
      },
      criticalAutonomyMinutes: _int(rawCultivation?['criticalAutonomyMinutes'],
          base.cultivation.criticalAutonomyMinutes),
      tapBonusMinutes: _int(
          rawCultivation?['tapBonusMinutes'], base.cultivation.tapBonusMinutes),
      tapMaximumPerDay: _int(rawCultivation?['tapMaximumPerDay'],
          base.cultivation.tapMaximumPerDay),
      tapMinimumDelayHours: _int(rawCultivation?['tapMinimumDelayHours'],
          base.cultivation.tapMinimumDelayHours),
      traitInfusionHours: _int(rawCultivation?['traitInfusionHours'],
          base.cultivation.traitInfusionHours),
      evolutionHours: _int(
          rawCultivation?['evolutionHours'], base.cultivation.evolutionHours),
      traitMaterialCostCoefficient: _double(
          rawCultivation?['traitMaterialCostCoefficient'],
          base.cultivation.traitMaterialCostCoefficient),
      traitEnergyCostCoefficient: _double(
          rawCultivation?['traitEnergyCostCoefficient'],
          base.cultivation.traitEnergyCostCoefficient),
      evolutionMaterialCostCoefficient: _double(
          rawCultivation?['evolutionMaterialCostCoefficient'],
          base.cultivation.evolutionMaterialCostCoefficient),
      evolutionEnergyCostCoefficient: _double(
          rawCultivation?['evolutionEnergyCostCoefficient'],
          base.cultivation.evolutionEnergyCostCoefficient),
      traitTapBonusMinutes: _int(rawCultivation?['traitTapBonusMinutes'],
          base.cultivation.traitTapBonusMinutes),
      evolutionTapBonusMinutes: _int(
          rawCultivation?['evolutionTapBonusMinutes'],
          base.cultivation.evolutionTapBonusMinutes),
      evolutionDataCost: _dataFamilyMap(rawCultivation?['evolutionDataCost'],
          base.cultivation.evolutionDataCost),
    ),
    valuation: PTibugValuationConfig(
      configVersion: _int(
        rawValuation?['configVersion'],
        base.valuation.configVersion,
      ),
      minimumNameLength: _int(
        rawValuation?['minimumNameLength'],
        base.valuation.minimumNameLength,
      ),
      maximumNameLength: _int(
        rawValuation?['maximumNameLength'],
        base.valuation.maximumNameLength,
      ),
      baseValueBySpecies: <PTibugSpecies, int>{
        for (final species in PTibugSpecies.values)
          species: _int(
            _map(rawValuation?['baseValueBySpecies'])?[species.name],
            base.valuation.baseValueFor(species),
          ),
      },
      cumulativeLevelValues: _levelMap(
        rawValuation?['cumulativeLevelValues'],
        base.valuation.cumulativeLevelValues,
      ),
      traitRankValues: _levelMap(
        rawValuation?['traitRankValues'],
        base.valuation.traitRankValues,
      ),
      moduleValues: <PTibugModuleType, int>{
        for (final type in PTibugModuleType.values)
          type: _int(
            _map(rawValuation?['moduleValues'])?[type.name],
            base.valuation.moduleValueFor(type),
          ),
      },
      customerRequestCoefficient: _double(
        rawValuation?['customerRequestCoefficient'],
        base.valuation.customerRequestCoefficient,
      ),
      sourcierContractCoefficient: _double(
        rawValuation?['sourcierContractCoefficient'],
        base.valuation.sourcierContractCoefficient,
      ),
      minimumPayment: _int(
        rawValuation?['minimumPayment'],
        base.valuation.minimumPayment,
      ),
    ),
    nurseryReserveCapacity: _int(
      raw['nurseryReserveCapacity'],
      base.nurseryReserveCapacity,
    ),
    sourcierCellPricePerDataValue: _int(
      raw['sourcierCellPricePerDataValue'],
      base.sourcierCellPricePerDataValue,
    ),
    territory: PTibugTerritoryConfig(
      nurseryMaximumLevel: _int(
        rawTerritory?['nurseryMaximumLevel'],
        base.territory.nurseryMaximumLevel,
      ),
      refugeMaximumLevel: _int(
        rawTerritory?['refugeMaximumLevel'],
        base.territory.refugeMaximumLevel,
      ),
      capacityPerLevel: _int(
        rawTerritory?['capacityPerLevel'],
        base.territory.capacityPerLevel,
      ),
      organicAmount:
          _int(rawTerritory?['organicAmount'], base.territory.organicAmount),
      organicEveryHours: _int(
          rawTerritory?['organicEveryHours'], base.territory.organicEveryHours),
      mineralAmount:
          _int(rawTerritory?['mineralAmount'], base.territory.mineralAmount),
      mineralEveryHours: _int(
          rawTerritory?['mineralEveryHours'], base.territory.mineralEveryHours),
      energyAmount:
          _int(rawTerritory?['energyAmount'], base.territory.energyAmount),
      energyEveryHours: _int(
          rawTerritory?['energyEveryHours'], base.territory.energyEveryHours),
      moduleEnergyAmount: _int(rawTerritory?['moduleEnergyAmount'],
          base.territory.moduleEnergyAmount),
      moduleEnergyEveryHours: _int(rawTerritory?['moduleEnergyEveryHours'],
          base.territory.moduleEnergyEveryHours),
      nurseryEnergyAmount: _int(rawTerritory?['nurseryEnergyAmount'],
          base.territory.nurseryEnergyAmount),
      nurseryEnergyEveryHours: _int(rawTerritory?['nurseryEnergyEveryHours'],
          base.territory.nurseryEnergyEveryHours),
      refugeEnergyAmount: _int(rawTerritory?['refugeEnergyAmount'],
          base.territory.refugeEnergyAmount),
      refugeEnergyEveryHours: _int(rawTerritory?['refugeEnergyEveryHours'],
          base.territory.refugeEnergyEveryHours),
      dataCellStorageCapacity: _int(rawTerritory?['dataCellStorageCapacity'],
          base.territory.dataCellStorageCapacity),
      refugeConstructionOrganic: _int(
          rawTerritory?['refugeConstructionOrganic'],
          base.territory.refugeConstructionOrganic),
      refugeConstructionMineral: _int(
          rawTerritory?['refugeConstructionMineral'],
          base.territory.refugeConstructionMineral),
      refugeConstructionBioBatteries: _int(
          rawTerritory?['refugeConstructionBioBatteries'],
          base.territory.refugeConstructionBioBatteries),
      refugeConstructionMinutes: _int(
          rawTerritory?['refugeConstructionMinutes'],
          base.territory.refugeConstructionMinutes),
      refugeUpgradeOrganicByLevel: _levelMap(
          rawTerritory?['refugeUpgradeOrganicByLevel'],
          base.territory.refugeUpgradeOrganicByLevel),
      refugeUpgradeMineralByLevel: _levelMap(
          rawTerritory?['refugeUpgradeMineralByLevel'],
          base.territory.refugeUpgradeMineralByLevel),
      refugeUpgradeBioBatteriesByLevel: _levelMap(
          rawTerritory?['refugeUpgradeBioBatteriesByLevel'],
          base.territory.refugeUpgradeBioBatteriesByLevel),
      refugeUpgradeMinutes: _int(rawTerritory?['refugeUpgradeMinutes'],
          base.territory.refugeUpgradeMinutes),
    ),
    progression: PTibugProgressionConfig(
      maximumLevel:
          _int(rawProgression?['maximumLevel'], base.progression.maximumLevel),
      xpRequiredByLevel: _levelMap(rawProgression?['xpRequiredByLevel'],
          base.progression.xpRequiredByLevel),
      yieldBonusPerLevel: _double(rawProgression?['yieldBonusPerLevel'],
          base.progression.yieldBonusPerLevel),
      baseEnergyPerDay: _int(rawProgression?['baseEnergyPerDay'],
          base.progression.baseEnergyPerDay),
      energyReductionPerLevel: _int(rawProgression?['energyReductionPerLevel'],
          base.progression.energyReductionPerLevel),
      minimumEnergyPerDay: _int(rawProgression?['minimumEnergyPerDay'],
          base.progression.minimumEnergyPerDay),
      renewalLevel: _int(
          rawProgression?['evolutionLevel'] ?? rawProgression?['renewalLevel'],
          base.progression.renewalLevel),
      renewalMaterialCost: _resourceMap(
          rawProgression?['evolutionMaterialCost'] ??
              rawProgression?['renewalMaterialCost'],
          base.progression.renewalMaterialCost),
      renewalEnergyCost: _int(
          rawProgression?['evolutionEnergyCost'] ??
              rawProgression?['renewalEnergyCost'],
          base.progression.renewalEnergyCost),
      renewalBioBatteryCost: _int(
          rawProgression?['evolutionBioBatteryCost'] ??
              rawProgression?['renewalBioBatteryCost'],
          base.progression.renewalBioBatteryCost),
      renewalDurationMinutes: _int(
          rawProgression?['evolutionDurationMinutes'] ??
              rawProgression?['renewalDurationMinutes'],
          base.progression.renewalDurationMinutes),
      maximumRenewals: _int(
          rawProgression?['maximumEvolutions'] ??
              rawProgression?['maximumRenewals'],
          base.progression.maximumRenewals),
    ),
    moduleCapacity: PTibugModuleCapacityConfig(
      initialCapacity: _int(rawModuleCapacity?['initialCapacity'],
          base.moduleCapacity.initialCapacity),
      maximumUpgrades: _int(rawModuleCapacity?['maximumUpgrades'],
          base.moduleCapacity.maximumUpgrades),
      capacityPerUpgrade: _int(rawModuleCapacity?['capacityPerUpgrade'],
          base.moduleCapacity.capacityPerUpgrade),
      materialCostsByLevel: _materialCostsByLevel(
          rawModuleCapacity?['materialCostsByLevel'],
          base.moduleCapacity.materialCostsByLevel,
          base.moduleCapacity.maximumUpgrades),
      bioBatteryCostsByLevel: _intLevels(
          rawModuleCapacity?['bioBatteryCostsByLevel'],
          base.moduleCapacity.bioBatteryCostsByLevel,
          base.moduleCapacity.maximumUpgrades),
      dataCostsByLevel: _dataCostsByLevel(
          rawModuleCapacity?['dataCostsByLevel'],
          base.moduleCapacity.dataCostsByLevel,
          base.moduleCapacity.maximumUpgrades),
    ),
    weather: PTibugWeatherConfig(
      productionMalusPercent: _int(rawWeather?['productionMalusPercent'],
          base.weather.productionMalusPercent),
      sensorMaterialPenaltyPercent: _int(
          rawWeather?['sensorMaterialPenaltyPercent'],
          base.weather.sensorMaterialPenaltyPercent),
      sensorChanceByLevel: _intLevels(rawWeather?['sensorChanceByLevel'],
          base.weather.sensorChanceByLevel, 3),
      sensorPityEnabled: rawWeather?['sensorPityEnabled'] is bool
          ? rawWeather!['sensorPityEnabled'] as bool
          : base.weather.sensorPityEnabled,
      sensorPityCycleThreshold: _int(rawWeather?['sensorPityCycleThreshold'],
          base.weather.sensorPityCycleThreshold),
      stabilizerRegenerationPercentByLevel: _intLevels(
          rawWeather?['stabilizerRegenerationPercentByLevel'],
          base.weather.stabilizerRegenerationPercentByLevel,
          3),
      stabilizerMaximumPercent: _int(rawWeather?['stabilizerMaximumPercent'],
          base.weather.stabilizerMaximumPercent),
      economyOrganicReductionPercentByLevel: _intLevels(
          rawWeather?['economyOrganicReductionPercentByLevel'],
          base.weather.economyOrganicReductionPercentByLevel,
          3),
      economyEnergyReductionPercentByLevel: _intLevels(
          rawWeather?['economyEnergyReductionPercentByLevel'],
          base.weather.economyEnergyReductionPercentByLevel,
          3),
    ),
  );
}

KernelProgressReward _kernelReward(
  Map<String, dynamic>? raw,
  KernelProgressReward fallback,
) =>
    KernelProgressReward(
      trustXp: _int(raw?['trustXp'], fallback.trustXp),
      breederXp: _int(raw?['breederXp'], fallback.breederXp),
      builderXp: _int(raw?['builderXp'], fallback.builderXp),
      restorerXp: _int(raw?['restorerXp'], fallback.restorerXp),
    );

KernelProgressEventType? _kernelEvent(
  Object? value,
  KernelProgressEventType? fallback,
) =>
    KernelProgressEventType.values
        .where((event) => event.name == value)
        .firstOrNull ??
    fallback;

KernelAxis? _kernelAxis(Object? value, KernelAxis? fallback) =>
    KernelAxis.values.where((axis) => axis.name == value).firstOrNull ??
    fallback;

KernelPlanState _kernelPlanState(Object? value, KernelPlanState fallback) =>
    KernelPlanState.values.where((state) => state.name == value).firstOrNull ??
    fallback;

CampHeartConfig _campHeart(Object? value) {
  final raw = _map(value);
  final stages = raw?['stages'];
  if (stages is! List ||
      stages.length != defaultCampHeartConfig.stages.length) {
    return defaultCampHeartConfig;
  }
  return CampHeartConfig(
    communityProjects: _communityProjects(raw?['communityProjects']),
    stages: List<CampHeartStageConfig>.generate(stages.length, (index) {
      final base = defaultCampHeartConfig.stages[index];
      final item = _map(stages[index]);
      return CampHeartStageConfig(
        level: base.level,
        stage: base.stage,
        label: _string(item?['label'], base.label),
        organicRequiredForNextLevel: base.organicRequiredForNextLevel == null
            ? null
            : _int(
                item?['organicRequiredForNextLevel'] ??
                    item?['xpRequiredForNextLevel'],
                base.organicRequiredForNextLevel!,
              ),
        populationLabel: _string(
          item?['populationLabel'],
          base.populationLabel,
        ),
        populationMin: base.populationMin == null
            ? null
            : _int(item?['populationMin'], base.populationMin!),
        populationMax: base.populationMax == null
            ? null
            : _int(item?['populationMax'], base.populationMax!),
        activePtipoteComfortLimit: _int(
          item?['activePtipoteComfortLimit'],
          base.activePtipoteComfortLimit,
        ),
        refugeHappinessBonus: _int(
          item?['refugeHappinessBonus'],
          base.refugeHappinessBonus,
        ),
        localActivityModifier: _double(
          item?['localActivityModifier'],
          base.localActivityModifier,
        ),
        unlocks: base.unlocks,
        effects: base.effects,
      );
    }),
  );
}

CommunityProjectsConfig _communityProjects(Object? value) {
  final raw = _map(value);
  final fallback = defaultCampHeartConfig.communityProjects;
  if (raw == null) return fallback;
  final configuredProjects =
      raw['projects'] is List ? raw['projects'] as List : const <dynamic>[];
  final definitions = <CommunityProjectDefinition>[
    for (final base in fallback.projects)
      (() {
        final item =
            configuredProjects.whereType<Map>().cast<dynamic>().firstWhere(
                  (entry) => _string(_map(entry)?['id'], '') == base.id,
                  orElse: () => null,
                );
        final map = _map(item);
        final costs = _map(map?['materialCosts']);
        return CommunityProjectDefinition(
          id: base.id,
          label: _string(map?['label'], base.label),
          weatherType: _string(map?['weatherType'], base.weatherType),
          tier: _int(map?['tier'], base.tier),
          requiredCoreLevel:
              _int(map?['requiredCoreLevel'], base.requiredCoreLevel),
          prerequisiteId: map?['prerequisiteId'] == null
              ? base.prerequisiteId
              : _string(map?['prerequisiteId'], ''),
          materialCosts: <String, int>{
            for (final cost in base.materialCosts.entries)
              cost.key: _int(costs?[cost.key], cost.value),
          },
          requiredContributionPoints: _int(map?['requiredContributionPoints'],
              base.requiredContributionPoints),
          globalProtectionPercent: _int(
              map?['globalProtectionPercent'], base.globalProtectionPercent),
          description: _string(map?['description'], base.description),
        );
      })(),
  ];
  final stockLoss = _map(raw['stockLossPercentByIntensity']);
  return CommunityProjectsConfig(
    choicesPerCoreLevel:
        _int(raw['choicesPerCoreLevel'], fallback.choicesPerCoreLevel),
    maximumActiveProjects:
        _int(raw['maximumActiveProjects'], fallback.maximumActiveProjects),
    playerDailyContribution:
        _int(raw['playerDailyContribution'], fallback.playerDailyContribution),
    residentHappinessThreshold: _int(
        raw['residentHappinessThreshold'], fallback.residentHappinessThreshold),
    residentDailyContribution: _int(
        raw['residentDailyContribution'], fallback.residentDailyContribution),
    residentContributionCapEnabled:
        raw['residentContributionCapEnabled'] is bool
            ? raw['residentContributionCapEnabled'] as bool
            : fallback.residentContributionCapEnabled,
    residentContributionCap:
        _int(raw['residentContributionCap'], fallback.residentContributionCap),
    projects: definitions,
    protectedBatteryCapacity: _int(
        raw['protectedBatteryCapacity'], fallback.protectedBatteryCapacity),
    protectedBatteryCapacityPerUpgrade: _int(
      raw['protectedBatteryCapacityPerUpgrade'],
      fallback.protectedBatteryCapacityPerUpgrade,
    ),
    protectedBatteryUpgradeMaxLevel: _int(
      raw['protectedBatteryUpgradeMaxLevel'],
      fallback.protectedBatteryUpgradeMaxLevel,
    ),
    protectedBatteryUpgradeMineralCosts:
        raw['protectedBatteryUpgradeMineralCosts'] is List
            ? (raw['protectedBatteryUpgradeMineralCosts'] as List)
                .map((value) => _int(value, 0))
                .toList()
            : fallback.protectedBatteryUpgradeMineralCosts,
    stockLossPercentByIntensity: <String, int>{
      for (final entry in fallback.stockLossPercentByIntensity.entries)
        entry.key: _int(stockLoss?[entry.key], entry.value),
    },
  );
}

LisiereForageConfig _lisiere(Object? value) {
  final raw = _map(value);
  if (raw == null) return defaultLisiereForageConfig;
  final durations =
      raw['durations'] is List ? raw['durations'] as List : const [];
  final intensities =
      raw['intensities'] is List ? raw['intensities'] as List : const [];
  final biomes = raw['biomes'] is List ? raw['biomes'] as List : const [];
  final durationById = <String, Map<String, dynamic>>{
    for (final item in durations)
      if (_map(item) case final map?) _string(map['id'], ''): map,
  };
  final intensityById = <String, Map<String, dynamic>>{
    for (final item in intensities)
      if (_map(item) case final map?) _string(map['id'], ''): map,
  };
  final biomeById = <String, Map<String, dynamic>>{
    for (final item in biomes)
      if (_map(item) case final map?) _string(map['id'], ''): map,
  };
  final xp = _map(raw['xpGainByDuration']);
  final intensityXp = _map(raw['intensityXpMultiplier']);
  final missionTypes = _map(raw['missionTypes']);
  return LisiereForageConfig(
    forageTimeScale: _int(
      raw['forageTimeScale'],
      defaultLisiereForageConfig.forageTimeScale,
    ),
    refugeSafetyFallback: _int(
      raw['refugeSafetyFallback'],
      defaultLisiereForageConfig.refugeSafetyFallback,
    ),
    minimumMissionRisk: _int(
      raw['minimumMissionRisk'],
      defaultLisiereForageConfig.minimumMissionRisk,
    ),
    securityRiskReductionFactor: _double(
      raw['securityRiskReductionFactor'],
      defaultLisiereForageConfig.securityRiskReductionFactor,
    ),
    wasteLevelMax: _int(
      raw['wasteLevelMax'],
      defaultLisiereForageConfig.wasteLevelMax,
    ),
    wasteMultiplierPerLevel: _double(
      raw['wasteMultiplierPerLevel'],
      defaultLisiereForageConfig.wasteMultiplierPerLevel,
    ),
    wasteHoursPerLevelDepletion: _double(
      raw['wasteHoursPerLevelDepletion'],
      defaultLisiereForageConfig.wasteHoursPerLevelDepletion,
    ),
    organicBonusAtZeroWaste: _double(
      raw['organicBonusAtZeroWaste'],
      defaultLisiereForageConfig.organicBonusAtZeroWaste,
    ),
    inventorySlotLimit: _int(
      raw['inventorySlotLimit'],
      defaultLisiereForageConfig.inventorySlotLimit,
    ),
    inventoryStackLimit: _int(
      raw['inventoryStackLimit'],
      defaultLisiereForageConfig.inventoryStackLimit,
    ),
    xpGainByDuration: {
      for (final key in ForageDuration.values)
        key: _int(
          xp?[key.name],
          defaultLisiereForageConfig.xpGainByDuration[key]!,
        ),
    },
    intensityXpMultiplier: {
      for (final key in ForageIntensity.values)
        key: _double(
          intensityXp?[key.name],
          defaultLisiereForageConfig.intensityXpMultiplier[key]!,
        ),
    },
    durations: {
      for (final key in ForageDuration.values)
        key: _duration(key, durationById[key.name]),
    },
    intensities: {
      for (final key in ForageIntensity.values)
        key: _intensity(key, intensityById[key.name]),
    },
    biomes: {
      for (final key in ForageBiome.values)
        key: _biome(key, biomeById[key.name]),
    },
    biomass: _biomass(_map(raw['biomass'])),
    territoryBuildings: _territoryBuildings(_map(raw['territoryBuildings'])),
    myceliumExploration: _myceliumExploration(_map(raw['myceliumExploration'])),
    missionTypes: <ForageMissionType, ForageMissionTypeConfig>{
      for (final type in ForageMissionType.values)
        type: () {
          final base = defaultLisiereForageConfig.missionTypes[type]!;
          final item = _map(missionTypes?[type.name]);
          return ForageMissionTypeConfig(
            label: _string(item?['label'], base.label),
            vigorMultiplier:
                _double(item?['vigorMultiplier'], base.vigorMultiplier),
            cellChanceMultiplier: _double(
                item?['cellChanceMultiplier'], base.cellChanceMultiplier),
            maximumCellsMultiplier: _double(
                item?['maximumCellsMultiplier'], base.maximumCellsMultiplier),
            wastePerHour: _int(item?['wastePerHour'], base.wastePerHour),
          );
        }(),
    },
  );
}

LisiereTerritoryBuildingsConfig _territoryBuildings(Map<String, dynamic>? raw) {
  final base = defaultLisiereForageConfig.territoryBuildings;
  final bio = _map(raw?['biofermenter']);
  final baseBio = base.biofermenter;
  final perLevel = _map(bio?['passiveOrganicPerDayByLevel']);
  final construct = _map(bio?['constructionCost']);
  final upgrades = _map(bio?['upgradeCosts']);
  final forest = _map(bio?['edibleForest']);
  final network = _map(bio?['mycelialNetwork']);
  final calcium = _map(bio?['calciumBasin']);
  final scarabe = _map(bio?['futureScarabeHook']);
  final lithoculture = _map(bio?['lithoculture']);
  final durations = _map(bio?['constructionMinutesByLevel']);
  return LisiereTerritoryBuildingsConfig(
    slotsPerZone: _int(raw?['slotsPerZone'], base.slotsPerZone),
    biofermenter: BiofermenterConfig(
      passiveOrganicPerDayByLevel: <int, double>{
        for (var level = 1; level <= 4; level++)
          level: _double(
              perLevel?['$level'], baseBio.passiveOrganicPerDayByLevel[level]!)
      },
      constructionCost: <String, int>{
        for (final entry in baseBio.constructionCost.entries)
          entry.key: _int(construct?[entry.key], entry.value)
      },
      upgradeCosts: <int, Map<String, int>>{
        for (final entry in baseBio.upgradeCosts.entries)
          entry.key: <String, int>{
            for (final cost in entry.value.entries)
              cost.key:
                  _int(_map(upgrades?['${entry.key}'])?[cost.key], cost.value)
          }
      },
      passiveProductionMultiplier: _double(bio?['passiveProductionMultiplier'],
          baseBio.passiveProductionMultiplier),
      vatCount: _int(bio?['vatCount'], baseBio.vatCount),
      vatEfficiencyMultiplier: _double(
          bio?['vatEfficiencyMultiplier'], baseBio.vatEfficiencyMultiplier),
      lithocultureMineralPerCycle: _int(
        lithoculture?['mineralPerCycle'],
        baseBio.lithocultureMineralPerCycle,
      ),
      lithocultureOrganicPerCycle: _int(
        lithoculture?['organicPerCycle'],
        baseBio.lithocultureOrganicPerCycle,
      ),
      lithocultureCycleMinutes: _int(
        lithoculture?['cycleMinutes'],
        baseBio.lithocultureCycleMinutes,
      ),
      normalMineralPerOrganic: _int(
          bio?['normalMineralPerOrganic'], baseBio.normalMineralPerOrganic),
      mineralBasinMineralPerOrganic: _int(bio?['mineralBasinMineralPerOrganic'],
          baseBio.mineralBasinMineralPerOrganic),
      wasteCanReplaceMineral: bio?['wasteCanReplaceMineral'] is bool
          ? bio!['wasteCanReplaceMineral'] as bool
          : baseBio.wasteCanReplaceMineral,
      mineralEquivalentPerWaste: _double(
          bio?['mineralEquivalentPerWaste'], baseBio.mineralEquivalentPerWaste),
      maxWasteSharePerBatch:
          _double(bio?['maxWasteSharePerBatch'], baseBio.maxWasteSharePerBatch),
      edibleForestEnabled: forest?['enabled'] is bool
          ? forest!['enabled'] as bool
          : baseBio.edibleForestEnabled,
      edibleForestCost: <String, int>{
        for (final entry in baseBio.edibleForestCost.entries)
          entry.key: _int(_map(forest?['cost'])?[entry.key], entry.value),
      },
      pollinatorTraitId:
          _string(forest?['pollinatorTraitId'], baseBio.pollinatorTraitId),
      bonusPerPollinator:
          _double(forest?['bonusPerPollinator'], baseBio.bonusPerPollinator),
      maxPollinatorsCounted:
          _int(forest?['maxPollinatorsCounted'], baseBio.maxPollinatorsCounted),
      futureScarabeHookEnabled: scarabe?['enabled'] is bool
          ? scarabe!['enabled'] as bool
          : baseBio.futureScarabeHookEnabled,
      futureScarabeMineralPerOrganic: _int(
          scarabe?['mineralToOrganicConversionRate'],
          baseBio.futureScarabeMineralPerOrganic),
      constructionMinutesByLevel: <int, int>{
        for (var level = 1; level <= 4; level++)
          level: _int(
              durations?['$level'], baseBio.constructionMinutesByLevel[level]!)
      },
      edibleForestConstructionMinutes: _int(forest?['constructionMinutes'],
          baseBio.edibleForestConstructionMinutes),
      mycelialNetworkEnabled: network?['enabled'] is bool
          ? network!['enabled'] as bool
          : baseBio.mycelialNetworkEnabled,
      mycelialNetworkCost: <String, int>{
        for (final entry in baseBio.mycelialNetworkCost.entries)
          entry.key: _int(_map(network?['cost'])?[entry.key], entry.value),
      },
      mycelialNetworkConstructionMinutes: _int(
        network?['constructionMinutes'],
        baseBio.mycelialNetworkConstructionMinutes,
      ),
      baseMyceliumPerDay: _double(
        network?['baseMyceliumPerDay'],
        baseBio.baseMyceliumPerDay,
      ),
      myceliumBiomeMultipliers: <MyceliumRichness, double>{
        for (final richness in MyceliumRichness.values)
          richness: _double(
            _map(network?['biomeMultipliers'])?[richness.name],
            baseBio.myceliumBiomeMultipliers[richness]!,
          ),
      },
      mycelialTraitId:
          _string(network?['mycelialTraitId'], baseBio.mycelialTraitId),
      mycelialTraitBonusPerPTibug: _double(
        network?['mycelialTraitBonusPerPTibug'],
        baseBio.mycelialTraitBonusPerPTibug,
      ),
      maxMycelialPTibugsCounted: _int(
        network?['maxMycelialPTibugsCounted'],
        baseBio.maxMycelialPTibugsCounted,
      ),
      calciumBasinEnabled: calcium?['enabled'] is bool
          ? calcium!['enabled'] as bool
          : baseBio.calciumBasinEnabled,
      calciumBasinCost: <String, int>{
        for (final entry in baseBio.calciumBasinCost.entries)
          entry.key: _int(_map(calcium?['cost'])?[entry.key], entry.value),
      },
      calciumBasinConstructionMinutes: _int(
        calcium?['constructionMinutes'],
        baseBio.calciumBasinConstructionMinutes,
      ),
      lithocultureTankBaseCapacity: _int(
        lithoculture?['tankBaseCapacity'],
        baseBio.lithocultureTankBaseCapacity,
      ),
      lithocultureTankCapacityPerLevel: _int(
        lithoculture?['tankCapacityPerLevel'],
        baseBio.lithocultureTankCapacityPerLevel,
      ),
      calciumOrganicBaseCapacity: _int(
          calcium?['organicBaseCapacity'], baseBio.calciumOrganicBaseCapacity),
      calciumOrganicCapacityPerLevel: _int(
        calcium?['organicCapacityPerLevel'],
        baseBio.calciumOrganicCapacityPerLevel,
      ),
      calciumWaterBaseCapacity:
          _int(calcium?['waterBaseCapacity'], baseBio.calciumWaterBaseCapacity),
      calciumWaterCapacityPerLevel: _int(
        calcium?['waterCapacityPerLevel'],
        baseBio.calciumWaterCapacityPerLevel,
      ),
      calciumMineralReserveBaseCapacity: _int(
        calcium?['mineralReserveBaseCapacity'],
        baseBio.calciumMineralReserveBaseCapacity,
      ),
      calciumMineralReserveCapacityPerLevel: _int(
        calcium?['mineralReserveCapacityPerLevel'],
        baseBio.calciumMineralReserveCapacityPerLevel,
      ),
      calciumMineralPerTenStoredPerHour: _int(
        calcium?['mineralPerTenStoredPerHour'],
        baseBio.calciumMineralPerTenStoredPerHour,
      ),
      calciumOrganicPerActiveHour: _int(calcium?['organicPerActiveHour'],
          baseBio.calciumOrganicPerActiveHour),
      calciumWaterPerActiveHour: _int(
          calcium?['waterPerActiveHour'], baseBio.calciumWaterPerActiveHour),
      calciumMinerTraitBonusPerPTibug: _int(
        calcium?['minerTraitBonusPerPTibug'],
        baseBio.calciumMinerTraitBonusPerPTibug,
      ),
      calciumEligibleTraitIds: (calcium?['eligibleTraitIds'] as List?)
              ?.map((value) => '$value')
              .where((value) => value.isNotEmpty)
              .toList() ??
          baseBio.calciumEligibleTraitIds,
    ),
  );
}

MyceliumExplorationConfig _myceliumExploration(
  Map<String, dynamic>? raw,
) {
  final base = defaultLisiereForageConfig.myceliumExploration;
  final yields = _map(raw?['yieldByRichness']);
  return MyceliumExplorationConfig(
    yieldByRichness: <MyceliumRichness, int>{
      for (final richness in MyceliumRichness.values)
        richness: _int(yields?[richness.name], base.yieldByRichness[richness]!),
    },
    mycelialTypeGatherBonus: _double(
      raw?['mycelialTypeGatherBonus'],
      base.mycelialTypeGatherBonus,
    ),
  );
}

List<BiomassTierConfig> _biomassTiers(
  Object? value,
  List<BiomassTierConfig> fallback,
) {
  final raw = value is List ? value : null;
  if (raw == null) return fallback;
  final tiers = raw
      .map(_map)
      .whereType<Map<String, dynamic>>()
      .map(
        (item) => BiomassTierConfig(
          minimumPercent: _int(item['minimumPercent'], 0),
          maximumPercent: _int(item['maximumPercent'], 100),
          multiplier: _double(item['multiplier'], 1),
        ),
      )
      .toList(growable: false);
  return tiers.isEmpty ? fallback : tiers;
}

List<BiomassVisualStateConfig> _biomassVisualStates(
  Object? value,
  List<BiomassVisualStateConfig> fallback,
) {
  final raw = value is List ? value : null;
  if (raw == null) return fallback;
  final states = raw
      .map(_map)
      .whereType<Map<String, dynamic>>()
      .map(
        (item) => BiomassVisualStateConfig(
          minimumPercent: _int(item['minimumPercent'], 0),
          maximumPercent: _int(item['maximumPercent'], 100),
          label: _string(item['label'], ''),
          icon: _string(item['icon'], ''),
        ),
      )
      .where((item) => item.label.isNotEmpty && item.icon.isNotEmpty)
      .toList(growable: false);
  return states.isEmpty ? fallback : states;
}

BiomassConfig _biomass(Map<String, dynamic>? raw) {
  final base = defaultLisiereForageConfig.biomass;
  if (raw == null) return base;
  final consumption = _map(raw['missionConsumptionByIntensity']);
  return BiomassConfig(
    maximumPercent: _int(raw['maximumPercent'], base.maximumPercent),
    missionConsumptionByIntensity: <ForageIntensity, int>{
      for (final intensity in ForageIntensity.values)
        intensity: _int(
          consumption?[intensity.name],
          base.missionConsumptionByIntensity[intensity] ?? 0,
        ),
    },
    resourceYieldTiers: _biomassTiers(
      raw['resourceYieldTiers'],
      base.resourceYieldTiers,
    ),
    recoveryHoursPerPoint: _double(
      raw['recoveryHoursPerPoint'],
      base.recoveryHoursPerPoint,
    ),
    recoveryTiers: _biomassTiers(raw['recoveryTiers'], base.recoveryTiers),
    revitalizeBaseOrganicCost: _int(
      raw['revitalizeBaseOrganicCost'],
      base.revitalizeBaseOrganicCost,
    ),
    revitalizeBaseMineralCost: _int(
      raw['revitalizeBaseMineralCost'],
      base.revitalizeBaseMineralCost,
    ),
    revitalizeBaseMyceliumCost: _int(
      raw['revitalizeBaseMyceliumCost'],
      base.revitalizeBaseMyceliumCost,
    ),
    revitalizeGain: _int(raw['revitalizeGain'], base.revitalizeGain),
    revitalizeCooldownHours: _int(
      raw['revitalizeCooldownHours'],
      base.revitalizeCooldownHours,
    ),
    revitalizeCostTiers: _biomassTiers(
      raw['revitalizeCostTiers'],
      base.revitalizeCostTiers,
    ),
    ptibugYieldTiers: _biomassTiers(
      raw['ptibugYieldTiers'],
      base.ptibugYieldTiers,
    ),
    visualStates: _biomassVisualStates(
      raw['visualStates'],
      base.visualStates,
    ),
  );
}

ForageDurationConfig _duration(ForageDuration key, Map<String, dynamic>? raw) {
  final base = defaultLisiereForageConfig.durations[key]!;
  return ForageDurationConfig(
    label: _string(raw?['label'], base.label),
    theoreticalHours: _int(raw?['theoreticalHours'], base.theoreticalHours),
    baseVitalityCost: _int(raw?['baseVitalityCost'], base.baseVitalityCost),
  );
}

ForageIntensityConfig _intensity(
  ForageIntensity key,
  Map<String, dynamic>? raw,
) {
  final base = defaultLisiereForageConfig.intensities[key]!;
  return ForageIntensityConfig(
    label: _string(raw?['label'], base.label),
    rewardMultiplier: _double(raw?['rewardMultiplier'], base.rewardMultiplier),
    timeMultiplier: _double(raw?['timeMultiplier'], base.timeMultiplier),
    vitalityMultiplier: _double(
      raw?['vitalityMultiplier'],
      base.vitalityMultiplier,
    ),
    riskModifierPercent: _int(
      raw?['riskModifierPercent'],
      base.riskModifierPercent,
    ),
    zoneFatigueLabel: base.zoneFatigueLabel,
  );
}

ForageBiomeConfig _biome(ForageBiome key, Map<String, dynamic>? raw) {
  final base = defaultLisiereForageConfig.biomes[key]!;
  return ForageBiomeConfig(
    // Biome IDs are persistent. Their display labels are canonicalized here
    // so a legacy Dashboard document cannot revive an obsolete name in-app.
    label: base.label,
    tendency: base.tendency,
    baseRewards: _resourceMap(raw?['rewards'], base.baseRewards),
    baseRiskPercent: _int(raw?['baseRiskPercent'], base.baseRiskPercent),
    restorationLevel: _int(raw?['restorationLevel'], base.restorationLevel),
    restorationStage: _string(raw?['restorationStage'], base.restorationStage),
    organicRewardModifier: base.organicRewardModifier,
    mineralRewardModifier: base.mineralRewardModifier,
    riskModifier: base.riskModifier,
    linkedPtipoteRefugeBonus: base.linkedPtipoteRefugeBonus,
    wasteBaseGain: _int(raw?['wasteBaseGain'], base.wasteBaseGain),
    wasteHoursPerLevelRegeneration: _double(
      raw?['wasteHoursPerLevelRegeneration'],
      base.wasteHoursPerLevelRegeneration,
    ),
    myceliumRichness: MyceliumRichness.values.firstWhere(
      (item) =>
          item.name ==
          _string(raw?['myceliumRichness'], base.myceliumRichness.name),
      orElse: () => base.myceliumRichness,
    ),
    hazards: base.hazards,
  );
}

SecurityTowerConfig _tower(Object? value) {
  final raw = _map(value);
  if (raw == null) return defaultSecurityTowerConfig;
  final slots = _map(raw['slotsByLevel']);
  const base = defaultSecurityTowerConfig;
  return SecurityTowerConfig(
    requiredCampHeartLevel: _int(
      raw['requiredCampHeartLevel'],
      base.requiredCampHeartLevel,
    ),
    constructionCostOrganic: _int(
      raw['constructionCostOrganic'],
      base.constructionCostOrganic,
    ),
    constructionCostMineral: _int(
      raw['constructionCostMineral'],
      base.constructionCostMineral,
    ),
    maxSecurity: _int(raw['maxSecurity'], base.maxSecurity),
    initialSecurity: _int(raw['initialSecurity'], base.initialSecurity),
    securityGainPerTick: _int(
      raw['securityGainPerTick'],
      base.securityGainPerTick,
    ),
    tickMinutes: _int(raw['tickMinutes'], base.tickMinutes),
    vitalityCostPerTick: _int(
      raw['vitalityCostPerTick'],
      base.vitalityCostPerTick,
    ),
    securityDecayPerTick: _int(
      raw['securityDecayPerTick'],
      base.securityDecayPerTick,
    ),
    level1Slots: _int(slots?['1'], base.level1Slots),
    level2Slots: _int(slots?['2'], base.level2Slots),
    level3Slots: _int(slots?['3'], base.level3Slots),
    manualRechargeSecurityGain: _int(
      raw['manualRechargeSecurityGain'],
      base.manualRechargeSecurityGain,
    ),
    manualRechargeCooldownMinutes: _int(
      raw['manualRechargeCooldownMinutes'],
      base.manualRechargeCooldownMinutes,
    ),
    securityGainBonusPerLevel: _int(
      raw['securityGainBonusPerLevel'],
      base.securityGainBonusPerLevel,
    ),
    manualRechargeBonusPerLevel: _int(
      raw['manualRechargeBonusPerLevel'],
      base.manualRechargeBonusPerLevel,
    ),
  );
}

TowerOperationsConfig _towerOperations(Object? value) {
  final raw = _map(value);
  if (raw == null) return defaultTowerOperationsConfig;
  const base = defaultTowerOperationsConfig;
  final bands =
      raw['wellbeingBands'] is List ? raw['wellbeingBands'] as List : const [];
  final weather =
      raw['weatherEvents'] is List ? raw['weatherEvents'] as List : const [];
  final globalWeather = _globalWeather(
    raw['globalWeather'],
    base.globalWeather,
  );
  final buildingViability = _buildingViability(
    raw['buildingViability'],
    base.buildingViability,
  );
  return TowerOperationsConfig(
    biomeRevealSecurityThreshold: _int(
      raw['biomeRevealSecurityThreshold'],
      base.biomeRevealSecurityThreshold,
    ),
    explorationDurationMinutes: _int(
      raw['explorationDurationMinutes'],
      base.explorationDurationMinutes,
    ),
    localSecurityMaximum: _int(
      raw['localSecurityMaximum'],
      base.localSecurityMaximum,
    ),
    localSecurityHoursForFullPatrol: _int(
      raw['localSecurityHoursForFullPatrol'],
      base.localSecurityHoursForFullPatrol,
    ),
    maximumLocalRiskReductionPercent: _int(
      raw['maximumLocalRiskReductionPercent'],
      base.maximumLocalRiskReductionPercent,
    ),
    localSecurityDecayPerHour: _int(
      raw['localSecurityDecayPerHour'],
      base.localSecurityDecayPerHour,
    ),
    localSecurityRecentMissionHours: _int(
      raw['localSecurityRecentMissionHours'],
      base.localSecurityRecentMissionHours,
    ),
    merchantPresenceHours: _int(
      raw['merchantPresenceHours'],
      base.merchantPresenceHours,
    ),
    merchantMaxVisitsPerDay: _int(
      raw['merchantMaxVisitsPerDay'],
      base.merchantMaxVisitsPerDay,
    ),
    merchantMinimumGapHours: _int(
      raw['merchantMinimumGapHours'],
      base.merchantMinimumGapHours,
    ),
    merchantRandomGapAdditionalHours: _int(
      raw['merchantRandomGapAdditionalHours'],
      base.merchantRandomGapAdditionalHours,
    ),
    merchantCallBatteryCost: _int(
      raw['merchantCallBatteryCost'],
      base.merchantCallBatteryCost,
    ),
    merchantCallMinimumWaitMinutes: _int(
      raw['merchantCallMinimumWaitMinutes'],
      base.merchantCallMinimumWaitMinutes,
    ),
    merchantCallRandomWaitAdditionalMinutes: _int(
      raw['merchantCallRandomWaitAdditionalMinutes'],
      base.merchantCallRandomWaitAdditionalMinutes,
    ),
    merchantOfferPrices: _resourceMap(
      raw['merchantOfferPrices'],
      base.merchantOfferPrices,
    ),
    merchantWorkshopOfferCount: _int(
      raw['merchantWorkshopOfferCount'],
      base.merchantWorkshopOfferCount,
    ),
    merchantWorkshopMinimumQuantity: _int(
      raw['merchantWorkshopMinimumQuantity'],
      base.merchantWorkshopMinimumQuantity,
    ),
    merchantWorkshopMaximumQuantity: _int(
      raw['merchantWorkshopMaximumQuantity'],
      base.merchantWorkshopMaximumQuantity,
    ),
    maxWeatherEventsPerDay: _int(
      raw['maxWeatherEventsPerDay'],
      base.maxWeatherEventsPerDay,
    ),
    minimumWeatherIntervalMinutes: _int(
      raw['minimumWeatherIntervalMinutes'],
      base.minimumWeatherIntervalMinutes,
    ),
    manualWeatherTriggerId: _string(
      raw['manualWeatherTriggerId'],
      base.manualWeatherTriggerId,
    ),
    manualWeatherTriggerType: TowerWeatherType.values
        .where((type) => type.name == raw['manualWeatherTriggerType'])
        .firstOrNull,
    globalWeather: globalWeather,
    buildingViability: buildingViability,
    research: _towerResearch(raw['research'], base.research),
    wellbeingBands: List<SecurityWellbeingBand>.generate(
      base.wellbeingBands.length,
      (index) {
        final item = index < bands.length ? _map(bands[index]) : null;
        final fallback = base.wellbeingBands[index];
        return SecurityWellbeingBand(
          minimumSecurity: _int(
            item?['minimumSecurity'],
            fallback.minimumSecurity,
          ),
          wellbeingModifier: _int(
            item?['wellbeingModifier'],
            fallback.wellbeingModifier,
          ),
          label: fallback.label,
        );
      },
    ),
    weatherEvents: List<TowerWeatherConfig>.generate(
      base.weatherEvents.length,
      (index) {
        final item = index < weather.length ? _map(weather[index]) : null;
        final fallback = base.weatherEvents[index];
        return TowerWeatherConfig(
          type: fallback.type,
          label: _string(item?['label'], fallback.label),
          description: _string(item?['description'], fallback.description),
          announcement: _string(item?['announcement'], fallback.announcement),
          durationMinutes: _int(
            item?['durationMinutes'],
            fallback.durationMinutes,
          ),
          warningMinutes: _int(
            item?['warningMinutes'],
            fallback.warningMinutes,
          ),
          preparationItem: _string(
            item?['preparationItem'],
            fallback.preparationItem,
          ),
          preparationAmount: _int(
            item?['preparationAmount'],
            fallback.preparationAmount,
          ),
          occurrenceWeight: _int(
            item?['occurrenceWeight'],
            fallback.occurrenceWeight,
          ),
        );
      },
    ),
  );
}

BuildingViabilityConfig _buildingViability(
  Object? value,
  BuildingViabilityConfig base,
) {
  final raw = _map(value);
  if (raw == null) return base;
  final damage = _map(raw['damageByWeatherAndIntensity']);
  return BuildingViabilityConfig(
    maximumViability: _int(raw['maximumViability'], base.maximumViability),
    initialViability: _int(raw['initialViability'], base.initialViability),
    degradedThreshold: _int(raw['degradedThreshold'], base.degradedThreshold),
    restartViability: _int(raw['restartViability'], base.restartViability),
    degradedCraftTimePercent:
        _int(raw['degradedCraftTimePercent'], base.degradedCraftTimePercent),
    degradedCraftCostPercent:
        _int(raw['degradedCraftCostPercent'], base.degradedCraftCostPercent),
    degradedProductionPercent:
        _int(raw['degradedProductionPercent'], base.degradedProductionPercent),
    repairGain: _int(raw['repairGain'], base.repairGain),
    repairOrganicCost: _int(raw['repairOrganicCost'], base.repairOrganicCost),
    repairMineralCost: _int(raw['repairMineralCost'], base.repairMineralCost),
    repairCostsByBuildingLevel: <int, Map<String, int>>{
      for (final entry in base.repairCostsByBuildingLevel.entries)
        entry.key: <String, int>{
          for (final cost in entry.value.entries)
            cost.key: _int(
              _map(_map(raw['repairCostsByBuildingLevel'])?['${entry.key}'])?[
                  cost.key],
              cost.value,
            ),
        },
    },
    restartOrganicCost:
        _int(raw['restartOrganicCost'], base.restartOrganicCost),
    restartMineralCost:
        _int(raw['restartMineralCost'], base.restartMineralCost),
    restartBioBatteryCost:
        _int(raw['restartBioBatteryCost'], base.restartBioBatteryCost),
    slotsPerLevel: _int(raw['slotsPerLevel'], base.slotsPerLevel),
    protectionCapPercent:
        _int(raw['protectionCapPercent'], base.protectionCapPercent),
    protectionReductionPercents: (raw['protectionReductionPercents'] as List? ??
            base.protectionReductionPercents)
        .map((entry) => _int(entry, 0))
        .toList(),
    damageByWeatherAndIntensity: <TowerWeatherType,
        Map<GlobalWeatherIntensity, int>>{
      for (final type in TowerWeatherType.values)
        type: <GlobalWeatherIntensity, int>{
          for (final intensity in GlobalWeatherIntensity.values)
            intensity: _int(
              _map(damage?[type.name])?[intensity.name],
              base.damageFor(type, intensity),
            ),
        },
    },
    repairMiniGames:
        _repairMiniGames(raw['repairMiniGames'], base.repairMiniGames),
  );
}

RepairMiniGamesConfig _repairMiniGames(
    Object? value, RepairMiniGamesConfig base) {
  final raw = _map(value);
  if (raw == null) return base;
  Map<int, Map<String, int>> table(
      String key, Map<int, Map<String, int>> fallback) {
    final source = _map(raw[key]);
    return <int, Map<String, int>>{
      for (final entry in fallback.entries)
        entry.key: <String, int>{
          for (final item in entry.value.entries)
            item.key:
                _int(_map(source?['${entry.key}'])?[item.key], item.value),
        },
    };
  }

  return RepairMiniGamesConfig(
    enabled: raw['enabled'] is bool ? raw['enabled'] as bool : base.enabled,
    colorMatchWeight: _int(raw['colorMatchWeight'], base.colorMatchWeight),
    pipesWeight: _int(raw['pipesWeight'], base.pipesWeight),
    waterSortWeight: _int(raw['waterSortWeight'], base.waterSortWeight),
    retryFree:
        raw['retryFree'] is bool ? raw['retryFree'] as bool : base.retryFree,
    failurePenalty: raw['failurePenalty'] is bool
        ? raw['failurePenalty'] as bool
        : base.failurePenalty,
    timerEnabled: raw['timerEnabled'] is bool
        ? raw['timerEnabled'] as bool
        : base.timerEnabled,
    colorMatchByBuildingLevel:
        table('colorMatchByBuildingLevel', base.colorMatchByBuildingLevel),
    pipesByBuildingLevel:
        table('pipesByBuildingLevel', base.pipesByBuildingLevel),
    waterSortByBuildingLevel:
        table('waterSortByBuildingLevel', base.waterSortByBuildingLevel),
    straightWeight: _int(raw['straightWeight'], base.straightWeight),
    curveWeight: _int(raw['curveWeight'], base.curveWeight),
    teeWeight: _int(raw['teeWeight'], base.teeWeight),
  );
}

GlobalWeatherConfig _globalWeather(Object? value, GlobalWeatherConfig base) {
  final raw = _map(value);
  if (raw == null) return base;
  final intensities = _map(raw['intensities']);
  final sensitivities = _map(raw['biomeSensitivities']);
  return GlobalWeatherConfig(
    cycleMinutes: _int(raw['cycleMinutes'], base.cycleMinutes),
    forecastMinutes: _int(raw['forecastMinutes'], base.forecastMinutes),
    maximumConsecutiveAdverseEvents: _int(
        raw['maximumConsecutiveAdverseEvents'],
        base.maximumConsecutiveAdverseEvents),
    allowConsecutiveSevereEvents: _int(
        raw['allowConsecutiveSevereEvents'], base.allowConsecutiveSevereEvents),
    forcedCalmChancePercent:
        _int(raw['forcedCalmChancePercent'], base.forcedCalmChancePercent),
    maximumPTibugMalusPercent:
        _int(raw['maximumPTibugMalusPercent'], base.maximumPTibugMalusPercent),
    localImpactMultipliers: <String, double>{
      for (final entry in base.localImpactMultipliers.entries)
        entry.key: _double(
            _map(raw['localImpactMultipliers'])?[entry.key], entry.value),
    },
    intensities: <GlobalWeatherIntensity, GlobalWeatherIntensityConfig>{
      for (final intensity in GlobalWeatherIntensity.values)
        intensity: () {
          final fallback = base.intensities[intensity]!;
          final item = _map(intensities?[intensity.name]);
          return GlobalWeatherIntensityConfig(
            weight: _int(item?['weight'], fallback.weight),
            ptibugMalusPercent:
                _int(item?['ptibugMalusPercent'], fallback.ptibugMalusPercent),
            minimumAffectedBiomes: _int(
                item?['minimumAffectedBiomes'], fallback.minimumAffectedBiomes),
            maximumAffectedBiomes: _int(
                item?['maximumAffectedBiomes'], fallback.maximumAffectedBiomes),
          );
        }(),
    },
    biomeSensitivities: <String,
        Map<TowerWeatherType, GlobalWeatherBiomeSensitivity>>{
      for (final biomeEntry in base.biomeSensitivities.entries)
        biomeEntry.key: <TowerWeatherType, GlobalWeatherBiomeSensitivity>{
          for (final typeEntry in biomeEntry.value.entries)
            typeEntry.key: () {
              final fallback = typeEntry.value;
              final item = _map(
                  _map(sensitivities?[biomeEntry.key])?[typeEntry.key.name]);
              return GlobalWeatherBiomeSensitivity(
                chancePercent:
                    _int(item?['chancePercent'], fallback.chancePercent),
                impactMultiplier: _double(
                    item?['impactMultiplier'], fallback.impactMultiplier),
                immune: item?['immune'] is bool
                    ? item!['immune'] as bool
                    : fallback.immune,
                reason: _string(item?['reason'], fallback.reason),
              );
            }(),
        },
    },
  );
}

FablabConfig _fablab(Object? value) {
  final raw = _map(value);
  const b = defaultFablabConfig;
  if (raw == null) return b;
  return FablabConfig(
    constructionCostLevel1Organic: _int(
      raw['constructionCostLevel1Organic'],
      b.constructionCostLevel1Organic,
    ),
    constructionCostLevel1Mineral: _int(
      raw['constructionCostLevel1Mineral'],
      b.constructionCostLevel1Mineral,
    ),
    baseGlobalStockCapacity: _int(
      raw['baseGlobalStockCapacity'],
      b.baseGlobalStockCapacity,
    ),
    stockCapacityBonusPerFablabLevel: _int(
      raw['stockCapacityBonusPerFablabLevel'],
      b.stockCapacityBonusPerFablabLevel,
    ),
    fablabStorageByLevel:
        _levelMap(raw['fablabStorageByLevel'], b.fablabStorageByLevel),
    houseStorageByLevel:
        _levelMap(raw['houseStorageByLevel'], b.houseStorageByLevel),
    recyclerInputByLevel:
        _levelMap(raw['recyclerInputByLevel'], b.recyclerInputByLevel),
    recyclerVatOneCapacityByLevel: _levelMap(
      raw['recyclerVatOneCapacityByLevel'],
      b.recyclerVatOneCapacityByLevel,
    ),
    recyclerVatTwoCapacityByLevel: _levelMap(
      raw['recyclerVatTwoCapacityByLevel'],
      b.recyclerVatTwoCapacityByLevel,
    ),
    recyclerSpecializedMinimumOutOfTen: _int(
      raw['recyclerSpecializedMinimumOutOfTen'],
      b.recyclerSpecializedMinimumOutOfTen,
    ),
    kitchenRoomLevels: _fablabRoomLevels(
      raw['kitchenRoomLevels'],
      b.kitchenRoomLevels,
    ),
    workshopRoomLevels: _fablabRoomLevels(
      raw['workshopRoomLevels'],
      b.workshopRoomLevels,
    ),
    fablabMaxLevel: _int(raw['fablabMaxLevel'], b.fablabMaxLevel),
    cuisineMaxLevel: _int(raw['cuisineMaxLevel'], b.cuisineMaxLevel),
    atelierMaxLevel: _int(raw['atelierMaxLevel'], b.atelierMaxLevel),
    cuisineUnlockLevel: _int(raw['cuisineUnlockLevel'], b.cuisineUnlockLevel),
    atelierUnlockCampHeartLevel: _int(
      raw['atelierUnlockCampHeartLevel'],
      b.atelierUnlockCampHeartLevel,
    ),
    recyclerUnlockCampHeartLevel: _int(
      raw['recyclerUnlockCampHeartLevel'],
      b.recyclerUnlockCampHeartLevel,
    ),
    simpleMealOrganicCost: _int(
      raw['simpleMealOrganicCost'],
      b.simpleMealOrganicCost,
    ),
    simpleMealOutputAmount: _int(
      raw['simpleMealOutputAmount'],
      b.simpleMealOutputAmount,
    ),
  );
}

Map<int, FablabRoomLevelConfig> _fablabRoomLevels(
  Object? value,
  Map<int, FablabRoomLevelConfig> fallback,
) {
  final raw = _map(value);
  if (raw == null) return fallback;
  return <int, FablabRoomLevelConfig>{
    for (var level = 1; level <= 4; level++)
      level: () {
        final base = fallback[level] ?? fallback[4]!;
        final item = _map(raw['$level']);
        final quantities = item?['quantities'] is List
            ? (item!['quantities'] as List)
                .whereType<num>()
                .map((number) => number.toInt())
                .where((number) => number > 0)
                .toList()
            : base.quantities;
        return FablabRoomLevelConfig(
          workers: _int(item?['workers'], base.workers),
          manualSlots: _int(item?['manualSlots'], base.manualSlots),
          quantities: quantities.isEmpty ? base.quantities : quantities,
          recipeTier: _int(item?['recipeTier'], base.recipeTier),
          queueCapacity: _int(item?['queueCapacity'], base.queueCapacity),
          marketRestock: item?['marketRestock'] is bool
              ? item!['marketRestock'] as bool
              : base.marketRestock,
          categories: item?['categories'] is List
              ? (item!['categories'] as List).map((entry) => '$entry').toList()
              : base.categories,
        );
      }(),
  };
}

WorkshopConfig _workshop(Object? value) {
  final raw = _map(value);
  const b = defaultWorkshopConfig;
  if (raw == null) return b;
  return WorkshopConfig(
    vitalityCostPerUnit: _int(
      raw['vitalityCostPerUnit'],
      b.vitalityCostPerUnit,
    ),
    levelSpeedBonusPercent: _double(
      raw['levelSpeedBonusPercent'],
      b.levelSpeedBonusPercent,
    ),
    maxLevelSpeedBonusPercent: _double(
      raw['maxLevelSpeedBonusPercent'],
      b.maxLevelSpeedBonusPercent,
    ),
    buildingLevelSpeedBonusPercent: _double(
      raw['buildingLevelSpeedBonusPercent'],
      b.buildingLevelSpeedBonusPercent,
    ),
    maxBuildingSpeedBonusPercent: _double(
      raw['maxBuildingSpeedBonusPercent'],
      b.maxBuildingSpeedBonusPercent,
    ),
    slotsPerLevel: _int(raw['slotsPerLevel'], b.slotsPerLevel),
    ptipoteCraftTimeReductionPercent: _double(
      raw['ptipoteCraftTimeReductionPercent'],
      b.ptipoteCraftTimeReductionPercent,
    ),
  );
}

CraftConfig _craft(Object? value) {
  final raw = _map(value);
  final recipes = raw?['recipes'];
  if (recipes is! List || recipes.isEmpty) return defaultCraftConfig;
  final defaults = {
    for (final recipe in defaultCraftConfig.recipes) recipe.id: recipe,
  };
  final parsed = recipes
      .map(_map)
      .whereType<Map<String, dynamic>>()
      .map(
        (recipe) => _craftRecipe(recipe, defaults[_string(recipe['id'], '')]),
      )
      .whereType<CraftRecipe>()
      .toList();
  if (!parsed.any((recipe) => recipe.id == 'simpleMeal')) {
    return defaultCraftConfig;
  }
  // Remote dashboards created before a recipe was introduced must not hide
  // it from an existing refuge. Their configured recipes still take priority.
  final remoteIds = parsed.map((recipe) => recipe.id).toSet();
  return CraftConfig(
    recipes: <CraftRecipe>[
      ...parsed,
      ...defaultCraftConfig.recipes
          .where((recipe) => !remoteIds.contains(recipe.id)),
    ],
  );
}

CraftRecipe? _craftRecipe(Map<String, dynamic> raw, CraftRecipe? fallback) {
  final id = _string(raw['id'], fallback?.id ?? '');
  if (id.isEmpty) return null;
  final section = _string(
    raw['craftSection'],
    fallback?.craftSection.name ?? 'cuisine',
  );
  final craftSection = section == CraftSection.atelier.name
      ? CraftSection.atelier
      : CraftSection.cuisine;
  return CraftRecipe(
    id: id,
    displayName: _string(raw['displayName'], fallback?.displayName ?? id),
    craftSection: craftSection,
    ingredients: _recipeResources(
      raw['ingredients'],
      fallback?.ingredients ?? const {},
    ),
    contextIngredients: _recipeResources(
      raw['contextIngredients'],
      fallback?.contextIngredients ?? const {},
    ),
    cuisineLevel: _int(raw['cuisineLevel'], fallback?.cuisineLevel ?? 0),
    atelierLevel: _int(raw['atelierLevel'], fallback?.atelierLevel ?? 0),
    kernelTrustLevel: _int(
      raw['kernelTrustLevel'],
      fallback?.kernelTrustLevel ?? 1,
    ),
    breederLevel: _int(raw['breederLevel'], fallback?.breederLevel ?? 1),
    builderLevel: _int(raw['builderLevel'], fallback?.builderLevel ?? 1),
    restorerLevel: _int(raw['restorerLevel'], fallback?.restorerLevel ?? 1),
    resultItem: _string(raw['resultItem'], fallback?.resultItem ?? id),
    resultAmount: _int(raw['resultAmount'], fallback?.resultAmount ?? 1),
    isConsumable: raw['isConsumable'] is bool
        ? raw['isConsumable'] as bool
        : fallback?.isConsumable ?? false,
    hungerRestore: _int(raw['hungerRestore'], fallback?.hungerRestore ?? 0),
    vitalityRestore: _int(
      raw['vitalityRestore'],
      fallback?.vitalityRestore ?? 0,
    ),
    durationMinutes: _int(
      raw['durationMinutes'],
      fallback?.durationMinutes ?? 1,
    ),
    isEquipment: raw['isEquipment'] is bool
        ? raw['isEquipment'] as bool
        : fallback?.isEquipment ?? false,
    energyCost: _int(raw['energyCost'], fallback?.energyCost ?? 0),
    bioBatteryCost: _int(
      raw['bioBatteryCost'],
      fallback?.bioBatteryCost ?? 0,
    ),
    stackLimit: _int(raw['stackLimit'], fallback?.stackLimit ?? 1),
  );
}

Map<String, int> _recipeResources(Object? value, Map<String, int> fallback) {
  if (value is List) {
    final entries =
        value.map(_map).whereType<Map<String, dynamic>>().map((item) {
      final resource = _string(item['resource'], '');
      return MapEntry(resource, _int(item['amount'], 0));
    }).where((entry) => entry.key.isNotEmpty && entry.value > 0);
    final result = Map<String, int>.fromEntries(entries);
    return result.isEmpty ? fallback : result;
  }
  return _resourceMap(value, fallback);
}

MarketConfig _market(Object? value) {
  final raw = _map(value);
  const b = defaultMarketConfig;
  if (raw == null) return b;
  return MarketConfig(
    constructionCost: _resourceMap(raw['constructionCost'], b.constructionCost),
    requiredCampHeartLevel: _int(
      raw['requiredCampHeartLevel'],
      b.requiredCampHeartLevel,
    ),
    requiredPopulation: _int(raw['requiredPopulation'], b.requiredPopulation),
    saleSlotsPerLevel: _int(raw['saleSlotsPerLevel'], b.saleSlotsPerLevel),
    valuePerBioBattery: _int(raw['valuePerBioBattery'], b.valuePerBioBattery),
    vitalityCostPerTick: _int(
      raw['vitalityCostPerTick'],
      b.vitalityCostPerTick,
    ),
    vitalityTickMinutes: _int(
      raw['vitalityTickMinutes'],
      b.vitalityTickMinutes,
    ),
    requestChance: _double(raw['requestChance'], b.requestChance),
    maxActiveRequests: _int(raw['maxActiveRequests'], b.maxActiveRequests),
    requestMinReturnMinutes: _int(
      raw['requestMinReturnMinutes'],
      b.requestMinReturnMinutes,
    ),
    requestMaxReturnMinutes: _int(
      raw['requestMaxReturnMinutes'],
      b.requestMaxReturnMinutes,
    ),
    saleValues: (_resourceMap(raw['saleValues'], b.saleValues)..remove('Eau')),
    salePriceBioPiles: (_resourceMap(
      raw['salePriceBioPiles'],
      b.salePriceBioPiles,
    )..remove('Eau'))
        .map((key, value) => MapEntry(key, value.clamp(0, 99).toInt())),
    maxActiveRequestsBonusPerLevel: _int(
      raw['maxActiveRequestsBonusPerLevel'],
      b.maxActiveRequestsBonusPerLevel,
    ),
    maximumLevel: _int(raw['maximumLevel'], b.maximumLevel),
    manualSlotsByLevel: _levelMap(
      raw['manualSlotsByLevel'],
      b.manualSlotsByLevel,
    ),
    allowDuplicateStacks: raw['allowDuplicateStacks'] is bool
        ? raw['allowDuplicateStacks'] as bool
        : b.allowDuplicateStacks,
    stackQuantityLimit: _int(raw['stackQuantityLimit'], b.stackQuantityLimit),
    distributorConstructionCost: _resourceMap(
      raw['distributorConstructionCost'],
      b.distributorConstructionCost,
    ),
    distributorConstructionMinutes: _int(
      raw['distributorConstructionMinutes'],
      b.distributorConstructionMinutes,
    ),
    distributorEnergyCapacity: _int(
      raw['distributorEnergyCapacity'],
      b.distributorEnergyCapacity,
    ),
    distributorEnergyPerBioBattery: _int(
      raw['distributorEnergyPerBioBattery'],
      b.distributorEnergyPerBioBattery,
    ),
    distributorDailyEnergyByLevel: _levelMap(
      raw['distributorDailyEnergyByLevel'],
      b.distributorDailyEnergyByLevel,
    ),
    distributorSlotsByLevel: _levelMap(
      raw['distributorSlotsByLevel'],
      b.distributorSlotsByLevel,
    ),
    distributorBreakDenominatorByLevel: _levelMap(
      raw['distributorBreakDenominatorByLevel'],
      b.distributorBreakDenominatorByLevel,
    ),
    distributorRepairMinutesByLevel: _levelMap(
      raw['distributorRepairMinutesByLevel'],
      b.distributorRepairMinutesByLevel,
    ),
    distributorRepairCost: _resourceMap(
      raw['distributorRepairCost'],
      b.distributorRepairCost,
    ),
    confidenceSuccessGain: _int(
      raw['confidenceSuccessGain'],
      b.confidenceSuccessGain,
    ),
    confidenceFailurePenalty: _int(
      raw['confidenceFailurePenalty'],
      b.confidenceFailurePenalty,
    ),
    confidenceMaxPaymentBonusPercent: _double(
      raw['confidenceMaxPaymentBonusPercent'],
      b.confidenceMaxPaymentBonusPercent,
    ),
    maxActiveLicenses: _int(raw['maxActiveLicenses'], b.maxActiveLicenses),
    licenseCostBioBatteries: _int(
      raw['licenseCostBioBatteries'],
      b.licenseCostBioBatteries,
    ),
    licenseChangeCostBioBatteries: _int(
      raw['licenseChangeCostBioBatteries'],
      b.licenseChangeCostBioBatteries,
    ),
    licenseDirectedRatioPercent: _int(
      raw['licenseDirectedRatioPercent'],
      b.licenseDirectedRatioPercent,
    ),
    specializedShopSlotsByMarketLevel: _levelMap(
      raw['specializedShopSlotsByMarketLevel'],
      b.specializedShopSlotsByMarketLevel,
    ),
    firstShopFree: raw['firstShopFree'] is bool
        ? raw['firstShopFree'] as bool
        : b.firstShopFree,
    residentsPerHourlyRequest: _int(
      raw['residentsPerHourlyRequest'],
      b.residentsPerHourlyRequest,
    ),
    requestJitterMinPercent: _int(
      raw['requestJitterMinPercent'],
      b.requestJitterMinPercent,
    ),
    requestJitterMaxPercent: _int(
      raw['requestJitterMaxPercent'],
      b.requestJitterMaxPercent,
    ),
    distributorResponseDelayMinutes: _int(
      raw['distributorResponseDelayMinutes'],
      b.distributorResponseDelayMinutes,
    ),
    weatherRequestRatioPercent:
        _int(raw['weatherRequestRatioPercent'], b.weatherRequestRatioPercent),
    weatherRequestPopulationDivisor: _int(
        raw['weatherRequestPopulationDivisor'],
        b.weatherRequestPopulationDivisor),
    weatherRequestItems: <String, List<String>>{
      for (final entry in b.weatherRequestItems.entries)
        entry.key: ((raw['weatherRequestItems'] as Map?)?[entry.key] as List? ??
                entry.value)
            .map((item) => '$item')
            .toList(),
    },
    requestBasePerHourByLevel: _levelMap(
      raw['requestBasePerHourByLevel'],
      b.requestBasePerHourByLevel,
    ),
    requestMinimumSpacingMinutes: _int(
        raw['requestMinimumSpacingMinutes'], b.requestMinimumSpacingMinutes),
    economicActivityWellbeingMaxPercent: _int(
        raw['economicActivityWellbeingMaxPercent'],
        b.economicActivityWellbeingMaxPercent),
    economicActivityHeartLevelPercent: _int(
        raw['economicActivityHeartLevelPercent'],
        b.economicActivityHeartLevelPercent),
    economicActivityHeartLevelCapPercent: _int(
        raw['economicActivityHeartLevelCapPercent'],
        b.economicActivityHeartLevelCapPercent),
    economicActivityMarketLevelPercent: _int(
        raw['economicActivityMarketLevelPercent'],
        b.economicActivityMarketLevelPercent),
    economicActivityMarketLevelCapPercent: _int(
        raw['economicActivityMarketLevelCapPercent'],
        b.economicActivityMarketLevelCapPercent),
    economicActivityWeatherPercent: _resourceMap(
        raw['economicActivityWeatherPercent'],
        b.economicActivityWeatherPercent),
    requestCategoryWeights:
        _resourceMap(raw['requestCategoryWeights'], b.requestCategoryWeights),
    requestPriceBioPiles:
        _resourceMap(raw['requestPriceBioPiles'], b.requestPriceBioPiles),
    specializedShopGainBonusPercent: _int(
        raw['specializedShopGainBonusPercent'],
        b.specializedShopGainBonusPercent),
    baseStorePricePenaltyPercent: _int(
        raw['baseStorePricePenaltyPercent'], b.baseStorePricePenaltyPercent),
    shopConstructionCost:
        _resourceMap(raw['shopConstructionCost'], b.shopConstructionCost),
    shopConstructionBioBatteries: _int(
        raw['shopConstructionBioBatteries'], b.shopConstructionBioBatteries),
    shopUpgradeCostMultiplier:
        _int(raw['shopUpgradeCostMultiplier'], b.shopUpgradeCostMultiplier),
    distributorConstructionBioBatteries: _int(
        raw['distributorConstructionBioBatteries'],
        b.distributorConstructionBioBatteries),
    residentClaimVacancyDays:
        _int(raw['residentClaimVacancyDays'], b.residentClaimVacancyDays),
    residentClaimWarningHours:
        _int(raw['residentClaimWarningHours'], b.residentClaimWarningHours),
    requestBookLevel: _int(raw['requestBookLevel'], b.requestBookLevel),
    informationPointLevel:
        _int(raw['informationPointLevel'], b.informationPointLevel),
    distributorMarketLevels: _levelMap(
      raw['distributorMarketLevels'],
      b.distributorMarketLevels,
    ),
    residentShopServiceCapacity: _int(
      raw['residentShopServiceCapacity'],
      b.residentShopServiceCapacity,
    ),
    residentShopReservePiles: _int(
      raw['residentShopReservePiles'],
      b.residentShopReservePiles,
    ),
    residentShopStockTarget: _int(
      raw['residentShopStockTarget'],
      b.residentShopStockTarget,
    ),
    requestMinimumMarketLevelByItem: _resourceMap(
      raw['requestMinimumMarketLevelByItem'],
      b.requestMinimumMarketLevelByItem,
    ),
    constructionMinutesByLevel: _levelMap(
      raw['constructionMinutesByLevel'],
      b.constructionMinutesByLevel,
    ),
  );
}

CommunityRolesConfig _communityRoles(Object? value) {
  final raw = _map(value);
  const b = defaultCommunityRolesConfig;
  if (raw == null) return b;
  final weights = _map(raw['passionWeights']);
  return CommunityRolesConfig(
    enabled: raw['enabled'] is bool ? raw['enabled'] as bool : b.enabled,
    passionWeights: <String, int>{
      for (final entry in b.passionWeights.entries)
        entry.key: _int(weights?[entry.key], entry.value),
    },
    passionHappinessBonus:
        _int(raw['passionHappinessBonus'], b.passionHappinessBonus),
    communityEfficiencyPercent:
        _int(raw['communityEfficiencyPercent'], b.communityEfficiencyPercent),
    roleIntervalMinutes:
        _int(raw['roleIntervalMinutes'], b.roleIntervalMinutes),
    cookingCoveragePerCycle:
        _int(raw['cookingCoveragePerCycle'], b.cookingCoveragePerCycle),
    cookingMaximumMealsPerDay:
        _int(raw['cookingMaximumMealsPerDay'], b.cookingMaximumMealsPerDay),
    craftingMaximumOutputPerDay:
        _int(raw['craftingMaximumOutputPerDay'], b.craftingMaximumOutputPerDay),
    observationOrganicPerCycle:
        _int(raw['observationOrganicPerCycle'], b.observationOrganicPerCycle),
    observationMineralPerCycle:
        _int(raw['observationMineralPerCycle'], b.observationMineralPerCycle),
    observationRequiresSecurity:
        _int(raw['observationRequiresSecurity'], b.observationRequiresSecurity),
    watchingSecurityPerInterval:
        _int(raw['watchingSecurityPerInterval'], b.watchingSecurityPerInterval),
    ptibugRequestChancePercent:
        _int(raw['ptibugRequestChancePercent'], b.ptibugRequestChancePercent),
    residentPtibugMaximum:
        _int(raw['residentPtibugMaximum'], b.residentPtibugMaximum),
    allowNonPassionWork: raw['allowNonPassionWork'] is bool
        ? raw['allowNonPassionWork'] as bool
        : b.allowNonPassionWork,
  );
}

ResidentEconomyConfig _residentEconomy(Object? value) {
  final raw = _map(value);
  const b = defaultResidentEconomyConfig;
  if (raw == null) return b;
  return ResidentEconomyConfig(
    enabled: raw['enabled'] is bool ? raw['enabled'] as bool : b.enabled,
    pilesPerBattery: _int(raw['pilesPerBattery'], b.pilesPerBattery),
    batteriesPerEnergyCore:
        _int(raw['batteriesPerEnergyCore'], b.batteriesPerEnergyCore),
    householdDistributionMinutes: _int(
        raw['householdDistributionMinutes'], b.householdDistributionMinutes),
    secondGeneratorBonusPercent:
        _int(raw['secondGeneratorBonusPercent'], b.secondGeneratorBonusPercent),
    secondGeneratorInstallationCostPiles: _int(
      raw['secondGeneratorInstallationCostPiles'],
      b.secondGeneratorInstallationCostPiles,
    ),
    residentInitialPileBalance:
        _int(raw['residentInitialPileBalance'], b.residentInitialPileBalance),
    householdInitialPileBalance:
        _int(raw['householdInitialPileBalance'], b.householdInitialPileBalance),
    personalEmergencyReservePiles: _int(
        raw['personalEmergencyReservePiles'], b.personalEmergencyReservePiles),
    essentialPurchaseMayUseReserve:
        raw['essentialPurchaseMayUseReserve'] is bool
            ? raw['essentialPurchaseMayUseReserve'] as bool
            : b.essentialPurchaseMayUseReserve,
    desirePurchaseMayUseReserve: raw['desirePurchaseMayUseReserve'] is bool
        ? raw['desirePurchaseMayUseReserve'] as bool
        : b.desirePurchaseMayUseReserve,
    personalAccountCapPiles:
        _int(raw['personalAccountCapPiles'], b.personalAccountCapPiles),
    householdAccountCapPiles:
        _int(raw['householdAccountCapPiles'], b.householdAccountCapPiles),
    residentInventoryItemCap:
        _int(raw['residentInventoryItemCap'], b.residentInventoryItemCap),
    basePricesPiles: _resourceMap(raw['basePricesPiles'], b.basePricesPiles),
    producerSharePercent:
        _int(raw['producerSharePercent'], b.producerSharePercent),
    supplierSharePercent:
        _int(raw['supplierSharePercent'], b.supplierSharePercent),
    merchantSharePercent:
        _int(raw['merchantSharePercent'], b.merchantSharePercent),
    absentMerchantShareRecipient: _string(
        raw['absentMerchantShareRecipient'], b.absentMerchantShareRecipient),
    financialStrainWindowDays:
        _int(raw['financialStrainWindowDays'], b.financialStrainWindowDays),
    financialStrainCriticalThreshold: _int(
        raw['financialStrainCriticalThreshold'],
        b.financialStrainCriticalThreshold),
    maxSettlementHistory:
        _int(raw['maxSettlementHistory'], b.maxSettlementHistory),
  );
}

HousingConfig _housing(Object? value) {
  final raw = _map(value);
  const b = defaultHousingConfig;
  if (raw == null) return b;
  final alcoves = _map(raw['alcovesByHouseLevel']);
  return HousingConfig(
    houseMaxLevel: _int(raw['houseMaxLevel'], b.houseMaxLevel),
    alcovesByHouseLevel: {
      for (final entry in b.alcovesByHouseLevel.entries)
        entry.key: _int(alcoves?[entry.key.toString()], entry.value),
    },
    residentsPerHousingUnit: _int(
      raw['residentsPerHousingUnit'],
      b.residentsPerHousingUnit,
    ),
    initialHousingOrganicCost: _int(
      raw['initialHousingOrganicCost'],
      b.initialHousingOrganicCost,
    ),
    initialHousingMineralCost: _int(
      raw['initialHousingMineralCost'],
      b.initialHousingMineralCost,
    ),
    housingOrganicCostIncreasePerUnit: _int(
      raw['housingOrganicCostIncreasePerUnit'],
      b.housingOrganicCostIncreasePerUnit,
    ),
    housingMineralCostIncreasePerUnit: _int(
      raw['housingMineralCostIncreasePerUnit'],
      b.housingMineralCostIncreasePerUnit,
    ),
    housingDurationMinutes: _int(
      raw['housingDurationMinutes'],
      b.housingDurationMinutes,
    ),
    wellbeingPenaltyPerUnhousedResident: _int(
      raw['wellbeingPenaltyPerUnhousedResident'],
      b.wellbeingPenaltyPerUnhousedResident,
    ),
    maximumHousingWellbeingPenalty: _int(
      raw['maximumHousingWellbeingPenalty'],
      b.maximumHousingWellbeingPenalty,
    ),
    thanksBioBatteryCost: _int(
      raw['thanksBioBatteryCost'],
      b.thanksBioBatteryCost,
    ),
    thanksWellbeingBonus: _int(
      raw['thanksWellbeingBonus'],
      b.thanksWellbeingBonus,
    ),
    thanksDurationHours: _int(
      raw['thanksDurationHours'],
      b.thanksDurationHours,
    ),
    houseViabilityDamageHappinessPercent: _int(
        raw['houseViabilityDamageHappinessPercent'],
        b.houseViabilityDamageHappinessPercent),
    houseRepairGain: _int(raw['houseRepairGain'], b.houseRepairGain),
    houseRepairOrganicCost:
        _int(raw['houseRepairOrganicCost'], b.houseRepairOrganicCost),
    houseRepairMineralCost:
        _int(raw['houseRepairMineralCost'], b.houseRepairMineralCost),
    houseProtectionSlots:
        _int(raw['houseProtectionSlots'], b.houseProtectionSlots),
    neutralHappinessWithoutResidents: _int(
        raw['neutralHappinessWithoutResidents'],
        b.neutralHappinessWithoutResidents),
    residentFurnitureSlots:
        _int(raw['residentFurnitureSlots'], b.residentFurnitureSlots),
    additionalGeneratorSlots:
        _int(raw['additionalGeneratorSlots'], b.additionalGeneratorSlots),
    domesticGeneratorPilesPerHour: _int(
      raw['domesticGeneratorPilesPerHour'],
      b.domesticGeneratorPilesPerHour,
    ),
    domesticGeneratorRunsWhenEmpty:
        raw['domesticGeneratorRunsWhenEmpty'] is bool
            ? raw['domesticGeneratorRunsWhenEmpty'] as bool
            : b.domesticGeneratorRunsWhenEmpty,
    residentInitialPileBalance:
        _int(raw['residentInitialPileBalance'], b.residentInitialPileBalance),
    mealsRequiredPerDay:
        _int(raw['mealsRequiredPerDay'], b.mealsRequiredPerDay),
    partialNutritionHappinessPenalty: _int(
      raw['partialNutritionHappinessPenalty'],
      b.partialNutritionHappinessPenalty,
    ),
    noNutritionHappinessPenalty: _int(
      raw['noNutritionHappinessPenalty'],
      b.noNutritionHappinessPenalty,
    ),
    interiorSatisfiedHappinessBonus: _int(
      raw['interiorSatisfiedHappinessBonus'],
      b.interiorSatisfiedHappinessBonus,
    ),
    interiorUnsatisfiedHappinessPenalty: _int(
      raw['interiorUnsatisfiedHappinessPenalty'],
      b.interiorUnsatisfiedHappinessPenalty,
    ),
    desireSatisfiedHappinessBonus: _int(
      raw['desireSatisfiedHappinessBonus'],
      b.desireSatisfiedHappinessBonus,
    ),
    weatherProtectionModeratePenalty: _int(
      raw['weatherProtectionModeratePenalty'],
      b.weatherProtectionModeratePenalty,
    ),
    weatherProtectionStrongPenalty: _int(
      raw['weatherProtectionStrongPenalty'],
      b.weatherProtectionStrongPenalty,
    ),
    weatherProtectionSeverePenalty: _int(
      raw['weatherProtectionSeverePenalty'],
      b.weatherProtectionSeverePenalty,
    ),
    migrationGraceHours:
        _int(raw['migrationGraceHours'], b.migrationGraceHours),
    clothingRequiredForFashionDesire: _int(
      raw['clothingRequiredForFashionDesire'],
      b.clothingRequiredForFashionDesire,
    ),
    defaultProtectionDurabilityEvents: _int(
        raw['defaultProtectionDurabilityEvents'],
        b.defaultProtectionDurabilityEvents),
    arrivalActiveCandidateLimit:
        _int(raw['arrivalActiveCandidateLimit'], b.arrivalActiveCandidateLimit),
    arrivalCandidateIntervalHours: _int(
        raw['arrivalCandidateIntervalHours'], b.arrivalCandidateIntervalHours),
    arrivalExpiryDays: _int(raw['arrivalExpiryDays'], b.arrivalExpiryDays),
    arrivalPostponeDays:
        _int(raw['arrivalPostponeDays'], b.arrivalPostponeDays),
    arrivalTravelHours: _int(raw['arrivalTravelHours'], b.arrivalTravelHours),
    arrivalInitialHappiness:
        _int(raw['arrivalInitialHappiness'], b.arrivalInitialHappiness),
    arrivalInitialPileBalance:
        _int(raw['arrivalInitialPileBalance'], b.arrivalInitialPileBalance),
    visionDisappointmentPenalty:
        _int(raw['visionDisappointmentPenalty'], b.visionDisappointmentPenalty),
    visionDisappointmentHours:
        _int(raw['visionDisappointmentHours'], b.visionDisappointmentHours),
    visionFulfilledBonus:
        _int(raw['visionFulfilledBonus'], b.visionFulfilledBonus),
    visionBonusCap: _int(raw['visionBonusCap'], b.visionBonusCap),
    visionSameBranchPercent:
        _int(raw['visionSameBranchPercent'], b.visionSameBranchPercent),
    householdAutonomyGraceHours:
        _int(raw['householdAutonomyGraceHours'], b.householdAutonomyGraceHours),
    householdEmergencyReservePiles: _int(raw['householdEmergencyReservePiles'],
        b.householdEmergencyReservePiles),
    autonomousRepairGain:
        _int(raw['autonomousRepairGain'], b.autonomousRepairGain),
    autonomousRepairHours:
        _int(raw['autonomousRepairHours'], b.autonomousRepairHours),
    autonomousRepairCostPiles:
        _int(raw['autonomousRepairCostPiles'], b.autonomousRepairCostPiles),
    householdContributionMaxPercent: _int(
        raw['householdContributionMaxPercent'],
        b.householdContributionMaxPercent),
  );
}
