import 'camp_heart_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'housing_config.dart';
import 'kernel_config.dart';
import 'kernel_progress_config.dart';
import 'lisiere_forage_config.dart';
import 'market_config.dart';
import 'ptibug_config.dart';
import 'security_tower_config.dart';
import 'tower_operations_config.dart';
import 'workshop_config.dart';

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
  pTibugConfig = _ptibug(raw?['ptibug']);
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

int _int(Object? value, int fallback) =>
    value is num && value.isFinite ? value.round() : fallback;
double _double(Object? value, double fallback) =>
    value is num && value.isFinite ? value.toDouble() : fallback;
String _string(Object? value, String fallback) =>
    value is String && value.trim().isNotEmpty ? value : fallback;

Map<String, int> _resourceMap(Object? value, Map<String, int> fallback) {
  final raw = _map(value);
  if (raw == null) return fallback;
  return <String, int>{
    for (final entry in fallback.entries)
      entry.key: _int(raw[entry.key], entry.value),
  };
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
    startingPopulation:
        _int(raw['startingPopulation'], base.startingPopulation),
    startingWellbeing: _int(raw['startingWellbeing'], base.startingWellbeing),
    startingBioBatteries:
        _int(raw['startingBioBatteries'], base.startingBioBatteries),
    maxRefugeRequests: _int(raw['maxRefugeRequests'], base.maxRefugeRequests),
    populationCapacityByCampHeartLevel: <int, int>{
      for (final entry in base.populationCapacityByCampHeartLevel.entries)
        entry.key: _int(capacities?['${entry.key}'], entry.value),
    },
    wellbeingRedThreshold:
        _int(raw['wellbeingRedThreshold'], base.wellbeingRedThreshold),
    wellbeingOrangeThreshold:
        _int(raw['wellbeingOrangeThreshold'], base.wellbeingOrangeThreshold),
    missions: missions.isEmpty
        ? base.missions
        : missions
            .map(_map)
            .whereType<Map<String, dynamic>>()
            .map((item) => _kernelMission(
                item,
                base.missions
                    .where((mission) => mission.id == item['id'])
                    .firstOrNull))
            .whereType<KernelMissionConfig>()
            .toList(),
    plans: base.plans.map((fallback) {
      final item = planById[fallback.id];
      return KernelPlanConfig(
        id: fallback.id,
        title: _string(item?['title'], fallback.title),
        description: _string(item?['description'], fallback.description),
        requiredCampHeartLevel: _int(
            item?['requiredCampHeartLevel'], fallback.requiredCampHeartLevel),
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
        raw['type'], fallback?.type ?? KernelMissionType.refugeRequest),
    title: _string(raw['title'], fallback?.title ?? id),
    description: _string(raw['description'], fallback?.description ?? ''),
    conditionType: _kernelMissionCondition(raw['conditionType'],
        fallback?.conditionType ?? KernelMissionConditionType.requirementsMet),
    requiredAmount: _int(raw['requiredAmount'], fallback?.requiredAmount ?? 1),
    populationReward:
        _int(raw['populationReward'], fallback?.populationReward ?? 0),
    bioBatteryReward:
        _int(raw['bioBatteryReward'], fallback?.bioBatteryReward ?? 0),
    xpReward: _int(raw['xpReward'], fallback?.xpReward ?? 0),
    mailMessage: _string(raw['mailMessage'],
        fallback?.mailMessage ?? 'Mission Kernel terminée.'),
    requiredBuildingLevels: _positiveMap(raw['requiredBuildingLevels']),
    requiredKernelTrustLevel: _int(raw['requiredKernelTrustLevel'],
        fallback?.requiredKernelTrustLevel ?? 1),
    requiredBreederLevel:
        _int(raw['requiredBreederLevel'], fallback?.requiredBreederLevel ?? 1),
    requiredBuilderLevel:
        _int(raw['requiredBuilderLevel'], fallback?.requiredBuilderLevel ?? 1),
    requiredRestorerLevel: _int(
        raw['requiredRestorerLevel'], fallback?.requiredRestorerLevel ?? 1),
    requestedItem: requestedItem.isEmpty ? null : requestedItem,
    requestedAmount:
        _int(raw['requestedAmount'], fallback?.requestedAmount ?? 0),
    resourceRewards: _positiveMap(raw['resourceRewards']),
    rewardPatternId: rewardPatternId.isEmpty ? null : rewardPatternId,
    weatherType: weatherType.isEmpty ? null : weatherType,
  );
}

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
        Object? value, KernelMissionType fallback) =>
    KernelMissionType.values.where((type) => type.name == value).firstOrNull ??
    fallback;

