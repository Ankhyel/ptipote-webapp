import 'camp_heart_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'housing_config.dart';
import 'lisiere_forage_config.dart';
import 'market_config.dart';
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
  marketConfig = _market(raw?['market']);
  housingConfig = _housing(raw?['housing']);
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
        xpRequiredForNextLevel: base.xpRequiredForNextLevel == null
            ? null
            : _int(
                item?['xpRequiredForNextLevel'], base.xpRequiredForNextLevel!),
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
      weatherEvents: base.weatherEvents);
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