KernelMissionConditionType _kernelMissionCondition(
        Object? value, KernelMissionConditionType fallback) =>
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
    trustXpRequiredBase:
        _int(raw['trustXpRequiredBase'], base.trustXpRequiredBase),
    axisXpRequiredBase:
        _int(raw['axisXpRequiredBase'], base.axisXpRequiredBase),
    xpRequiredMultiplier:
        _double(raw['xpRequiredMultiplier'], base.xpRequiredMultiplier),
    eventRewards: <KernelProgressEventType, KernelProgressReward>{
      for (final event in KernelProgressEventType.values)
        event: _kernelReward(
            _map(rawRewards?[event.name]), base.eventRewards[event]!),
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
        discoveryEvent:
            _kernelEvent(item?['discoveryEvent'], fallback.discoveryEvent),
        discoveryThreshold:
            _int(item?['discoveryThreshold'], fallback.discoveryThreshold),
        requiredTrustLevel:
            _int(item?['requiredTrustLevel'], fallback.requiredTrustLevel),
        requiredAxis: _kernelAxis(item?['requiredAxis'], fallback.requiredAxis),
        requiredAxisLevel:
            _int(item?['requiredAxisLevel'], fallback.requiredAxisLevel),
        requiredBreederLevel:
            _int(item?['requiredBreederLevel'], fallback.requiredBreederLevel),
        requiredBuilderLevel:
            _int(item?['requiredBuilderLevel'], fallback.requiredBuilderLevel),
        requiredRestorerLevel: _int(
            item?['requiredRestorerLevel'], fallback.requiredRestorerLevel),
        requiredBuildingLevels: _resourceMap(
          item?['requiredBuildingLevels'],
          fallback.requiredBuildingLevels,
        ),
        workshopRecipeId:
            _string(item?['workshopRecipeId'], fallback.workshopRecipeId ?? '')
                    .isEmpty
                ? null
                : _string(
                    item?['workshopRecipeId'], fallback.workshopRecipeId ?? ''),
        initialState: _kernelPlanState(
            item?['initialState'] ?? item?['state'], fallback.initialState),
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

PTibugConfig _ptibug(Object? value) {
  final raw = _map(value);
  const base = defaultPTibugConfig;
  if (raw == null) return base;
  final rawSpecies = _map(raw['species']);
  final rawPatterns = _map(raw['patterns']);
  final rawPrices = _map(raw['sourcierPatternPrices']);
  final rawTraits = _map(raw['traitDefinitions']);
  return PTibugConfig(
    nurseryRequirements:
        _resourceMap(raw['nurseryRequirements'], base.nurseryRequirements),
    nurseryDurationMinutes:
        _int(raw['nurseryDurationMinutes'], base.nurseryDurationMinutes),
    slotsByLevel: _levelMap(raw['slotsByLevel'], base.slotsByLevel),
    moduleSlotsByLevel:
        _levelMap(raw['moduleSlotsByLevel'], base.moduleSlotsByLevel),
    productionCycleMinutes:
        _int(raw['productionCycleMinutes'], base.productionCycleMinutes),
    carryingCapacity: _int(raw['carryingCapacity'], base.carryingCapacity),
    xpPerCycle: _int(raw['xpPerCycle'], base.xpPerCycle),
    wingsCycleReduction:
        _double(raw['wingsCycleReduction'], base.wingsCycleReduction),
    clawProductionBonus:
        _int(raw['clawProductionBonus'], base.clawProductionBonus),
    reservoirCapacityBonus:
        _int(raw['reservoirCapacityBonus'], base.reservoirCapacityBonus),
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
            creationCost:
                _resourceMap(item?['creationCost'], fallback.creationCost),
            creationEnergyCost:
                _int(item?['creationEnergyCost'], fallback.creationEnergyCost),
            creationBioBatteryCost: _int(
              item?['creationBioBatteryCost'],
              fallback.creationBioBatteryCost,
            ),
            creationMinutes:
                _int(item?['creationMinutes'], fallback.creationMinutes),
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
        ...?rawTraits?.keys
      })
        id: () {
          final item = _map(rawTraits?[id]);
          final fallback = base.traitDefinitions[id];
          final rawEffects = _resourceMap(
              item?['effects'], fallback?.effects ?? const <String, int>{});
          final rawGrades = _map(item?['gradeMultipliers']);
          return PTibugTraitDefinition(
            id: _string(item?['id'], fallback?.id ?? id),
            displayName:
                _string(item?['displayName'], fallback?.displayName ?? id),
            description:
                _string(item?['description'], fallback?.description ?? ''),
            effects: rawEffects,
            gradeMultipliers: <PTibugTraitGrade, int>{
              for (final grade in PTibugTraitGrade.values)
                grade: _int(rawGrades?[grade.name],
                    fallback?.gradeMultipliers[grade] ?? 1),
            },
            colorHex:
                _string(item?['colorHex'], fallback?.colorHex ?? '#817D66'),
            isActive: item?['isActive'] is bool
                ? item!['isActive'] as bool
                : fallback?.isActive ?? true,
          );
        }(),
    },
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
        Object? value, KernelProgressEventType? fallback) =>
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
                base.organicRequiredForNextLevel!),
        populationLabel:
            _string(item?['populationLabel'], base.populationLabel),
        populationMin: base.populationMin == null
            ? null
            : _int(item?['populationMin'], base.populationMin!),
        populationMax: base.populationMax == null
            ? null
            : _int(item?['populationMax'], base.populationMax!),
        activePtipoteComfortLimit: _int(
            item?['activePtipoteComfortLimit'], base.activePtipoteComfortLimit),
        refugeHappinessBonus:
            _int(item?['refugeHappinessBonus'], base.refugeHappinessBonus),
        localActivityModifier:
            _double(item?['localActivityModifier'], base.localActivityModifier),
        unlocks: base.unlocks,
        effects: base.effects,
      );
    }),
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
  return LisiereForageConfig(
    forageTimeScale: _int(
        raw['forageTimeScale'], defaultLisiereForageConfig.forageTimeScale),
    refugeSafetyFallback: _int(raw['refugeSafetyFallback'],
        defaultLisiereForageConfig.refugeSafetyFallback),
    minimumMissionRisk: _int(raw['minimumMissionRisk'],
        defaultLisiereForageConfig.minimumMissionRisk),
    securityRiskReductionFactor: _double(raw['securityRiskReductionFactor'],
        defaultLisiereForageConfig.securityRiskReductionFactor),
    inventorySlotLimit: _int(raw['inventorySlotLimit'],
        defaultLisiereForageConfig.inventorySlotLimit),
    inventoryStackLimit: _int(raw['inventoryStackLimit'],
        defaultLisiereForageConfig.inventoryStackLimit),
    xpGainByDuration: {
      for (final key in ForageDuration.values)
        key: _int(
            xp?[key.name], defaultLisiereForageConfig.xpGainByDuration[key]!)
    },
    intensityXpMultiplier: {
      for (final key in ForageIntensity.values)
        key: _double(intensityXp?[key.name],
            defaultLisiereForageConfig.intensityXpMultiplier[key]!)
    },
    durations: {
      for (final key in ForageDuration.values)
        key: _duration(key, durationById[key.name])
    },
    intensities: {
      for (final key in ForageIntensity.values)
        key: _intensity(key, intensityById[key.name])
    },
    biomes: {
      for (final key in ForageBiome.values)
        key: _biome(key, biomeById[key.name])
    },
  );
}

ForageDurationConfig _duration(ForageDuration key, Map<String, dynamic>? raw) {
  final base = defaultLisiereForageConfig.durations[key]!;
  return ForageDurationConfig(
      label: _string(raw?['label'], base.label),
      theoreticalHours: _int(raw?['theoreticalHours'], base.theoreticalHours),
      baseVitalityCost: _int(raw?['baseVitalityCost'], base.baseVitalityCost));
}

ForageIntensityConfig _intensity(
    ForageIntensity key, Map<String, dynamic>? raw) {
  final base = defaultLisiereForageConfig.intensities[key]!;
  return ForageIntensityConfig(
      label: _string(raw?['label'], base.label),
      rewardMultiplier:
          _double(raw?['rewardMultiplier'], base.rewardMultiplier),
      vitalityMultiplier:
          _double(raw?['vitalityMultiplier'], base.vitalityMultiplier),
      riskModifierPercent:
          _int(raw?['riskModifierPercent'], base.riskModifierPercent),
      zoneFatigueLabel: base.zoneFatigueLabel);
}

ForageBiomeConfig _biome(ForageBiome key, Map<String, dynamic>? raw) {
  final base = defaultLisiereForageConfig.biomes[key]!;
  return ForageBiomeConfig(
      label: _string(raw?['label'], base.label),
      tendency: base.tendency,
      baseRewards: _resourceMap(raw?['rewards'], base.baseRewards),
      baseRiskPercent: _int(raw?['baseRiskPercent'], base.baseRiskPercent),
      restorationLevel: _int(raw?['restorationLevel'], base.restorationLevel),
      restorationStage:
          _string(raw?['restorationStage'], base.restorationStage),
      organicRewardModifier: base.organicRewardModifier,
      mineralRewardModifier: base.mineralRewardModifier,
      riskModifier: base.riskModifier,
      linkedPtipoteRefugeBonus: base.linkedPtipoteRefugeBonus,
      hazards: base.hazards);
}

SecurityTowerConfig _tower(Object? value) {
  final raw = _map(value);
  if (raw == null) return defaultSecurityTowerConfig;
  final slots = _map(raw['slotsByLevel']);
  const base = defaultSecurityTowerConfig;
  return SecurityTowerConfig(
      requiredCampHeartLevel:
          _int(raw['requiredCampHeartLevel'], base.requiredCampHeartLevel),
      constructionCostOrganic:
          _int(raw['constructionCostOrganic'], base.constructionCostOrganic),
      constructionCostMineral:
          _int(raw['constructionCostMineral'], base.constructionCostMineral),
      maxSecurity: _int(raw['maxSecurity'], base.maxSecurity),
      initialSecurity: _int(raw['initialSecurity'], base.initialSecurity),
      securityGainPerTick:
          _int(raw['securityGainPerTick'], base.securityGainPerTick),
      tickMinutes: _int(raw['tickMinutes'], base.tickMinutes),
      vitalityCostPerTick:
          _int(raw['vitalityCostPerTick'], base.vitalityCostPerTick),
      securityDecayPerTick:
          _int(raw['securityDecayPerTick'], base.securityDecayPerTick),
      level1Slots: _int(slots?['1'], base.level1Slots),
      level2Slots: _int(slots?['2'], base.level2Slots),
      level3Slots: _int(slots?['3'], base.level3Slots),
      manualRechargeSecurityGain: _int(
          raw['manualRechargeSecurityGain'], base.manualRechargeSecurityGain),
      manualRechargeCooldownMinutes: _int(raw['manualRechargeCooldownMinutes'],
          base.manualRechargeCooldownMinutes),
      securityGainBonusPerLevel: _int(
          raw['securityGainBonusPerLevel'], base.securityGainBonusPerLevel),
      manualRechargeBonusPerLevel: _int(raw['manualRechargeBonusPerLevel'],
          base.manualRechargeBonusPerLevel));
}

TowerOperationsConfig _towerOperations(Object? value) {
  final raw = _map(value);
  if (raw == null) return defaultTowerOperationsConfig;
  const base = defaultTowerOperationsConfig;
  final bands =
      raw['wellbeingBands'] is List ? raw['wellbeingBands'] as List : const [];
  final weather =
      raw['weatherEvents'] is List ? raw['weatherEvents'] as List : const [];
  return TowerOperationsConfig(
      biomeRevealSecurityThreshold: _int(raw['biomeRevealSecurityThreshold'],
          base.biomeRevealSecurityThreshold),
      explorationDurationMinutes: _int(
          raw['explorationDurationMinutes'], base.explorationDurationMinutes),
      localSecurityMaximum:
          _int(raw['localSecurityMaximum'], base.localSecurityMaximum),
      localSecurityHoursForFullPatrol: _int(
          raw['localSecurityHoursForFullPatrol'],
          base.localSecurityHoursForFullPatrol),
      maximumLocalRiskReductionPercent: _int(
          raw['maximumLocalRiskReductionPercent'],
          base.maximumLocalRiskReductionPercent),
      localSecurityDecayPerHour: _int(
          raw['localSecurityDecayPerHour'], base.localSecurityDecayPerHour),
      localSecurityRecentMissionHours: _int(
          raw['localSecurityRecentMissionHours'],
          base.localSecurityRecentMissionHours),
      merchantPresenceHours:
          _int(raw['merchantPresenceHours'], base.merchantPresenceHours),
      merchantOfferPrices:
          _resourceMap(raw['merchantOfferPrices'], base.merchantOfferPrices),
      wellbeingBands: List<SecurityWellbeingBand>.generate(
          base.wellbeingBands.length, (index) {
        final item = index < bands.length ? _map(bands[index]) : null;
        final fallback = base.wellbeingBands[index];
        return SecurityWellbeingBand(
            minimumSecurity:
                _int(item?['minimumSecurity'], fallback.minimumSecurity),
            wellbeingModifier:
                _int(item?['wellbeingModifier'], fallback.wellbeingModifier),
            label: fallback.label);
      }),
      weatherEvents:
          List<TowerWeatherConfig>.generate(base.weatherEvents.length, (index) {
        final item = index < weather.length ? _map(weather[index]) : null;
        final fallback = base.weatherEvents[index];
        return TowerWeatherConfig(
          type: fallback.type,
          label: _string(item?['label'], fallback.label),
          description: _string(item?['description'], fallback.description),
          durationMinutes:
              _int(item?['durationMinutes'], fallback.durationMinutes),
          warningMinutes:
              _int(item?['warningMinutes'], fallback.warningMinutes),
          preparationItem:
              _string(item?['preparationItem'], fallback.preparationItem),
          preparationAmount:
              _int(item?['preparationAmount'], fallback.preparationAmount),
        );
      }));
}

FablabConfig _fablab(Object? value) {
  final raw = _map(value);
  const b = defaultFablabConfig;
  if (raw == null) return b;
  return FablabConfig(
      constructionCostLevel1Organic: _int(raw['constructionCostLevel1Organic'],
          b.constructionCostLevel1Organic),
      constructionCostLevel1Mineral: _int(raw['constructionCostLevel1Mineral'],
          b.constructionCostLevel1Mineral),
      baseGlobalStockCapacity:
          _int(raw['baseGlobalStockCapacity'], b.baseGlobalStockCapacity),
      stockCapacityBonusPerFablabLevel: _int(
          raw['stockCapacityBonusPerFablabLevel'],
          b.stockCapacityBonusPerFablabLevel),
      fablabMaxLevel: _int(raw['fablabMaxLevel'], b.fablabMaxLevel),
      cuisineMaxLevel: _int(raw['cuisineMaxLevel'], b.cuisineMaxLevel),
      atelierMaxLevel: _int(raw['atelierMaxLevel'], b.atelierMaxLevel),
      cuisineUnlockLevel: _int(raw['cuisineUnlockLevel'], b.cuisineUnlockLevel),
      atelierUnlockCampHeartLevel: _int(
          raw['atelierUnlockCampHeartLevel'], b.atelierUnlockCampHeartLevel),
      recyclerUnlockCampHeartLevel: _int(
          raw['recyclerUnlockCampHeartLevel'], b.recyclerUnlockCampHeartLevel),
      simpleMealOrganicCost:
          _int(raw['simpleMealOrganicCost'], b.simpleMealOrganicCost),
      simpleMealOutputAmount:
          _int(raw['simpleMealOutputAmount'], b.simpleMealOutputAmount));
}

WorkshopConfig _workshop(Object? value) {
  final raw = _map(value);
  const b = defaultWorkshopConfig;
  if (raw == null) return b;
  return WorkshopConfig(
      vitalityCostPerUnit:
          _int(raw['vitalityCostPerUnit'], b.vitalityCostPerUnit),
      levelSpeedBonusPercent:
          _double(raw['levelSpeedBonusPercent'], b.levelSpeedBonusPercent),
      maxLevelSpeedBonusPercent: _double(
          raw['maxLevelSpeedBonusPercent'], b.maxLevelSpeedBonusPercent),
      buildingLevelSpeedBonusPercent: _double(
          raw['buildingLevelSpeedBonusPercent'],
          b.buildingLevelSpeedBonusPercent),
      maxBuildingSpeedBonusPercent: _double(
          raw['maxBuildingSpeedBonusPercent'], b.maxBuildingSpeedBonusPercent),
      slotsPerLevel: _int(raw['slotsPerLevel'], b.slotsPerLevel));
}

CraftConfig _craft(Object? value) {
  final raw = _map(value);
  final recipes = raw?['recipes'];
  if (recipes is! List || recipes.isEmpty) return defaultCraftConfig;
  final defaults = {
    for (final recipe in defaultCraftConfig.recipes) recipe.id: recipe
  };
  final parsed = recipes
      .map(_map)
      .whereType<Map<String, dynamic>>()
      .map(
          (recipe) => _craftRecipe(recipe, defaults[_string(recipe['id'], '')]))
      .whereType<CraftRecipe>()
      .toList();
  return parsed.any((recipe) => recipe.id == 'simpleMeal')
      ? CraftConfig(recipes: parsed)
      : defaultCraftConfig;
}

CraftRecipe? _craftRecipe(Map<String, dynamic> raw, CraftRecipe? fallback) {
  final id = _string(raw['id'], fallback?.id ?? '');
  if (id.isEmpty) return null;
  final section =
      _string(raw['craftSection'], fallback?.craftSection.name ?? 'cuisine');
  final craftSection = section == CraftSection.atelier.name
      ? CraftSection.atelier
      : CraftSection.cuisine;
  final foodType = _string(raw['foodType'], fallback?.foodType.name ?? 'meal');
  return CraftRecipe(
    id: id,
    displayName: _string(raw['displayName'], fallback?.displayName ?? id),
    craftSection: craftSection,
    ingredients:
        _recipeResources(raw['ingredients'], fallback?.ingredients ?? const {}),
    contextIngredients: _recipeResources(
        raw['contextIngredients'], fallback?.contextIngredients ?? const {}),
    cuisineLevel: _int(raw['cuisineLevel'], fallback?.cuisineLevel ?? 0),
    atelierLevel: _int(raw['atelierLevel'], fallback?.atelierLevel ?? 0),
    kernelTrustLevel:
        _int(raw['kernelTrustLevel'], fallback?.kernelTrustLevel ?? 1),
    breederLevel: _int(raw['breederLevel'], fallback?.breederLevel ?? 1),
    builderLevel: _int(raw['builderLevel'], fallback?.builderLevel ?? 1),
    restorerLevel: _int(raw['restorerLevel'], fallback?.restorerLevel ?? 1),
    resultItem: _string(raw['resultItem'], fallback?.resultItem ?? id),
    resultAmount: _int(raw['resultAmount'], fallback?.resultAmount ?? 1),
    isConsumable: raw['isConsumable'] is bool
        ? raw['isConsumable'] as bool
        : fallback?.isConsumable ?? false,
    foodType: foodType == FoodType.drink.name ? FoodType.drink : FoodType.meal,
    hungerRestore: _int(raw['hungerRestore'], fallback?.hungerRestore ?? 0),
    vitalityRestore:
        _int(raw['vitalityRestore'], fallback?.vitalityRestore ?? 0),
    durationMinutes:
        _int(raw['durationMinutes'], fallback?.durationMinutes ?? 1),
    isEquipment: raw['isEquipment'] is bool
        ? raw['isEquipment'] as bool
        : fallback?.isEquipment ?? false,
    energyCost: _int(raw['energyCost'], fallback?.energyCost ?? 0),
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
      constructionCost:
          _resourceMap(raw['constructionCost'], b.constructionCost),
      requiredCampHeartLevel:
          _int(raw['requiredCampHeartLevel'], b.requiredCampHeartLevel),
      requiredPopulation: _int(raw['requiredPopulation'], b.requiredPopulation),
      saleSlotsPerLevel: _int(raw['saleSlotsPerLevel'], b.saleSlotsPerLevel),
      baseSaleIntervalMinutes:
          _int(raw['baseSaleIntervalMinutes'], b.baseSaleIntervalMinutes),
      valuePerBioBattery: _int(raw['valuePerBioBattery'], b.valuePerBioBattery),
      ptipoteIntervalMultiplier: _double(
          raw['ptipoteIntervalMultiplier'], b.ptipoteIntervalMultiplier),
      vitalityCostPerTick:
          _int(raw['vitalityCostPerTick'], b.vitalityCostPerTick),
      vitalityTickMinutes:
          _int(raw['vitalityTickMinutes'], b.vitalityTickMinutes),
      requestChance: _double(raw['requestChance'], b.requestChance),
      maxActiveRequests: _int(raw['maxActiveRequests'], b.maxActiveRequests),
      requestMinReturnMinutes:
          _int(raw['requestMinReturnMinutes'], b.requestMinReturnMinutes),
      requestMaxReturnMinutes:
          _int(raw['requestMaxReturnMinutes'], b.requestMaxReturnMinutes),
      saleValues: _resourceMap(raw['saleValues'], b.saleValues),
      saleIntervalReductionPerLevel: _double(
          raw['saleIntervalReductionPerLevel'],
          b.saleIntervalReductionPerLevel),
      maxActiveRequestsBonusPerLevel: _int(
          raw['maxActiveRequestsBonusPerLevel'],
          b.maxActiveRequestsBonusPerLevel));
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
          entry.key: _int(alcoves?[entry.key.toString()], entry.value)
      },
      residentsPerHousingUnit:
          _int(raw['residentsPerHousingUnit'], b.residentsPerHousingUnit),
      initialHousingOrganicCost:
          _int(raw['initialHousingOrganicCost'], b.initialHousingOrganicCost),
      initialHousingMineralCost:
          _int(raw['initialHousingMineralCost'], b.initialHousingMineralCost),
      housingDurationMinutes:
          _int(raw['housingDurationMinutes'], b.housingDurationMinutes),
      wellbeingPenaltyPerUnhousedResident: _int(
          raw['wellbeingPenaltyPerUnhousedResident'],
          b.wellbeingPenaltyPerUnhousedResident),
      maximumHousingWellbeingPenalty: _int(
          raw['maximumHousingWellbeingPenalty'],
          b.maximumHousingWellbeingPenalty),
      thanksBioBatteryCost:
          _int(raw['thanksBioBatteryCost'], b.thanksBioBatteryCost),
      thanksWellbeingBonus:
          _int(raw['thanksWellbeingBonus'], b.thanksWellbeingBonus),
      thanksDurationHours:
          _int(raw['thanksDurationHours'], b.thanksDurationHours));
}
