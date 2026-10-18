import 'dart:convert';

const int elevageConfigSchemaVersion = 7;

/// Every non-generic resource that can be selected as an explicit recipe
/// component in the local Élevage Dashboard. Organic and Mineral stay as their
/// dedicated base-cost fields so existing saves and the economy remain clear.
const List<String> elevageRecipeSpecialComponentIds = <String>[
  'ROOT',
  'LEAF',
  'MOSS',
  'ALGAE',
  'MUSHROOM',
  'FRUIT',
  'FIBROUS_FRUIT',
  'FRUIT_JELLY',
  'IRON',
  'LIMESTONE',
  'QUARTZ',
  'SEED',
  'SPORE',
  'SPROUT',
  'SALT',
];

enum ElevagePreset { prototype, target }

/// A Nature owns its complete ecological curve.  Keeping the six values per
/// axis in configuration prevents a hidden universal "2/2/2" optimum.
class ElevageNatureProfile {
  const ElevageNatureProfile({
    required this.id,
    required this.family,
    required this.nature,
    required this.label,
    required this.placeholder,
    required this.preferredLight,
    required this.preferredTemperature,
    required this.preferredHumidity,
    required this.curves,
  });

  final String id;
  final String family;
  final String nature;
  final String label;
  final String placeholder;
  final int preferredLight;
  final int preferredTemperature;
  final int preferredHumidity;

  /// `light`, `temperature` and `humidity`, each indexed from 0 through 5.
  final Map<String, List<String>> curves;

  String axisComfort(String axis, int value) {
    final values = curves[axis];
    if (values == null || values.length != 6) return 'NEUTRAL';
    return values[value.clamp(0, 5)];
  }

  int preferredForAxis(String axis) => switch (axis) {
        'light' => preferredLight,
        'temperature' => preferredTemperature,
        'humidity' => preferredHumidity,
        _ => 0,
      };

  ElevageNatureProfile copyWith({
    int? preferredLight,
    int? preferredTemperature,
    int? preferredHumidity,
    Map<String, List<String>>? curves,
  }) =>
      ElevageNatureProfile(
        id: id,
        family: family,
        nature: nature,
        label: label,
        placeholder: placeholder,
        preferredLight: preferredLight ?? this.preferredLight,
        preferredTemperature: preferredTemperature ?? this.preferredTemperature,
        preferredHumidity: preferredHumidity ?? this.preferredHumidity,
        curves: curves ?? this.curves,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'family': family,
        'nature': nature,
        'label': label,
        'placeholder': placeholder,
        'preferredLight': preferredLight,
        'preferredTemperature': preferredTemperature,
        'preferredHumidity': preferredHumidity,
        'curves': curves,
      };

  factory ElevageNatureProfile.fromJson(
          Map<String, dynamic> json, ElevageNatureProfile fallback) =>
      ElevageNatureProfile(
        id: fallback.id,
        family: fallback.family,
        nature: fallback.nature,
        label: fallback.label,
        placeholder: fallback.placeholder,
        preferredLight: _scale(json['preferredLight'], fallback.preferredLight),
        preferredTemperature:
            _scale(json['preferredTemperature'], fallback.preferredTemperature),
        preferredHumidity:
            _scale(json['preferredHumidity'], fallback.preferredHumidity),
        curves: _natureCurves(json['curves'], fallback.curves),
      );
}

class ElevageRecipe {
  const ElevageRecipe({
    required this.id,
    required this.label,
    required this.installationId,
    required this.organic,
    required this.mineral,
    this.special = const <String, int>{},
    this.unlockItems = const <String>[],
  });

  final String id;
  final String label;
  final String installationId;
  final int organic;
  final int mineral;
  final Map<String, int> special;
  final List<String> unlockItems;

  bool get isBase => unlockItems.isEmpty;

  ElevageRecipe copyWith(
          {int? organic, int? mineral, Map<String, int>? special}) =>
      ElevageRecipe(
        id: id,
        label: label,
        installationId: installationId,
        organic: organic ?? this.organic,
        mineral: mineral ?? this.mineral,
        special: special ?? this.special,
        unlockItems: unlockItems,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'installationId': installationId,
        'organic': organic,
        'mineral': mineral,
        'special': special,
        'unlockItems': unlockItems,
      };

  factory ElevageRecipe.fromJson(Map<String, dynamic> json) => ElevageRecipe(
        id: json['id'] == 'TROU_GEOTHERMIQUE_CHAUD'
            ? 'FOUR_BIO_ORGANIQUE'
            : json['id'] as String,
        label: json['label'] as String,
        installationId: json['installationId'] == 'TROU_GEOTHERMIQUE_CHAUD'
            ? 'FOUR_BIO_ORGANIQUE'
            : json['installationId'] as String,
        organic: (json['organic'] as num).toInt(),
        mineral: (json['mineral'] as num).toInt(),
        special: (json['special'] as Map? ?? const <String, dynamic>{}).map(
          (key, value) => MapEntry('$key', (value as num).toInt()),
        ),
        unlockItems:
            List<String>.from(json['unlockItems'] as List? ?? const []),
      );
}

/// Recycling intentionally reduces a specific resource to a generic one.
/// Rules live in Élevage configuration so the domain never guesses a UI-only
/// conversion and a future Dashboard editor can safely expose them.
class ElevageRecycleRule {
  const ElevageRecycleRule({
    required this.recyclable,
    this.recycleOutputType,
    this.recycleOutputQuantity = 0,
  });

  final bool recyclable;
  final String? recycleOutputType;
  final int recycleOutputQuantity;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'recyclable': recyclable,
        'recycleOutputType': recycleOutputType,
        'recycleOutputQuantity': recycleOutputQuantity,
      };

  factory ElevageRecycleRule.fromJson(
          Map<String, dynamic> json, ElevageRecycleRule fallback) =>
      ElevageRecycleRule(
        recyclable: json['recyclable'] is bool
            ? json['recyclable'] as bool
            : fallback.recyclable,
        recycleOutputType:
            json['recycleOutputType'] as String? ?? fallback.recycleOutputType,
        recycleOutputQuantity: _nonNegative(
            json['recycleOutputQuantity'], fallback.recycleOutputQuantity),
      );
}

/// A structure may be passive, use stored Energy, or consume reserve matter
/// directly. The state is persisted on each placed structure, while costs stay
/// editable and serialised at the Refuge configuration level.
class ElevageStructureConsumption {
  const ElevageStructureConsumption({
    this.mode = 'NONE',
    this.energyCost = 0,
    this.resourceCosts = const <String, int>{},
    this.consumptionIntervalSeconds = 0,
    this.enabled = true,
  });

  final String mode;
  final int energyCost;
  final Map<String, int> resourceCosts;
  final int consumptionIntervalSeconds;
  final bool enabled;

  ElevageStructureConsumption copyWith({
    int? energyCost,
    Map<String, int>? resourceCosts,
    int? consumptionIntervalSeconds,
    bool? enabled,
  }) =>
      ElevageStructureConsumption(
        mode: mode,
        energyCost: energyCost ?? this.energyCost,
        resourceCosts: resourceCosts ?? this.resourceCosts,
        consumptionIntervalSeconds:
            consumptionIntervalSeconds ?? this.consumptionIntervalSeconds,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode,
        'energyCost': energyCost,
        'resourceCosts': resourceCosts,
        'consumptionIntervalSeconds': consumptionIntervalSeconds,
        'enabled': enabled,
      };

  factory ElevageStructureConsumption.fromJson(
          Map<String, dynamic> json, ElevageStructureConsumption fallback) =>
      ElevageStructureConsumption(
        mode: json['mode'] as String? ?? fallback.mode,
        energyCost: _nonNegative(json['energyCost'], fallback.energyCost),
        resourceCosts: (json['resourceCosts'] as Map?)
                ?.map((key, value) => MapEntry('$key', _nonNegative(value, 0)))
                .cast<String, int>() ??
            fallback.resourceCosts,
        consumptionIntervalSeconds: _nonNegative(
            json['consumptionIntervalSeconds'],
            fallback.consumptionIntervalSeconds),
        enabled: json['enabled'] is bool
            ? json['enabled'] as bool
            : fallback.enabled,
      );
}

/// Structure identity never has a level. This profile describes only the
/// optional module sockets available on each concrete structure type.
class ElevageStructureModuleProfile {
  const ElevageStructureModuleProfile({
    this.moduleSlots = 0,
    this.allowedModuleIds = const <String>[],
    this.primaryEnvironmentAxis,
  });

  final int moduleSlots;
  final List<String> allowedModuleIds;
  final String? primaryEnvironmentAxis;

  ElevageStructureModuleProfile copyWith({int? moduleSlots}) =>
      ElevageStructureModuleProfile(
        moduleSlots: moduleSlots ?? this.moduleSlots,
        allowedModuleIds: allowedModuleIds,
        primaryEnvironmentAxis: primaryEnvironmentAxis,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'moduleSlots': moduleSlots,
        'allowedModuleIds': allowedModuleIds,
        'primaryEnvironmentAxis': primaryEnvironmentAxis,
      };

  factory ElevageStructureModuleProfile.fromJson(
          Map<String, dynamic> json, ElevageStructureModuleProfile fallback) =>
      ElevageStructureModuleProfile(
        moduleSlots: _nonNegative(json['moduleSlots'], fallback.moduleSlots),
        allowedModuleIds: List<String>.from(
            json['allowedModuleIds'] as List? ?? fallback.allowedModuleIds),
        primaryEnvironmentAxis: json['primaryEnvironmentAxis'] as String? ??
            fallback.primaryEnvironmentAxis,
      );
}

/// Module effects are data, not widget conditionals. V1 resolves additive
/// values first then multiplicative values, independently of installed order.
class ElevageModuleDefinition {
  const ElevageModuleDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.category,
    required this.compatibleStructures,
    this.effects = const <String, num>{},
    this.icon = 'extension',
    this.enabled = true,
    this.stackable = false,
    this.maxStacksPerStructure = 1,
    this.organicCost = 0,
    this.mineralCost = 0,
  });

  final String id;
  final String label;
  final String description;
  final String category;
  final List<String> compatibleStructures;
  final Map<String, num> effects;
  final String icon;
  final bool enabled;
  final bool stackable;
  final int maxStacksPerStructure;
  final int organicCost;
  final int mineralCost;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'description': description,
        'category': category,
        'compatibleStructures': compatibleStructures,
        'effects': effects,
        'icon': icon,
        'enabled': enabled,
        'stackable': stackable,
        'maxStacksPerStructure': maxStacksPerStructure,
        'organicCost': organicCost,
        'mineralCost': mineralCost,
      };

  ElevageModuleDefinition copyWith({
    bool? enabled,
    bool? stackable,
    int? maxStacksPerStructure,
    Map<String, num>? effects,
    int? organicCost,
    int? mineralCost,
  }) =>
      ElevageModuleDefinition(
        id: id,
        label: label,
        description: description,
        category: category,
        compatibleStructures: compatibleStructures,
        effects: effects ?? this.effects,
        icon: icon,
        enabled: enabled ?? this.enabled,
        stackable: stackable ?? this.stackable,
        maxStacksPerStructure:
            maxStacksPerStructure ?? this.maxStacksPerStructure,
        organicCost: organicCost ?? this.organicCost,
        mineralCost: mineralCost ?? this.mineralCost,
      );

  factory ElevageModuleDefinition.fromJson(
          Map<String, dynamic> json, ElevageModuleDefinition fallback) =>
      fallback.copyWith(
        enabled: json['enabled'] is bool ? json['enabled'] as bool : null,
        stackable: json['stackable'] is bool ? json['stackable'] as bool : null,
        maxStacksPerStructure: _positive(
            json['maxStacksPerStructure'], fallback.maxStacksPerStructure),
        organicCost: _nonNegative(json['organicCost'], fallback.organicCost),
        mineralCost: _nonNegative(json['mineralCost'], fallback.mineralCost),
        effects: (json['effects'] as Map?)?.map(
                (key, value) => MapEntry('$key', value is num ? value : 0)) ??
            fallback.effects,
      );
}

/// One independently configurable output of a biological producer.  Keeping
/// the clock and cap on the output (rather than on the building) lets a full
/// ROOT stock pause while LEAF continues to grow.
class ElevageProductionOutput {
  const ElevageProductionOutput({
    required this.resourceId,
    required this.quantityPerCycle,
    required this.productionSeconds,
    required this.maxLocalStock,
    this.enabled = true,
  });

  final String resourceId;
  final int quantityPerCycle;
  final int productionSeconds;
  final int maxLocalStock;
  final bool enabled;

  ElevageProductionOutput copyWith({
    int? quantityPerCycle,
    int? productionSeconds,
    int? maxLocalStock,
    bool? enabled,
  }) =>
      ElevageProductionOutput(
        resourceId: resourceId,
        quantityPerCycle: quantityPerCycle ?? this.quantityPerCycle,
        productionSeconds: productionSeconds ?? this.productionSeconds,
        maxLocalStock: maxLocalStock ?? this.maxLocalStock,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'resourceId': resourceId,
        'quantityPerCycle': quantityPerCycle,
        'productionSeconds': productionSeconds,
        'maxLocalStock': maxLocalStock,
        'enabled': enabled,
      };

  factory ElevageProductionOutput.fromJson(
          Map<String, dynamic> json, ElevageProductionOutput fallback) =>
      ElevageProductionOutput(
        resourceId: fallback.resourceId,
        quantityPerCycle:
            _positive(json['quantityPerCycle'], fallback.quantityPerCycle),
        productionSeconds:
            _positive(json['productionSeconds'], fallback.productionSeconds),
        maxLocalStock: _positive(json['maxLocalStock'], fallback.maxLocalStock),
        enabled: json['enabled'] is bool
            ? json['enabled'] as bool
            : fallback.enabled,
      );
}

class ElevageInstallationDefinition {
  const ElevageInstallationDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.light,
    required this.temperature,
    required this.humidity,
    this.wellbeingImpact = 0,
    this.category = 'STRUCTURE',
    this.movableByPtipote = false,
    this.activity,
    this.decorCategory,
    this.resonanceMaterial,
    this.resonanceFamily,
    this.outputs = const <String, int>{},
  });

  final String id;
  final String label;

  /// Player-facing copy. Values and mechanics remain defined by this object.
  final String description;
  final int light;
  final int temperature;
  final int humidity;

  /// Base wellbeing change when a free habitat item is used. Environmental
  /// structures keep this at zero; furniture and decorations expose it to the
  /// local Dashboard without exposing their individual affinity logic.
  final int wellbeingImpact;

  /// STRUCTURE uses a technical Z1–Z4 slot; MEUBLE and DECORATION are free.
  final String category;
  final bool movableByPtipote;
  final String? activity;
  final String? decorCategory;
  final String? resonanceMaterial;

  /// Family accepted by a durable biological resonance support.
  final String? resonanceFamily;
  final Map<String, int> outputs;

  bool get productive => outputs.isNotEmpty;

  ElevageInstallationDefinition copyWith({
    int? light,
    int? temperature,
    int? humidity,
    int? wellbeingImpact,
  }) =>
      ElevageInstallationDefinition(
        id: id,
        label: label,
        description: description,
        light: light ?? this.light,
        temperature: temperature ?? this.temperature,
        humidity: humidity ?? this.humidity,
        wellbeingImpact: wellbeingImpact ?? this.wellbeingImpact,
        category: category,
        movableByPtipote: movableByPtipote,
        activity: activity,
        decorCategory: decorCategory,
        resonanceMaterial: resonanceMaterial,
        resonanceFamily: resonanceFamily,
        outputs: outputs,
      );
}

/// Four deliberately simple spatial contexts inside an Alcôve. Their effects
/// are relative gameplay values, just like the global Alcôve environment.
class ElevageSceneZone {
  const ElevageSceneZone({
    required this.id,
    required this.label,
    this.light = 0,
    this.temperature = 0,
    this.humidity = 0,
  });

  final String id;
  final String label;
  final int light;
  final int temperature;
  final int humidity;
}

class ElevageConfig {
  const ElevageConfig({
    required this.revision,
    required this.featureEnabled,
    required this.devMode,
    required this.preset,
    required this.alcoveCount,
    required this.installationSlotCount,
    required this.hungerNormalHours,
    required this.hungerHungryHours,
    required this.hungerVeryHungryHours,
    required this.suspectedThreshold,
    required this.confirmedThreshold,
    required this.foragingDurationSeconds,
    required this.productionIntervalSeconds,
    required this.productionMaxStock,
    required this.coRearingDurationHours,
    required this.refundOrganicRate,
    required this.refundMineralRate,
    required this.sourcierEnabled,
    required this.fibrousFruitPrice,
    required this.fruitJellyPrice,
    required this.buybackQuantity,
    required this.buybackBioPiles,
    required this.metamorphosisToleranceMs,
    required this.inventoryStackSize,
    required this.dayDurationHours,
    required this.nightDurationHours,
    required this.energyOrganicCost,
    required this.energyMineralCost,
    required this.energyProduced,
    required this.vegetalSleepMinutes,
    required this.mineralDaySleepMinutes,
    required this.mineralLateNightSleepMinutes,
    required this.fungalMidDaySleepMinutes,
    required this.fungalTransitionSleepMinutes,
    required this.observationTextThreshold,
    required this.observationEvidenceCooldownMinutes,
    required this.autonomousReactionIntervalSeconds,
    required this.objectReactionDelayMs,
    required this.idlePauseSeconds,
    required this.normalMoveDurationMs,
    required this.runMoveDurationMs,
    required this.personalityBaselineWeight,
    required this.personalityBabyWeight,
    required this.personalityIntermediateWeight,
    required this.personalityAdultPlasticityWeight,
    required this.warmCuddleCooldownSeconds,
    required this.reservedCuddleCooldownSeconds,
    required this.requestDurationSeconds,
    required this.baseHumidity,
    required this.baseTemperature,
    required this.dayTemperatureDelta,
    required this.strongShadeTemperatureDelta,
    required this.reactionBubbleSeconds,
    required this.absorptionBubbleSeconds,
    required this.longPressHoldSeconds,
    required this.wakeGraceSeconds,
    required this.baseStayBabySeconds,
    required this.baseStayIntermediateSeconds,
    required this.baseStayMatureSeconds,
    required this.tempoPosedStayModifierSeconds,
    required this.tempoSpontaneousStayModifierSeconds,
    required this.perfectZoneStayModifierSeconds,
    required this.badZoneStayModifierSeconds,
    required this.extremeZoneStayModifierSeconds,
    required this.minStaySeconds,
    required this.resonanceGainPerUse,
    required this.vocalizations,
    required this.recycleRules,
    required this.recipes,
    required this.natureProfiles,
    this.producerOutputs = const <String, List<ElevageProductionOutput>>{},
    this.installationEffects = const <String, Map<String, int>>{},
    this.structureConsumptions = const <String, ElevageStructureConsumption>{},
    this.structureModules = const <String, ElevageStructureModuleProfile>{},
    this.modules = const <String, ElevageModuleDefinition>{},
    this.refugeProgression = const <String, dynamic>{},
  });

  final String revision;
  final bool featureEnabled;
  final bool devMode;
  final ElevagePreset preset;
  final int alcoveCount;
  final int installationSlotCount;
  final int hungerNormalHours;
  final int hungerHungryHours;
  final int hungerVeryHungryHours;
  final int suspectedThreshold;
  final int confirmedThreshold;
  final int foragingDurationSeconds;
  final int productionIntervalSeconds;
  final int productionMaxStock;
  final int coRearingDurationHours;
  final double refundOrganicRate;
  final double refundMineralRate;
  final bool sourcierEnabled;
  final int fibrousFruitPrice;
  final int fruitJellyPrice;
  final int buybackQuantity;
  final int buybackBioPiles;
  final int metamorphosisToleranceMs;
  final int inventoryStackSize;
  final int dayDurationHours;
  final int nightDurationHours;
  final int energyOrganicCost;
  final int energyMineralCost;
  final int energyProduced;

  /// Durées réglables des fenêtres circadiennes. Les profils conservent leur
  /// position biologique (nuit, début de jour, etc.), mais ne dépendent plus
  /// de fractions codées en dur du cycle Jour/Nuit.
  final int vegetalSleepMinutes;
  final int mineralDaySleepMinutes;
  final int mineralLateNightSleepMinutes;
  final int fungalMidDaySleepMinutes;
  final int fungalTransitionSleepMinutes;
  final int observationTextThreshold;
  final int observationEvidenceCooldownMinutes;
  final int autonomousReactionIntervalSeconds;
  final int objectReactionDelayMs;
  final int idlePauseSeconds;
  final int normalMoveDurationMs;
  final int runMoveDurationMs;
  final double personalityBaselineWeight;
  final double personalityBabyWeight;
  final double personalityIntermediateWeight;
  final double personalityAdultPlasticityWeight;
  final int warmCuddleCooldownSeconds;
  final int reservedCuddleCooldownSeconds;
  final int requestDurationSeconds;

  /// Valeurs relatives converties vers l'échelle joueur avec +3. Elles sont
  /// explicites afin que les libellés de zones ne modifient jamais le climat.
  final int baseHumidity;
  final int baseTemperature;
  final int dayTemperatureDelta;
  final int strongShadeTemperatureDelta;
  final int reactionBubbleSeconds;
  final int absorptionBubbleSeconds;
  final int longPressHoldSeconds;
  final int wakeGraceSeconds;
  final int baseStayBabySeconds;
  final int baseStayIntermediateSeconds;
  final int baseStayMatureSeconds;
  final int tempoPosedStayModifierSeconds;
  final int tempoSpontaneousStayModifierSeconds;
  final int perfectZoneStayModifierSeconds;
  final int badZoneStayModifierSeconds;
  final int extremeZoneStayModifierSeconds;
  final int minStaySeconds;
  final int resonanceGainPerUse;
  final Map<String, String> vocalizations;
  final Map<String, ElevageRecycleRule> recycleRules;
  final List<ElevageRecipe> recipes;
  final List<ElevageNatureProfile> natureProfiles;

  /// Production is configured per resource, not as a hidden global building
  /// timer.  Only the three biological producers expose entries here.
  final Map<String, List<ElevageProductionOutput>> producerOutputs;

  /// Dashboard-only overrides. Structures expose light/temperature/humidity;
  /// furniture and decorations expose wellbeing only. Individual affinity
  /// remains part of the domain, not of the configuration UI.
  final Map<String, Map<String, int>> installationEffects;
  final Map<String, ElevageStructureConsumption> structureConsumptions;
  final Map<String, ElevageStructureModuleProfile> structureModules;
  final Map<String, ElevageModuleDefinition> modules;

  /// Paramètres de méta-progression du Refuge. Une map versionnable évite de
  /// figer prématurément une économie encore en prototypage, tout en gardant
  /// chaque valeur éditable depuis le Dashboard.
  final Map<String, dynamic> refugeProgression;

  int get startingAlcoveCount =>
      ((refugeProgression['startingAlcoveCount'] as num?)?.toInt() ?? 1)
          .clamp(1, alcoveCount);
  int get loanChoiceCount =>
      ((refugeProgression['loanChoiceCount'] as num?)?.toInt() ?? 2)
          .clamp(2, 2);
  int get loanReturnDelayDays =>
      ((refugeProgression['loanReturnDelayDays'] as num?)?.toInt() ?? 21)
          .clamp(1, 3650);
  int get startingBioBatteryCount =>
      ((refugeProgression['startingBioBatteryCount'] as num?)?.toInt() ?? 2)
          .clamp(0, 99);
  int get bioBatteryEnergy =>
      ((refugeProgression['bioBatteryEnergy'] as num?)?.toInt() ?? 10)
          .clamp(1, 999);
  List<Map<String, dynamic>> get alcoveRequirements =>
      ((refugeProgression['alcoveRequirements'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList(growable: false);

  Map<String, dynamic> get biogeneratorConfig => Map<String, dynamic>.from(
      refugeProgression['biogenerator'] as Map? ?? const <dynamic, dynamic>{});
  int _biogeneratorNumber(String key, int fallback) =>
      ((biogeneratorConfig[key] as num?)?.toInt() ?? fallback).clamp(1, 9999);
  int get biogeneratorOrganicTankCapacity =>
      _biogeneratorNumber('organicTankCapacity', 30);
  int get biogeneratorMineralTankCapacity =>
      _biogeneratorNumber('mineralTankCapacity', 10);
  int get biogeneratorOrganicCost =>
      _biogeneratorNumber('organicCostPerCycle', 3);
  int get biogeneratorMineralCost =>
      _biogeneratorNumber('mineralCostPerCycle', 2);
  int get biogeneratorEnergyPerCycle =>
      _biogeneratorNumber('energyPerCycle', 10);
  int get biogeneratorEfficiencyOrganicReduction =>
      ((biogeneratorConfig['efficiencyOrganicReduction'] as num?)?.toInt() ?? 1)
          .clamp(0, 999);
  int get biogeneratorEfficiencyMineralReduction =>
      ((biogeneratorConfig['efficiencyMineralReduction'] as num?)?.toInt() ?? 1)
          .clamp(0, 999);
  int get biogeneratorPowerEnergyBonus =>
      ((biogeneratorConfig['powerEnergyBonus'] as num?)?.toInt() ?? 5)
          .clamp(0, 9999);
  int get biogeneratorCapacityOrganicBonus =>
      ((biogeneratorConfig['capacityOrganicBonus'] as num?)?.toInt() ?? 10)
          .clamp(0, 9999);
  int get biogeneratorCapacityMineralBonus =>
      ((biogeneratorConfig['capacityMineralBonus'] as num?)?.toInt() ?? 10)
          .clamp(0, 9999);
  int get biogeneratorMinimumOrganicCost =>
      _biogeneratorNumber('minimumOrganicCost', 1);
  int get biogeneratorMinimumMineralCost =>
      _biogeneratorNumber('minimumMineralCost', 1);
  Map<String, dynamic> get trackerConfig => Map<String, dynamic>.from(
      refugeProgression['tracker'] as Map? ?? const <dynamic, dynamic>{});
  int trackerThreshold(int level) =>
      ((trackerConfig['xpForLevel$level'] as num?)?.toInt() ??
              <int>[0, 10, 30, 60][level.clamp(0, 3)])
          .clamp(0, 999999);
  int trackerCarryBonus(int level) =>
      ((trackerConfig['carryBonusByLevel'] as Map?)?['$level'] as num?)
          ?.toInt() ??
      level.clamp(0, 3);
  int get babyVocalCooldownSeconds =>
      ((refugeProgression['ambientFeedback']
              as Map?)?['babyVocalCooldownSeconds'] as num?)
          ?.toInt() ??
      3;
  Map<String, dynamic> get languageConfig => Map<String, dynamic>.from(
      refugeProgression['language'] as Map? ?? const <dynamic, dynamic>{});
  int get juvenileNewConceptWordThreshold =>
      ((languageConfig['juvenileNewConceptWordThreshold'] as num?)?.toInt() ??
              5)
          .clamp(1, 999);
  int get juvenileBabyKnownConceptWordThreshold =>
      ((languageConfig['juvenileBabyKnownConceptWordThreshold'] as num?)
                  ?.toInt() ??
              10)
          .clamp(1, 999);
  Map<String, dynamic> get knowledgeConfig => Map<String, dynamic>.from(
      refugeProgression['knowledge'] as Map? ?? const <dynamic, dynamic>{});
  int get observationsForHypothesis =>
      ((knowledgeConfig['observationsForHypothesis'] as num?)?.toInt() ?? 5)
          .clamp(1, 999);
  int get evidenceForConfirmation =>
      ((knowledgeConfig['evidenceForConfirmation'] as num?)?.toInt() ?? 5)
          .clamp(1, 999);
  Map<String, dynamic> get maturationConfig => Map<String, dynamic>.from(
      refugeProgression['maturation'] as Map? ?? const <dynamic, dynamic>{});
  int get maturationObservationRequirement =>
      ((maturationConfig['observationRequirement'] as num?)?.toInt() ?? 4)
          .clamp(0, 999);
  int get maturationHypothesisRequirement =>
      ((maturationConfig['hypothesisRequirement'] as num?)?.toInt() ?? 3)
          .clamp(0, 999);
  int get maturationConfirmationRequirement =>
      ((maturationConfig['confirmationRequirement'] as num?)?.toInt() ?? 1)
          .clamp(0, 999);
  Map<String, dynamic> get tamTamConfig => Map<String, dynamic>.from(
      refugeProgression['tamTam'] as Map? ?? const <dynamic, dynamic>{});
  int get tamTamTotalBeats =>
      ((tamTamConfig['totalBeats'] as num?)?.toInt() ?? 3).clamp(1, 32);
  int get tamTamRequiredSuccessfulBeats =>
      ((tamTamConfig['requiredSuccessfulBeats'] as num?)?.toInt() ?? 3)
          .clamp(1, tamTamTotalBeats);
  int get tamTamBeatIntervalMs =>
      ((tamTamConfig['beatIntervalMs'] as num?)?.toInt() ?? 700)
          .clamp(100, 10000);
  int get tamTamPerfectWindowMs =>
      ((tamTamConfig['perfectWindowMs'] as num?)?.toInt() ?? 120)
          .clamp(1, 5000);
  int get tamTamGoodWindowMs =>
      ((tamTamConfig['goodWindowMs'] as num?)?.toInt() ?? 240)
          .clamp(tamTamPerfectWindowMs, 10000)
          .toInt();

  Map<String, dynamic> requirementForAlcove(int index) =>
      index <= 1 || index - 2 >= alcoveRequirements.length
          ? const <String, dynamic>{}
          : alcoveRequirements[index - 2];

  int get babyMinimumHours => preset == ElevagePreset.prototype ? 24 : 48;
  int get intermediateMinimumHours =>
      preset == ElevagePreset.prototype ? 72 : 168;
  int get dayNightCycleHours => dayDurationHours + nightDurationHours;

  ElevageNatureProfile natureProfile(String family, String nature) {
    return natureProfiles.firstWhere(
        (profile) => profile.family == family && profile.nature == nature,
        orElse: () => natureProfiles
            .firstWhere((profile) => profile.id == 'MINERAL_RESONANCE'));
  }

  ElevageNatureProfile profileForIndividual(Map individual) => natureProfile(
      individual['family'] as String? ?? 'MINERAL',
      individual['nature'] as String? ?? 'RESONANCE');

  ElevageRecycleRule? recycleRule(String itemId) => recycleRules[itemId];
  ElevageStructureConsumption consumptionFor(String installationId) =>
      structureConsumptions[installationId] ??
      const ElevageStructureConsumption();
  ElevageStructureModuleProfile modulesFor(String installationId) =>
      structureModules[installationId] ?? const ElevageStructureModuleProfile();
  ElevageModuleDefinition? module(String id) => modules[id];

  List<ElevageInstallationDefinition> get _defaultInstallations =>
      <ElevageInstallationDefinition>[
        const ElevageInstallationDefinition(
          id: 'BASSIN',
          label: 'Bassin',
          description:
              'Un petit milieu humide où peuvent se développer algues et mousses.',
          light: 0,
          temperature: 0,
          humidity: 2,
          outputs: <String, int>{'ALGAE': 1, 'MOSS': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'MOSS_STONE',
          label: 'Pierre de mousse',
          description: 'Une pierre fraîche recouverte de mousse.',
          light: 0,
          temperature: -1,
          humidity: 2,
        ),
        const ElevageInstallationDefinition(
          id: 'CULTURE_POTAGERE',
          label: 'Culture potagère',
          description:
              'Un coin de culture qui fait pousser racines et feuilles.',
          light: 0,
          temperature: 0,
          humidity: 0,
          outputs: <String, int>{'ROOT': 1, 'LEAF': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'BUTTE_ARBUSTE',
          label: 'Butte d’arbuste',
          description: 'Une petite butte végétale où mûrissent des fruits.',
          light: 0,
          temperature: 0,
          humidity: 0,
          outputs: <String, int>{'FRUIT': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'SUPPORT_FONGIQUE',
          label: 'Support fongique',
          description:
              'Permet la culture progressive de champignons utilisables comme ressource organique.',
          light: 0,
          temperature: 0,
          humidity: 1,
          outputs: <String, int>{'MUSHROOM': 1},
        ),
        const ElevageInstallationDefinition(
          id: 'FORMATION_METALLIQUE',
          label: 'Formation métallique',
          description:
              'Un support durable où les P’TIPOTES minéraux peuvent entrer en résonance.',
          light: 0,
          temperature: 0,
          humidity: 0,
          resonanceMaterial: 'IRON',
        ),
        const ElevageInstallationDefinition(
          id: 'FORMATION_CRISTALLINE',
          label: 'Formation cristalline',
          description:
              'Un support durable de résonance cristalline, sans produire de matière.',
          light: 0,
          temperature: 0,
          humidity: 0,
          resonanceMaterial: 'QUARTZ',
        ),
        const ElevageInstallationDefinition(
          id: 'FORMATION_MINERALE',
          label: 'Formation minérale',
          description: 'Un support minéral durable pour une résonance lente.',
          light: 0,
          temperature: 0,
          humidity: 0,
          resonanceMaterial: 'LIMESTONE',
          resonanceFamily: 'MINERAL',
        ),
        const ElevageInstallationDefinition(
          id: 'BOSQUET_SYMBIOTIQUE',
          label: 'Bosquet symbiotique',
          description:
              'Écosystème végétal dense où les P’TIPOTES végétaux renforcent progressivement leur structure.',
          light: 0,
          temperature: 0,
          humidity: 1,
          resonanceFamily: 'VEGETAL',
        ),
        const ElevageInstallationDefinition(
          id: 'COLONIE_MYCELIENNE',
          label: 'Colonie mycélienne',
          description:
              'Réseau durable où les P’TIPOTES fongiques renforcent progressivement leur structure.',
          light: -1,
          temperature: 0,
          humidity: 1,
          resonanceFamily: 'FUNGAL',
        ),
        const ElevageInstallationDefinition(
          id: 'LAMPE_SOLAIRE',
          label: 'Lampe solaire',
          description:
              'Une lampe qui éclaire et réchauffe légèrement l’Alcôve.',
          light: 2,
          temperature: 1,
          humidity: 0,
        ),
        const ElevageInstallationDefinition(
          id: 'ABRI_FIBREUX',
          label: 'Abri fibreux',
          description:
              'Un abri tressé qui apporte de l’ombre et de la fraîcheur.',
          light: -2,
          temperature: -1,
          humidity: 0,
        ),
        const ElevageInstallationDefinition(
          id: 'ABRI_MINERAL_PROFOND',
          label: 'Abri minéral profond',
          description: 'Un refuge profond, sombre et frais, mais plus humide.',
          light: -2,
          temperature: -2,
          humidity: 1,
        ),
        const ElevageInstallationDefinition(
          id: 'VENTILATION',
          label: 'Ventilation',
          description: 'Un courant d’air qui rafraîchit et assèche légèrement.',
          light: 0,
          temperature: -2,
          humidity: -2,
        ),
        const ElevageInstallationDefinition(
          id: 'FOUR_BIO_ORGANIQUE',
          label: 'Four bio-organique',
          description:
              'Un four vivant qui réchauffe l’espace en consommant de l’Organique.',
          light: 0,
          temperature: 2,
          humidity: -1,
        ),
        const ElevageInstallationDefinition(
          id: 'TOIT_SERRE',
          label: 'Toit de serre',
          description: 'Un toit transparent qui augmente lumière et chaleur.',
          light: 1,
          temperature: 2,
          humidity: 0,
        ),
        const ElevageInstallationDefinition(
          id: 'HAMAC',
          label: 'Hamac',
          description: 'Un meuble de repos court et de détente calme.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'REST',
        ),
        const ElevageInstallationDefinition(
          id: 'NID_COUCHETTE',
          label: 'Nid / couchette',
          description: 'Un coin calme pour les pauses et le repos.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'REST',
        ),
        const ElevageInstallationDefinition(
          id: 'POTAGER_VERTICAL',
          label: 'Potager vertical',
          description:
              'Une station végétale pour manipuler pousses et substrat.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'GARDEN',
        ),
        const ElevageInstallationDefinition(
          id: 'LITIERE_FONGIQUE',
          label: 'Litière fongique',
          description: 'Un substrat souple pour creuser et redistribuer.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'DIG',
        ),
        const ElevageInstallationDefinition(
          id: 'BAC_GRAVIER',
          label: 'Bac à gravier',
          description:
              'Un bac minéral pour fouiller, trier et déplacer des pierres.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'SORT',
        ),
        const ElevageInstallationDefinition(
          id: 'BIBLIOTHEQUE_DATABUG',
          label: 'Bibliothèque Databug',
          description: 'Une station de curiosité et d’observation lente.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'READ',
        ),
        const ElevageInstallationDefinition(
          id: 'PARCOURS_OBSTACLES',
          label: 'Parcours d’obstacles',
          description: 'Une station d’activité physique et d’exploration.',
          light: 0,
          temperature: 0,
          humidity: 0,
          category: 'MEUBLE',
          movableByPtipote: true,
          activity: 'PLAY',
        ),
        const ElevageInstallationDefinition(
            id: 'PLANTE_DECORATIVE',
            label: 'Plante décorative',
            description: 'Une petite plante libre à observer.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'VEGETAL'),
        const ElevageInstallationDefinition(
            id: 'MOUSSE_DECORATIVE',
            label: 'Mousse décorative',
            description: 'Un coussin végétal doux et discret.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MOSS'),
        const ElevageInstallationDefinition(
            id: 'CRISTAL_DECORATIF',
            label: 'Cristal décoratif',
            description:
                'Un petit cristal dont l’intérêt dépend de chaque individu.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'CRYSTAL'),
        const ElevageInstallationDefinition(
            id: 'GEODE_DECORATIVE',
            label: 'Géode décorative',
            description:
                'Une géode libre, décorative et potentiellement favorite.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MINERAL'),
        const ElevageInstallationDefinition(
            id: 'PIERRE_DECORATIVE',
            label: 'Pierre décorative',
            description: 'Une pierre libre à rapprocher de son coin préféré.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MINERAL'),
        const ElevageInstallationDefinition(
            id: 'CARILLON',
            label: 'Carillon',
            description: 'Un objet musical doux selon les goûts individuels.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MUSIC_SOFT'),
        const ElevageInstallationDefinition(
            id: 'CONQUE_MUSICALE',
            label: 'Conque musicale',
            description: 'Un objet musical rythmé selon les goûts individuels.',
            light: 0,
            temperature: 0,
            humidity: 0,
            category: 'DECORATION',
            movableByPtipote: true,
            decorCategory: 'MUSIC_ENERGETIC'),
      ];

  List<ElevageInstallationDefinition> get installations =>
      _defaultInstallations.map((definition) {
        // All free habitat items start with the same small, readable wellbeing
        // effect. Their individual affinity remains evaluated by the engine.
        final base = definition.category == 'STRUCTURE'
            ? definition
            : definition.copyWith(wellbeingImpact: 1);
        final override = installationEffects[definition.id];
        if (override == null) return base;
        return base.copyWith(
          light: override['light'],
          temperature: override['temperature'],
          humidity: override['humidity'],
          wellbeingImpact: override['wellbeing'],
        );
      }).toList(growable: false);

  List<ElevageSceneZone> get sceneZones => const <ElevageSceneZone>[
        ElevageSceneZone(id: 'ZONE_1', label: 'Abri ombragé', light: 2),
        ElevageSceneZone(id: 'ZONE_2', label: 'Nid central', light: 3),
        ElevageSceneZone(id: 'ZONE_3', label: 'Coin central', light: 3),
        ElevageSceneZone(id: 'ZONE_4', label: 'Bord éclairé', light: 4),
      ];

  /// Jour : 2 / 3 / 3 / 4 sur l’échelle joueur 1–5. La nuit reste discrète
  /// et centralisée : Z1–Z3 sombrent, Z4 garde une lumière résiduelle.
  int nightLightOffset(String zoneId) => switch (zoneId) {
        // Les bases jour sont 2 / 3 / 3 / 4 ; la nuit est 1 / 2 / 2 / 3.
        'ZONE_1' || 'ZONE_2' || 'ZONE_3' || 'ZONE_4' => -1,
        _ => 0,
      };

  /// Seuils de confort lumineux du profil Résonance V0, consultés par le
  /// domaine ; ils ne sont jamais recopiés dans l’interface.
  int resonanceLightComfort(int lightScale) => switch (lightScale) {
        1 || 2 => 1,
        3 => 0,
        4 => -1,
        _ => -2,
      };

  String resonanceAxisComfort(String axis, int scale) {
    return natureProfile('MINERAL', 'RESONANCE').axisComfort(axis, scale);
  }

  ElevageInstallationDefinition? installation(String id) {
    final normalized = switch (id) {
      'GEODE_FERRIQUE' => 'FORMATION_METALLIQUE',
      'GEODE_CRISTALLINE' => 'FORMATION_CRISTALLINE',
      _ => id,
    };
    for (final definition in installations) {
      if (definition.id == normalized) return definition;
    }
    return null;
  }

  List<ElevageProductionOutput> outputsFor(String installationId) =>
      producerOutputs[installationId] ?? const <ElevageProductionOutput>[];

  ElevageSceneZone? sceneZone(String id) {
    for (final zone in sceneZones) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  ElevageConfig copyWith({
    String? revision,
    bool? featureEnabled,
    bool? devMode,
    ElevagePreset? preset,
    int? alcoveCount,
    int? hungerNormalHours,
    int? hungerHungryHours,
    int? hungerVeryHungryHours,
    int? suspectedThreshold,
    int? confirmedThreshold,
    int? foragingDurationSeconds,
    int? productionIntervalSeconds,
    int? productionMaxStock,
    int? coRearingDurationHours,
    double? refundOrganicRate,
    double? refundMineralRate,
    bool? sourcierEnabled,
    int? fibrousFruitPrice,
    int? fruitJellyPrice,
    int? buybackQuantity,
    int? buybackBioPiles,
    int? metamorphosisToleranceMs,
    int? inventoryStackSize,
    int? dayDurationHours,
    int? nightDurationHours,
    int? energyOrganicCost,
    int? energyMineralCost,
    int? energyProduced,
    int? vegetalSleepMinutes,
    int? mineralDaySleepMinutes,
    int? mineralLateNightSleepMinutes,
    int? fungalMidDaySleepMinutes,
    int? fungalTransitionSleepMinutes,
    int? observationTextThreshold,
    int? observationEvidenceCooldownMinutes,
    int? autonomousReactionIntervalSeconds,
    int? objectReactionDelayMs,
    int? idlePauseSeconds,
    int? normalMoveDurationMs,
    int? runMoveDurationMs,
    double? personalityBaselineWeight,
    double? personalityBabyWeight,
    double? personalityIntermediateWeight,
    double? personalityAdultPlasticityWeight,
    int? warmCuddleCooldownSeconds,
    int? reservedCuddleCooldownSeconds,
    int? requestDurationSeconds,
    int? baseHumidity,
    int? baseTemperature,
    int? dayTemperatureDelta,
    int? strongShadeTemperatureDelta,
    int? reactionBubbleSeconds,
    int? absorptionBubbleSeconds,
    int? longPressHoldSeconds,
    int? wakeGraceSeconds,
    int? baseStayBabySeconds,
    int? baseStayIntermediateSeconds,
    int? baseStayMatureSeconds,
    int? tempoPosedStayModifierSeconds,
    int? tempoSpontaneousStayModifierSeconds,
    int? perfectZoneStayModifierSeconds,
    int? badZoneStayModifierSeconds,
    int? extremeZoneStayModifierSeconds,
    int? minStaySeconds,
    int? resonanceGainPerUse,
    Map<String, String>? vocalizations,
    Map<String, ElevageRecycleRule>? recycleRules,
    List<ElevageRecipe>? recipes,
    List<ElevageNatureProfile>? natureProfiles,
    Map<String, List<ElevageProductionOutput>>? producerOutputs,
    Map<String, Map<String, int>>? installationEffects,
    Map<String, ElevageStructureConsumption>? structureConsumptions,
    Map<String, ElevageStructureModuleProfile>? structureModules,
    Map<String, ElevageModuleDefinition>? modules,
    Map<String, dynamic>? refugeProgression,
  }) =>
      ElevageConfig(
        revision: revision ?? this.revision,
        featureEnabled: featureEnabled ?? this.featureEnabled,
        devMode: devMode ?? this.devMode,
        preset: preset ?? this.preset,
        alcoveCount: alcoveCount ?? this.alcoveCount,
        installationSlotCount: installationSlotCount,
        hungerNormalHours: hungerNormalHours ?? this.hungerNormalHours,
        hungerHungryHours: hungerHungryHours ?? this.hungerHungryHours,
        hungerVeryHungryHours:
            hungerVeryHungryHours ?? this.hungerVeryHungryHours,
        suspectedThreshold: suspectedThreshold ?? this.suspectedThreshold,
        confirmedThreshold: confirmedThreshold ?? this.confirmedThreshold,
        foragingDurationSeconds:
            foragingDurationSeconds ?? this.foragingDurationSeconds,
        productionIntervalSeconds:
            productionIntervalSeconds ?? this.productionIntervalSeconds,
        productionMaxStock: productionMaxStock ?? this.productionMaxStock,
        coRearingDurationHours:
            coRearingDurationHours ?? this.coRearingDurationHours,
        refundOrganicRate: refundOrganicRate ?? this.refundOrganicRate,
        refundMineralRate: refundMineralRate ?? this.refundMineralRate,
        sourcierEnabled: sourcierEnabled ?? this.sourcierEnabled,
        fibrousFruitPrice: fibrousFruitPrice ?? this.fibrousFruitPrice,
        fruitJellyPrice: fruitJellyPrice ?? this.fruitJellyPrice,
        buybackQuantity: buybackQuantity ?? this.buybackQuantity,
        buybackBioPiles: buybackBioPiles ?? this.buybackBioPiles,
        metamorphosisToleranceMs:
            metamorphosisToleranceMs ?? this.metamorphosisToleranceMs,
        inventoryStackSize: inventoryStackSize ?? this.inventoryStackSize,
        dayDurationHours: dayDurationHours ?? this.dayDurationHours,
        nightDurationHours: nightDurationHours ?? this.nightDurationHours,
        energyOrganicCost: energyOrganicCost ?? this.energyOrganicCost,
        energyMineralCost: energyMineralCost ?? this.energyMineralCost,
        energyProduced: energyProduced ?? this.energyProduced,
        vegetalSleepMinutes: vegetalSleepMinutes ?? this.vegetalSleepMinutes,
        mineralDaySleepMinutes:
            mineralDaySleepMinutes ?? this.mineralDaySleepMinutes,
        mineralLateNightSleepMinutes:
            mineralLateNightSleepMinutes ?? this.mineralLateNightSleepMinutes,
        fungalMidDaySleepMinutes:
            fungalMidDaySleepMinutes ?? this.fungalMidDaySleepMinutes,
        fungalTransitionSleepMinutes:
            fungalTransitionSleepMinutes ?? this.fungalTransitionSleepMinutes,
        observationTextThreshold:
            observationTextThreshold ?? this.observationTextThreshold,
        observationEvidenceCooldownMinutes:
            observationEvidenceCooldownMinutes ??
                this.observationEvidenceCooldownMinutes,
        autonomousReactionIntervalSeconds: autonomousReactionIntervalSeconds ??
            this.autonomousReactionIntervalSeconds,
        objectReactionDelayMs:
            objectReactionDelayMs ?? this.objectReactionDelayMs,
        idlePauseSeconds: idlePauseSeconds ?? this.idlePauseSeconds,
        normalMoveDurationMs: normalMoveDurationMs ?? this.normalMoveDurationMs,
        runMoveDurationMs: runMoveDurationMs ?? this.runMoveDurationMs,
        personalityBaselineWeight:
            personalityBaselineWeight ?? this.personalityBaselineWeight,
        personalityBabyWeight:
            personalityBabyWeight ?? this.personalityBabyWeight,
        personalityIntermediateWeight:
            personalityIntermediateWeight ?? this.personalityIntermediateWeight,
        personalityAdultPlasticityWeight: personalityAdultPlasticityWeight ??
            this.personalityAdultPlasticityWeight,
        warmCuddleCooldownSeconds:
            warmCuddleCooldownSeconds ?? this.warmCuddleCooldownSeconds,
        reservedCuddleCooldownSeconds:
            reservedCuddleCooldownSeconds ?? this.reservedCuddleCooldownSeconds,
        requestDurationSeconds:
            requestDurationSeconds ?? this.requestDurationSeconds,
        baseHumidity: baseHumidity ?? this.baseHumidity,
        baseTemperature: baseTemperature ?? this.baseTemperature,
        dayTemperatureDelta: dayTemperatureDelta ?? this.dayTemperatureDelta,
        strongShadeTemperatureDelta:
            strongShadeTemperatureDelta ?? this.strongShadeTemperatureDelta,
        reactionBubbleSeconds:
            reactionBubbleSeconds ?? this.reactionBubbleSeconds,
        absorptionBubbleSeconds:
            absorptionBubbleSeconds ?? this.absorptionBubbleSeconds,
        longPressHoldSeconds: longPressHoldSeconds ?? this.longPressHoldSeconds,
        wakeGraceSeconds: wakeGraceSeconds ?? this.wakeGraceSeconds,
        baseStayBabySeconds: baseStayBabySeconds ?? this.baseStayBabySeconds,
        baseStayIntermediateSeconds:
            baseStayIntermediateSeconds ?? this.baseStayIntermediateSeconds,
        baseStayMatureSeconds:
            baseStayMatureSeconds ?? this.baseStayMatureSeconds,
        tempoPosedStayModifierSeconds:
            tempoPosedStayModifierSeconds ?? this.tempoPosedStayModifierSeconds,
        tempoSpontaneousStayModifierSeconds:
            tempoSpontaneousStayModifierSeconds ??
                this.tempoSpontaneousStayModifierSeconds,
        perfectZoneStayModifierSeconds: perfectZoneStayModifierSeconds ??
            this.perfectZoneStayModifierSeconds,
        badZoneStayModifierSeconds:
            badZoneStayModifierSeconds ?? this.badZoneStayModifierSeconds,
        extremeZoneStayModifierSeconds: extremeZoneStayModifierSeconds ??
            this.extremeZoneStayModifierSeconds,
        minStaySeconds: minStaySeconds ?? this.minStaySeconds,
        resonanceGainPerUse: resonanceGainPerUse ?? this.resonanceGainPerUse,
        vocalizations: vocalizations ?? this.vocalizations,
        recycleRules: recycleRules ?? this.recycleRules,
        recipes: recipes ?? this.recipes,
        natureProfiles: natureProfiles ?? this.natureProfiles,
        producerOutputs: producerOutputs ??
            ((productionIntervalSeconds != null || productionMaxStock != null)
                ? this.producerOutputs.map((installation, outputs) => MapEntry(
                    installation,
                    outputs
                        .map((output) => output.copyWith(
                            productionSeconds: productionIntervalSeconds,
                            maxLocalStock: productionMaxStock))
                        .toList(growable: false)))
                : this.producerOutputs),
        installationEffects: installationEffects ?? this.installationEffects,
        structureConsumptions:
            structureConsumptions ?? this.structureConsumptions,
        structureModules: structureModules ?? this.structureModules,
        modules: modules ?? this.modules,
        refugeProgression: refugeProgression ?? this.refugeProgression,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': elevageConfigSchemaVersion,
        'revision': revision,
        'featureEnabled': featureEnabled,
        'devMode': devMode,
        'preset': preset.name,
        'alcoveCount': alcoveCount,
        'installationSlotCount': installationSlotCount,
        'hungerNormalHours': hungerNormalHours,
        'hungerHungryHours': hungerHungryHours,
        'hungerVeryHungryHours': hungerVeryHungryHours,
        'suspectedThreshold': suspectedThreshold,
        'confirmedThreshold': confirmedThreshold,
        'foragingDurationSeconds': foragingDurationSeconds,
        'productionIntervalSeconds': productionIntervalSeconds,
        'productionMaxStock': productionMaxStock,
        'coRearingDurationHours': coRearingDurationHours,
        'refundOrganicRate': refundOrganicRate,
        'refundMineralRate': refundMineralRate,
        'sourcierEnabled': sourcierEnabled,
        'fibrousFruitPrice': fibrousFruitPrice,
        'fruitJellyPrice': fruitJellyPrice,
        'buybackQuantity': buybackQuantity,
        'buybackBioPiles': buybackBioPiles,
        'metamorphosisToleranceMs': metamorphosisToleranceMs,
        'inventoryStackSize': inventoryStackSize,
        'dayDurationHours': dayDurationHours,
        'nightDurationHours': nightDurationHours,
        'energyOrganicCost': energyOrganicCost,
        'energyMineralCost': energyMineralCost,
        'energyProduced': energyProduced,
        'vegetalSleepMinutes': vegetalSleepMinutes,
        'mineralDaySleepMinutes': mineralDaySleepMinutes,
        'mineralLateNightSleepMinutes': mineralLateNightSleepMinutes,
        'fungalMidDaySleepMinutes': fungalMidDaySleepMinutes,
        'fungalTransitionSleepMinutes': fungalTransitionSleepMinutes,
        'observationTextThreshold': observationTextThreshold,
        'observationEvidenceCooldownMinutes':
            observationEvidenceCooldownMinutes,
        'autonomousReactionIntervalSeconds': autonomousReactionIntervalSeconds,
        'objectReactionDelayMs': objectReactionDelayMs,
        'idlePauseSeconds': idlePauseSeconds,
        'normalMoveDurationMs': normalMoveDurationMs,
        'runMoveDurationMs': runMoveDurationMs,
        'personalityBaselineWeight': personalityBaselineWeight,
        'personalityBabyWeight': personalityBabyWeight,
        'personalityIntermediateWeight': personalityIntermediateWeight,
        'personalityAdultPlasticityWeight': personalityAdultPlasticityWeight,
        'warmCuddleCooldownSeconds': warmCuddleCooldownSeconds,
        'reservedCuddleCooldownSeconds': reservedCuddleCooldownSeconds,
        'requestDurationSeconds': requestDurationSeconds,
        'baseHumidity': baseHumidity,
        'baseTemperature': baseTemperature,
        'dayTemperatureDelta': dayTemperatureDelta,
        'strongShadeTemperatureDelta': strongShadeTemperatureDelta,
        'reactionBubbleSeconds': reactionBubbleSeconds,
        'absorptionBubbleSeconds': absorptionBubbleSeconds,
        'longPressHoldSeconds': longPressHoldSeconds,
        'wakeGraceSeconds': wakeGraceSeconds,
        'baseStayBabySeconds': baseStayBabySeconds,
        'baseStayIntermediateSeconds': baseStayIntermediateSeconds,
        'baseStayMatureSeconds': baseStayMatureSeconds,
        'tempoPosedStayModifierSeconds': tempoPosedStayModifierSeconds,
        'tempoSpontaneousStayModifierSeconds':
            tempoSpontaneousStayModifierSeconds,
        'perfectZoneStayModifierSeconds': perfectZoneStayModifierSeconds,
        'badZoneStayModifierSeconds': badZoneStayModifierSeconds,
        'extremeZoneStayModifierSeconds': extremeZoneStayModifierSeconds,
        'minStaySeconds': minStaySeconds,
        'resonanceGainPerUse': resonanceGainPerUse,
        'vocalizations': vocalizations,
        'recycleRules':
            recycleRules.map((itemId, rule) => MapEntry(itemId, rule.toJson())),
        'recipes': recipes.map((recipe) => recipe.toJson()).toList(),
        'natureProfiles':
            natureProfiles.map((profile) => profile.toJson()).toList(),
        'producerOutputs': producerOutputs.map((installation, outputs) =>
            MapEntry(installation,
                outputs.map((output) => output.toJson()).toList())),
        'installationEffects': installationEffects,
        'structureConsumptions': structureConsumptions.map(
            (installationId, consumption) =>
                MapEntry(installationId, consumption.toJson())),
        'structureModules': structureModules.map((installationId, profile) =>
            MapEntry(installationId, profile.toJson())),
        'modules': modules
            .map((moduleId, module) => MapEntry(moduleId, module.toJson())),
        'refugeProgression': refugeProgression,
      };

  factory ElevageConfig.fromJson(Map<String, dynamic> json) {
    const base = defaultElevageConfig;
    final config = base.copyWith(
      revision: json['revision'] as String? ?? base.revision,
      featureEnabled: json['featureEnabled'] as bool? ?? base.featureEnabled,
      devMode: json['devMode'] as bool? ?? base.devMode,
      preset: ElevagePreset.values
          .byName(json['preset'] as String? ?? base.preset.name),
      alcoveCount: _positive(json['alcoveCount'], base.alcoveCount),
      refugeProgression: json['refugeProgression'] is Map
          ? Map<String, dynamic>.from(json['refugeProgression'] as Map)
          : base.refugeProgression,
      hungerNormalHours:
          _nonNegative(json['hungerNormalHours'], base.hungerNormalHours),
      hungerHungryHours:
          _nonNegative(json['hungerHungryHours'], base.hungerHungryHours),
      hungerVeryHungryHours: _nonNegative(
          json['hungerVeryHungryHours'], base.hungerVeryHungryHours),
      suspectedThreshold:
          _positive(json['suspectedThreshold'], base.suspectedThreshold),
      confirmedThreshold:
          _positive(json['confirmedThreshold'], base.confirmedThreshold),
      foragingDurationSeconds: _positive(
          json['foragingDurationSeconds'], base.foragingDurationSeconds),
      productionIntervalSeconds: _positive(
          json['productionIntervalSeconds'], base.productionIntervalSeconds),
      productionMaxStock:
          _positive(json['productionMaxStock'], base.productionMaxStock),
      coRearingDurationHours: _positive(
          json['coRearingDurationHours'], base.coRearingDurationHours),
      refundOrganicRate:
          _rate(json['refundOrganicRate'], base.refundOrganicRate),
      refundMineralRate:
          _rate(json['refundMineralRate'], base.refundMineralRate),
      sourcierEnabled: json['sourcierEnabled'] as bool? ?? base.sourcierEnabled,
      fibrousFruitPrice:
          _nonNegative(json['fibrousFruitPrice'], base.fibrousFruitPrice),
      fruitJellyPrice:
          _nonNegative(json['fruitJellyPrice'], base.fruitJellyPrice),
      buybackQuantity: _positive(json['buybackQuantity'], base.buybackQuantity),
      buybackBioPiles:
          _nonNegative(json['buybackBioPiles'], base.buybackBioPiles),
      metamorphosisToleranceMs: _nonNegative(
          json['metamorphosisToleranceMs'], base.metamorphosisToleranceMs),
      inventoryStackSize:
          _positive(json['inventoryStackSize'], base.inventoryStackSize),
      dayDurationHours:
          _positive(json['dayDurationHours'], base.dayDurationHours),
      nightDurationHours:
          _positive(json['nightDurationHours'], base.nightDurationHours),
      energyOrganicCost:
          _positive(json['energyOrganicCost'], base.energyOrganicCost),
      energyMineralCost:
          _positive(json['energyMineralCost'], base.energyMineralCost),
      energyProduced: _positive(json['energyProduced'], base.energyProduced),
      vegetalSleepMinutes:
          _positive(json['vegetalSleepMinutes'], base.vegetalSleepMinutes),
      mineralDaySleepMinutes: _positive(
          json['mineralDaySleepMinutes'], base.mineralDaySleepMinutes),
      mineralLateNightSleepMinutes: _positive(
          json['mineralLateNightSleepMinutes'],
          base.mineralLateNightSleepMinutes),
      fungalMidDaySleepMinutes: _positive(
          json['fungalMidDaySleepMinutes'], base.fungalMidDaySleepMinutes),
      fungalTransitionSleepMinutes: _positive(
          json['fungalTransitionSleepMinutes'],
          base.fungalTransitionSleepMinutes),
      observationTextThreshold: _positive(
          json['observationTextThreshold'], base.observationTextThreshold),
      observationEvidenceCooldownMinutes: _nonNegative(
          json['observationEvidenceCooldownMinutes'],
          base.observationEvidenceCooldownMinutes),
      autonomousReactionIntervalSeconds: _positive(
          json['autonomousReactionIntervalSeconds'],
          base.autonomousReactionIntervalSeconds),
      objectReactionDelayMs:
          _positive(json['objectReactionDelayMs'], base.objectReactionDelayMs),
      idlePauseSeconds:
          _positive(json['idlePauseSeconds'], base.idlePauseSeconds),
      normalMoveDurationMs:
          _positive(json['normalMoveDurationMs'], base.normalMoveDurationMs),
      runMoveDurationMs:
          _positive(json['runMoveDurationMs'], base.runMoveDurationMs),
      personalityBaselineWeight: _rate(
          json['personalityBaselineWeight'], base.personalityBaselineWeight),
      personalityBabyWeight:
          _rate(json['personalityBabyWeight'], base.personalityBabyWeight),
      personalityIntermediateWeight: _rate(
          json['personalityIntermediateWeight'],
          base.personalityIntermediateWeight),
      personalityAdultPlasticityWeight: _rate(
          json['personalityAdultPlasticityWeight'],
          base.personalityAdultPlasticityWeight),
      warmCuddleCooldownSeconds: _positive(
          json['warmCuddleCooldownSeconds'], base.warmCuddleCooldownSeconds),
      reservedCuddleCooldownSeconds: _positive(
          json['reservedCuddleCooldownSeconds'],
          base.reservedCuddleCooldownSeconds),
      requestDurationSeconds: _positive(
          json['requestDurationSeconds'], base.requestDurationSeconds),
      baseHumidity: _number(json['baseHumidity'], base.baseHumidity),
      baseTemperature: _number(json['baseTemperature'], base.baseTemperature),
      dayTemperatureDelta:
          _number(json['dayTemperatureDelta'], base.dayTemperatureDelta),
      strongShadeTemperatureDelta: _number(json['strongShadeTemperatureDelta'],
          base.strongShadeTemperatureDelta),
      reactionBubbleSeconds:
          _positive(json['reactionBubbleSeconds'], base.reactionBubbleSeconds),
      absorptionBubbleSeconds: _positive(
          json['absorptionBubbleSeconds'], base.absorptionBubbleSeconds),
      longPressHoldSeconds:
          _positive(json['longPressHoldSeconds'], base.longPressHoldSeconds),
      wakeGraceSeconds:
          _positive(json['wakeGraceSeconds'], base.wakeGraceSeconds),
      baseStayBabySeconds:
          _positive(json['baseStayBabySeconds'], base.baseStayBabySeconds),
      baseStayIntermediateSeconds: _positive(
          json['baseStayIntermediateSeconds'],
          base.baseStayIntermediateSeconds),
      baseStayMatureSeconds:
          _positive(json['baseStayMatureSeconds'], base.baseStayMatureSeconds),
      tempoPosedStayModifierSeconds: _number(
          json['tempoPosedStayModifierSeconds'],
          base.tempoPosedStayModifierSeconds),
      tempoSpontaneousStayModifierSeconds: _number(
          json['tempoSpontaneousStayModifierSeconds'],
          base.tempoSpontaneousStayModifierSeconds),
      perfectZoneStayModifierSeconds: _number(
          json['perfectZoneStayModifierSeconds'],
          base.perfectZoneStayModifierSeconds),
      badZoneStayModifierSeconds: _number(
          json['badZoneStayModifierSeconds'], base.badZoneStayModifierSeconds),
      extremeZoneStayModifierSeconds: _number(
          json['extremeZoneStayModifierSeconds'],
          base.extremeZoneStayModifierSeconds),
      minStaySeconds: _positive(json['minStaySeconds'], base.minStaySeconds),
      resonanceGainPerUse:
          _positive(json['resonanceGainPerUse'], base.resonanceGainPerUse),
      vocalizations: (json['vocalizations'] as Map?)?.map(
            (key, value) => MapEntry('$key', '$value'),
          ) ??
          base.vocalizations,
      recycleRules: _recycleRules(json['recycleRules'], base.recycleRules),
      recipes: (json['recipes'] as List?)
              ?.whereType<Map>()
              .map((raw) =>
                  ElevageRecipe.fromJson(Map<String, dynamic>.from(raw)))
              .toList() ??
          base.recipes,
      natureProfiles:
          _natureProfiles(json['natureProfiles'], base.natureProfiles),
      producerOutputs:
          _producerOutputs(json['producerOutputs'], base.producerOutputs),
      installationEffects: _installationEffects(
          json['installationEffects'], base.installationEffects),
      structureConsumptions: _structureConsumptions(
          json['structureConsumptions'], base.structureConsumptions),
      structureModules:
          _structureModules(json['structureModules'], base.structureModules),
      modules: _modules(json['modules'], base.modules),
    );
    validateElevageConfig(config);
    return config;
  }
}

int _positive(Object? value, int fallback) =>
    value is num && value > 0 ? value.round() : fallback;
int _nonNegative(Object? value, int fallback) =>
    value is num && value >= 0 ? value.round() : fallback;
int _number(Object? value, int fallback) =>
    value is num ? value.round() : fallback;
int _scale(Object? value, int fallback) =>
    value is num && value >= 0 && value <= 5 ? value.round() : fallback;
double _rate(Object? value, double fallback) =>
    value is num && value >= 0 && value <= 1 ? value.toDouble() : fallback;

Map<String, Map<String, int>> _installationEffects(
    Object? value, Map<String, Map<String, int>> fallback) {
  if (value is! Map) return fallback;
  final result = <String, Map<String, int>>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! Map) continue;
    final effects = <String, int>{};
    for (final effect in (entry.value as Map).entries) {
      if (effect.key is String && effect.value is num) {
        effects[effect.key as String] = (effect.value as num).round();
      }
    }
    result[entry.key as String] = effects;
  }
  return result;
}

Map<String, ElevageRecycleRule> _recycleRules(
    Object? value, Map<String, ElevageRecycleRule> fallback) {
  if (value is! Map) return fallback;
  final result = <String, ElevageRecycleRule>{};
  for (final entry in value.entries) {
    final fallbackRule = fallback['${entry.key}'];
    if (fallbackRule == null || entry.value is! Map) continue;
    result['${entry.key}'] = ElevageRecycleRule.fromJson(
        Map<String, dynamic>.from(entry.value as Map), fallbackRule);
  }
  return <String, ElevageRecycleRule>{...fallback, ...result};
}

Map<String, ElevageStructureConsumption> _structureConsumptions(
    Object? value, Map<String, ElevageStructureConsumption> fallback) {
  if (value is! Map) return fallback;
  final result = <String, ElevageStructureConsumption>{};
  for (final entry in value.entries) {
    final defaultValue = fallback['${entry.key}'];
    if (defaultValue == null || entry.value is! Map) continue;
    result['${entry.key}'] = ElevageStructureConsumption.fromJson(
        Map<String, dynamic>.from(entry.value as Map), defaultValue);
  }
  return <String, ElevageStructureConsumption>{...fallback, ...result};
}

Map<String, List<ElevageProductionOutput>> _producerOutputs(
    Object? value, Map<String, List<ElevageProductionOutput>> fallback) {
  if (value is! Map) return fallback;
  return fallback.map((installationId, defaults) {
    final rawOutputs = value[installationId];
    if (rawOutputs is! List) return MapEntry(installationId, defaults);
    final byResource = <String, Map>{
      for (final raw in rawOutputs.whereType<Map>())
        if (raw['resourceId'] is String) raw['resourceId'] as String: raw,
    };
    return MapEntry(
        installationId,
        defaults
            .map((output) => ElevageProductionOutput.fromJson(
                Map<String, dynamic>.from(
                    byResource[output.resourceId] ?? const <String, dynamic>{}),
                output))
            .toList(growable: false));
  });
}

Map<String, List<String>> _natureCurves(
    Object? value, Map<String, List<String>> fallback) {
  const axes = <String>['light', 'temperature', 'humidity'];
  const states = <String>{'IDEAL', 'GOOD', 'NEUTRAL', 'BAD', 'EXTREME'};
  if (value is! Map) return fallback;
  final result = <String, List<String>>{};
  for (final axis in axes) {
    final raw = value[axis];
    if (raw is! List ||
        raw.length != 6 ||
        raw.any((entry) => entry is! String || !states.contains(entry))) {
      result[axis] = fallback[axis]!;
    } else {
      result[axis] = raw.cast<String>();
    }
  }
  return result;
}

Map<String, ElevageStructureModuleProfile> _structureModules(
    Object? value, Map<String, ElevageStructureModuleProfile> fallback) {
  if (value is! Map) return fallback;
  final result = <String, ElevageStructureModuleProfile>{...fallback};
  for (final entry in value.entries) {
    final profile = fallback['${entry.key}'];
    if (profile == null || entry.value is! Map) continue;
    result['${entry.key}'] = ElevageStructureModuleProfile.fromJson(
        Map<String, dynamic>.from(entry.value as Map), profile);
  }
  return result;
}

Map<String, ElevageModuleDefinition> _modules(
    Object? value, Map<String, ElevageModuleDefinition> fallback) {
  if (value is! Map) return fallback;
  final result = <String, ElevageModuleDefinition>{...fallback};
  for (final entry in value.entries) {
    final definition = fallback['${entry.key}'];
    if (definition == null || entry.value is! Map) continue;
    result['${entry.key}'] = ElevageModuleDefinition.fromJson(
        Map<String, dynamic>.from(entry.value as Map), definition);
  }
  return result;
}

List<ElevageNatureProfile> _natureProfiles(
    Object? value, List<ElevageNatureProfile> fallback) {
  if (value is! List) return fallback;
  final byId = <String, Map>{
    for (final raw in value.whereType<Map>()) '${raw['id']}': raw,
  };
  return fallback
      .map((profile) => ElevageNatureProfile.fromJson(
          Map<String, dynamic>.from(
              byId[profile.id] ?? const <String, dynamic>{}),
          profile))
      .toList(growable: false);
}

bool _validNatureProfile(ElevageNatureProfile profile) {
  const axes = <String>['light', 'temperature', 'humidity'];
  const states = <String>{'IDEAL', 'GOOD', 'NEUTRAL', 'BAD', 'EXTREME'};
  return <int>[
        profile.preferredLight,
        profile.preferredTemperature,
        profile.preferredHumidity,
      ].every((value) => value >= 0 && value <= 5) &&
      axes.every((axis) {
        final curve = profile.curves[axis];
        return curve != null &&
            curve.length == 6 &&
            curve.every(states.contains);
      });
}

void validateElevageConfig(ElevageConfig config) {
  final baseDefinitions = <String, ElevageInstallationDefinition>{
    for (final definition in config._defaultInstallations)
      definition.id: definition,
  };
  final invalidInstallationEffects =
      config.installationEffects.entries.any((entry) {
    final definition = baseDefinitions[entry.key];
    if (definition == null) return true;
    const environmental = <String>{'light', 'temperature', 'humidity'};
    const wellbeing = <String>{'wellbeing'};
    final allowed =
        definition.category == 'STRUCTURE' ? environmental : wellbeing;
    return entry.value.keys.any((key) => !allowed.contains(key)) ||
        entry.value.values.any((value) => value < -5 || value > 5);
  });
  final invalidProducerOutputs = config.producerOutputs.entries.any((entry) =>
      !const <String>{'CULTURE_POTAGERE', 'BUTTE_ARBUSTE', 'SUPPORT_FONGIQUE'}
          .contains(entry.key) ||
      entry.value.isEmpty ||
      entry.value.any((output) =>
          !elevageRecipeSpecialComponentIds.contains(output.resourceId) ||
          output.quantityPerCycle <= 0 ||
          output.productionSeconds <= 0 ||
          output.maxLocalStock <= 0));
  final invalidRecycleRules = config.recycleRules.entries.any((entry) {
    final rule = entry.value;
    return !elevageRecipeSpecialComponentIds.contains(entry.key) ||
        !rule.recyclable ||
        !const <String>{'ORGANIC', 'MINERAL'}
            .contains(rule.recycleOutputType) ||
        rule.recycleOutputQuantity <= 0;
  });
  const consumptionModes = <String>{
    'NONE',
    'ENERGY',
    'DIRECT_RESOURCE',
    'MULTI_RESOURCE',
  };
  final invalidConsumption = config.structureConsumptions.values.any((entry) =>
      !consumptionModes.contains(entry.mode) ||
      (entry.mode == 'ENERGY' &&
          (entry.energyCost <= 0 || entry.consumptionIntervalSeconds <= 0)) ||
      (entry.mode == 'DIRECT_RESOURCE' &&
          (entry.resourceCosts.length != 1 ||
              entry.resourceCosts.values.any((value) => value <= 0) ||
              entry.consumptionIntervalSeconds <= 0)) ||
      (entry.mode == 'MULTI_RESOURCE' &&
          (entry.resourceCosts.isEmpty ||
              entry.resourceCosts.values.any((value) => value <= 0) ||
              entry.consumptionIntervalSeconds <= 0)));
  const moduleCategories = <String>{'POWER', 'EFFICIENCY', 'CAPACITY'};
  final invalidModules = config.modules.values.any((module) =>
      !moduleCategories.contains(module.category) ||
      module.compatibleStructures.isEmpty ||
      module.maxStacksPerStructure <= 0 ||
      module.organicCost < 0 ||
      module.mineralCost < 0);
  final invalidStructureModules = config.structureModules.entries.any((entry) =>
      entry.value.moduleSlots < 0 ||
      entry.value.allowedModuleIds.any((id) =>
          !config.modules.containsKey(id) ||
          !config.modules[id]!.compatibleStructures.contains(entry.key)));
  if (config.hungerNormalHours > config.hungerHungryHours ||
      config.hungerHungryHours > config.hungerVeryHungryHours ||
      config.suspectedThreshold > config.confirmedThreshold ||
      config.observationTextThreshold > config.confirmedThreshold ||
      config.autonomousReactionIntervalSeconds <= 0 ||
      config.objectReactionDelayMs <= 0 ||
      config.idlePauseSeconds <= 0 ||
      config.normalMoveDurationMs <= 0 ||
      config.runMoveDurationMs <= 0 ||
      ((config.personalityBaselineWeight +
                      config.personalityBabyWeight +
                      config.personalityIntermediateWeight +
                      config.personalityAdultPlasticityWeight) -
                  1)
              .abs() >
          .0001 ||
      config.warmCuddleCooldownSeconds <= 0 ||
      config.reservedCuddleCooldownSeconds <= 0 ||
      config.requestDurationSeconds <= 0 ||
      config.reactionBubbleSeconds <= 0 ||
      config.absorptionBubbleSeconds < config.reactionBubbleSeconds ||
      config.longPressHoldSeconds <= 0 ||
      config.wakeGraceSeconds <= 0 ||
      config.baseStayBabySeconds <= 0 ||
      config.baseStayIntermediateSeconds <= 0 ||
      config.baseStayMatureSeconds <= 0 ||
      config.minStaySeconds <= 0 ||
      config.resonanceGainPerUse <= 0 ||
      config.energyOrganicCost <= 0 ||
      config.energyMineralCost <= 0 ||
      config.energyProduced <= 0 ||
      config.vegetalSleepMinutes <= 0 ||
      config.mineralDaySleepMinutes <= 0 ||
      config.mineralLateNightSleepMinutes <= 0 ||
      config.fungalMidDaySleepMinutes <= 0 ||
      config.fungalTransitionSleepMinutes <= 0 ||
      <int>[
        config.vegetalSleepMinutes,
        config.mineralDaySleepMinutes,
        config.mineralLateNightSleepMinutes,
        config.fungalMidDaySleepMinutes,
        config.fungalTransitionSleepMinutes,
      ].any((minutes) => minutes > config.dayNightCycleHours * 60) ||
      invalidRecycleRules ||
      invalidConsumption ||
      invalidModules ||
      invalidStructureModules ||
      config.vocalizations.values.any((value) => value.trim().isEmpty) ||
      config.natureProfiles.length != 3 ||
      config.natureProfiles.map((profile) => profile.id).toSet().length !=
          config.natureProfiles.length ||
      config.natureProfiles.any((profile) => !_validNatureProfile(profile)) ||
      invalidProducerOutputs ||
      invalidInstallationEffects ||
      config.recipes.any((recipe) =>
          recipe.organic < 0 ||
          recipe.mineral < 0 ||
          recipe.special.entries.any((entry) =>
              !elevageRecipeSpecialComponentIds.contains(entry.key) ||
              entry.value <= 0)) ||
      config.recipes.map((recipe) => recipe.id).toSet().length !=
          config.recipes.length) {
    throw const FormatException('Configuration Élevage invalide.');
  }
}

const ElevageConfig defaultElevageConfig = ElevageConfig(
  revision: 'defaults:v1',
  featureEnabled: true,
  devMode: true,
  preset: ElevagePreset.prototype,
  alcoveCount: 4,
  installationSlotCount: 4,
  hungerNormalHours: 96,
  hungerHungryHours: 168,
  hungerVeryHungryHours: 240,
  suspectedThreshold: 2,
  confirmedThreshold: 4,
  foragingDurationSeconds: 20,
  productionIntervalSeconds: 10800,
  productionMaxStock: 6,
  coRearingDurationHours: 168,
  refundOrganicRate: .5,
  refundMineralRate: .5,
  sourcierEnabled: true,
  fibrousFruitPrice: 2,
  fruitJellyPrice: 3,
  buybackQuantity: 5,
  buybackBioPiles: 1,
  metamorphosisToleranceMs: 180,
  inventoryStackSize: 12,
  dayDurationHours: 4,
  nightDurationHours: 2,
  energyOrganicCost: 2,
  energyMineralCost: 1,
  energyProduced: 10,
  vegetalSleepMinutes: 120,
  // Résonance dort à la fin de nuit puis au début du jour. Ces valeurs font
  // notamment un réveil vers 2 h 30 avec un cycle de Jour 3 h / Nuit 1 h.
  mineralDaySleepMinutes: 150,
  mineralLateNightSleepMinutes: 30,
  // Les Fongiques gardent deux sommeils : chaleur du milieu de jour puis
  // transition jour/nuit. Les durées peuvent être affinées dans le Dashboard.
  fungalMidDaySleepMinutes: 50,
  fungalTransitionSleepMinutes: 45,
  observationTextThreshold: 2,
  observationEvidenceCooldownMinutes: 10,
  autonomousReactionIntervalSeconds: 60,
  objectReactionDelayMs: 700,
  idlePauseSeconds: 45,
  normalMoveDurationMs: 1600,
  runMoveDurationMs: 400,
  personalityBaselineWeight: .5,
  personalityBabyWeight: .25,
  personalityIntermediateWeight: .15,
  personalityAdultPlasticityWeight: .1,
  warmCuddleCooldownSeconds: 45,
  reservedCuddleCooldownSeconds: 90,
  requestDurationSeconds: 90,
  baseHumidity: 2,
  baseTemperature: 2,
  dayTemperatureDelta: 1,
  strongShadeTemperatureDelta: -1,
  reactionBubbleSeconds: 7,
  absorptionBubbleSeconds: 20,
  longPressHoldSeconds: 3,
  wakeGraceSeconds: 60,
  baseStayBabySeconds: 30,
  baseStayIntermediateSeconds: 20,
  baseStayMatureSeconds: 25,
  tempoPosedStayModifierSeconds: 5,
  tempoSpontaneousStayModifierSeconds: -5,
  perfectZoneStayModifierSeconds: 10,
  badZoneStayModifierSeconds: -10,
  extremeZoneStayModifierSeconds: -20,
  minStaySeconds: 3,
  resonanceGainPerUse: 1,
  vocalizations: <String, String>{
    'CURIOSITY': 'Pti ?',
    'ABSORB': 'Mm !',
    'CONTENT': 'Prr !',
    'DISCOMFORT': 'Nnh…',
    'SURPRISE': 'Ptik !',
    'REJECT': 'Nh !',
    'CALL': 'Pti !',
  },
  recycleRules: <String, ElevageRecycleRule>{
    'SALT': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'MINERAL',
        recycleOutputQuantity: 1),
    'FRUIT': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'ORGANIC',
        recycleOutputQuantity: 1),
    'ROOT': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'ORGANIC',
        recycleOutputQuantity: 1),
    'LEAF': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'ORGANIC',
        recycleOutputQuantity: 1),
    'SEED': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'ORGANIC',
        recycleOutputQuantity: 1),
    'SPORE': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'ORGANIC',
        recycleOutputQuantity: 1),
    'MOSS': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'ORGANIC',
        recycleOutputQuantity: 1),
    'MUSHROOM': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'ORGANIC',
        recycleOutputQuantity: 1),
    'ALGAE': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'ORGANIC',
        recycleOutputQuantity: 1),
    'SPROUT': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'ORGANIC',
        recycleOutputQuantity: 1),
    'IRON': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'MINERAL',
        recycleOutputQuantity: 1),
    'LIMESTONE': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'MINERAL',
        recycleOutputQuantity: 1),
    'QUARTZ': ElevageRecycleRule(
        recyclable: true,
        recycleOutputType: 'MINERAL',
        recycleOutputQuantity: 1),
  },
  structureConsumptions: <String, ElevageStructureConsumption>{
    // Prototype values: visible during a TestFlight session without rapidly
    // emptying a normal Refuge reserve. Target balance remains open.
    'FOUR_BIO_ORGANIQUE': ElevageStructureConsumption(
      mode: 'DIRECT_RESOURCE',
      resourceCosts: <String, int>{'ORGANIC': 1},
      consumptionIntervalSeconds: 3600,
    ),
    'VENTILATION': ElevageStructureConsumption(
      mode: 'ENERGY',
      energyCost: 1,
      consumptionIntervalSeconds: 7200,
    ),
  },
  structureModules: <String, ElevageStructureModuleProfile>{
    'FOUR_BIO_ORGANIQUE': ElevageStructureModuleProfile(
      moduleSlots: 2,
      allowedModuleIds: <String>[
        'MODULE_POWER_BASIC',
        'MODULE_EFFICIENCY_BASIC',
      ],
      primaryEnvironmentAxis: 'temperature',
    ),
    'VENTILATION': ElevageStructureModuleProfile(
      moduleSlots: 2,
      allowedModuleIds: <String>[
        'MODULE_POWER_BASIC',
        'MODULE_EFFICIENCY_BASIC',
      ],
      primaryEnvironmentAxis: 'humidity',
    ),
    'CULTURE_POTAGERE': ElevageStructureModuleProfile(
      moduleSlots: 1,
      allowedModuleIds: <String>['MODULE_CAPACITY_BASIC'],
    ),
    'BIOGENERATOR': ElevageStructureModuleProfile(
      moduleSlots: 3,
      allowedModuleIds: <String>[
        'MODULE_POWER_BASIC',
        'MODULE_EFFICIENCY_BASIC',
        'MODULE_CAPACITY_BASIC',
      ],
    ),
  },
  modules: <String, ElevageModuleDefinition>{
    'MODULE_POWER_BASIC': ElevageModuleDefinition(
      id: 'MODULE_POWER_BASIC',
      label: 'Module de puissance',
      description:
          'Renforce l’effet environnemental principal de la structure.',
      category: 'POWER',
      compatibleStructures: <String>[
        'FOUR_BIO_ORGANIQUE',
        'VENTILATION',
        'BIOGENERATOR',
      ],
      effects: <String, num>{'environmentMagnitudeDelta': 1},
      stackable: true,
      maxStacksPerStructure: 2,
      organicCost: 2,
      mineralCost: 1,
    ),
    'MODULE_EFFICIENCY_BASIC': ElevageModuleDefinition(
      id: 'MODULE_EFFICIENCY_BASIC',
      label: 'Module d’efficacité',
      description: 'Allonge l’intervalle entre deux consommations de 25 %.',
      category: 'EFFICIENCY',
      compatibleStructures: <String>[
        'FOUR_BIO_ORGANIQUE',
        'VENTILATION',
        'BIOGENERATOR',
      ],
      effects: <String, num>{'consumptionIntervalMultiplier': 1.25},
      stackable: true,
      maxStacksPerStructure: 2,
      organicCost: 2,
      mineralCost: 2,
    ),
    'MODULE_CAPACITY_BASIC': ElevageModuleDefinition(
      id: 'MODULE_CAPACITY_BASIC',
      label: 'Module de capacité',
      description: 'Augmente de 3 le stock local maximal de chaque ressource.',
      category: 'CAPACITY',
      compatibleStructures: <String>['CULTURE_POTAGERE', 'BIOGENERATOR'],
      effects: <String, num>{'stockCapacityDelta': 3},
      stackable: false,
      maxStacksPerStructure: 1,
      organicCost: 3,
      mineralCost: 1,
    ),
  },
  producerOutputs: <String, List<ElevageProductionOutput>>{
    'CULTURE_POTAGERE': <ElevageProductionOutput>[
      ElevageProductionOutput(
          resourceId: 'ROOT',
          quantityPerCycle: 1,
          productionSeconds: 10800,
          maxLocalStock: 6),
      ElevageProductionOutput(
          resourceId: 'LEAF',
          quantityPerCycle: 1,
          productionSeconds: 10800,
          maxLocalStock: 6),
    ],
    'BUTTE_ARBUSTE': <ElevageProductionOutput>[
      ElevageProductionOutput(
          resourceId: 'FRUIT',
          quantityPerCycle: 1,
          productionSeconds: 10800,
          maxLocalStock: 6),
    ],
    'SUPPORT_FONGIQUE': <ElevageProductionOutput>[
      ElevageProductionOutput(
          resourceId: 'MUSHROOM',
          quantityPerCycle: 1,
          productionSeconds: 10800,
          maxLocalStock: 6),
    ],
  },
  natureProfiles: <ElevageNatureProfile>[
    ElevageNatureProfile(
      id: 'MINERAL_RESONANCE',
      family: 'MINERAL',
      nature: 'RESONANCE',
      label: 'Minéral · Résonance',
      placeholder: '◇',
      preferredLight: 3,
      preferredTemperature: 4,
      preferredHumidity: 2,
      curves: <String, List<String>>{
        'light': <String>['BAD', 'GOOD', 'GOOD', 'IDEAL', 'NEUTRAL', 'BAD'],
        'temperature': <String>[
          'EXTREME',
          'BAD',
          'NEUTRAL',
          'GOOD',
          'IDEAL',
          'EXTREME',
        ],
        'humidity': <String>[
          'BAD',
          'GOOD',
          'IDEAL',
          'NEUTRAL',
          'BAD',
          'EXTREME',
        ],
      },
    ),
    ElevageNatureProfile(
      id: 'VEGETAL_PHOTOSYNTHESIS',
      family: 'VEGETAL',
      nature: 'PHOTOSYNTHESIS',
      label: 'Végétal · Photosynthèse',
      placeholder: '✦',
      preferredLight: 5,
      preferredTemperature: 3,
      preferredHumidity: 2,
      curves: <String, List<String>>{
        'light': <String>[
          'EXTREME',
          'BAD',
          'BAD',
          'NEUTRAL',
          'GOOD',
          'IDEAL',
        ],
        'temperature': <String>[
          'BAD',
          'BAD',
          'GOOD',
          'IDEAL',
          'NEUTRAL',
          'EXTREME',
        ],
        'humidity': <String>[
          'BAD',
          'GOOD',
          'IDEAL',
          'GOOD',
          'NEUTRAL',
          'BAD',
        ],
      },
    ),
    ElevageNatureProfile(
      id: 'FUNGAL_DECOMPOSITION',
      family: 'FUNGAL',
      nature: 'DECOMPOSITION',
      label: 'Fongique · Décomposition',
      placeholder: '♣',
      preferredLight: 1,
      preferredTemperature: 2,
      preferredHumidity: 4,
      curves: <String, List<String>>{
        'light': <String>[
          'GOOD',
          'IDEAL',
          'GOOD',
          'NEUTRAL',
          'BAD',
          'EXTREME',
        ],
        'temperature': <String>[
          'BAD',
          'GOOD',
          'IDEAL',
          'GOOD',
          'BAD',
          'EXTREME',
        ],
        'humidity': <String>[
          'EXTREME',
          'BAD',
          'NEUTRAL',
          'GOOD',
          'IDEAL',
          'GOOD',
        ],
      },
    ),
  ],
  recipes: <ElevageRecipe>[
    ElevageRecipe(
        id: 'ABRI_FIBREUX',
        label: 'Abri fibreux',
        installationId: 'ABRI_FIBREUX',
        organic: 5,
        mineral: 2),
    ElevageRecipe(
        id: 'ABRI_MINERAL_PROFOND',
        label: 'Abri minéral profond',
        installationId: 'ABRI_MINERAL_PROFOND',
        organic: 0,
        mineral: 7),
    ElevageRecipe(
        id: 'VENTILATION',
        label: 'Ventilation',
        installationId: 'VENTILATION',
        organic: 2,
        mineral: 5),
    ElevageRecipe(
        id: 'FOUR_BIO_ORGANIQUE',
        label: 'Four bio-organique',
        installationId: 'FOUR_BIO_ORGANIQUE',
        organic: 0,
        mineral: 7),
    ElevageRecipe(
        id: 'TOIT_SERRE',
        label: 'Toit de serre',
        installationId: 'TOIT_SERRE',
        organic: 6,
        mineral: 1),
    ElevageRecipe(
        id: 'LAMPE_SOLAIRE',
        label: 'Lampe solaire',
        installationId: 'LAMPE_SOLAIRE',
        organic: 2,
        mineral: 4),
    ElevageRecipe(
        id: 'BASSIN',
        label: 'Bassin',
        installationId: 'BASSIN',
        organic: 2,
        mineral: 10,
        special: <String, int>{'LIMESTONE': 1, 'ALGAE': 1},
        unlockItems: <String>['LIMESTONE', 'ALGAE']),
    ElevageRecipe(
        id: 'MOSS_STONE',
        label: 'Pierre de mousse',
        installationId: 'MOSS_STONE',
        organic: 2,
        mineral: 5,
        special: <String, int>{'MOSS': 1},
        unlockItems: <String>['MOSS']),
    ElevageRecipe(
        id: 'CULTURE_POTAGERE',
        label: 'Culture potagère',
        installationId: 'CULTURE_POTAGERE',
        organic: 0,
        mineral: 0,
        special: <String, int>{'ROOT': 10},
        unlockItems: <String>['SEED']),
    ElevageRecipe(
        id: 'BUTTE_ARBUSTE',
        label: 'Butte d’arbuste',
        installationId: 'BUTTE_ARBUSTE',
        organic: 0,
        mineral: 0,
        special: <String, int>{'SEED': 10},
        unlockItems: <String>['SEED']),
    ElevageRecipe(
        id: 'FORMATION_MINERALE',
        label: 'Formation minérale',
        installationId: 'FORMATION_MINERALE',
        organic: 0,
        mineral: 0,
        special: <String, int>{'LIMESTONE': 10},
        unlockItems: <String>['LIMESTONE']),
    ElevageRecipe(
        id: 'FORMATION_METALLIQUE',
        label: 'Formation métallique',
        installationId: 'FORMATION_METALLIQUE',
        organic: 0,
        mineral: 0,
        special: <String, int>{'IRON': 10},
        unlockItems: <String>['IRON']),
    ElevageRecipe(
        id: 'FORMATION_CRISTALLINE',
        label: 'Formation cristalline',
        installationId: 'FORMATION_CRISTALLINE',
        organic: 0,
        mineral: 0,
        special: <String, int>{'QUARTZ': 10},
        unlockItems: <String>['QUARTZ']),
    ElevageRecipe(
        id: 'SUPPORT_FONGIQUE',
        label: 'Support fongique',
        installationId: 'SUPPORT_FONGIQUE',
        organic: 0,
        mineral: 0,
        special: <String, int>{'MUSHROOM': 10},
        unlockItems: <String>['MUSHROOM']),
    ElevageRecipe(
        id: 'BOSQUET_SYMBIOTIQUE',
        label: 'Bosquet symbiotique',
        installationId: 'BOSQUET_SYMBIOTIQUE',
        organic: 5,
        mineral: 1,
        special: <String, int>{'SEED': 10},
        unlockItems: <String>['SEED']),
    ElevageRecipe(
        id: 'COLONIE_MYCELIENNE',
        label: 'Colonie mycélienne',
        installationId: 'COLONIE_MYCELIENNE',
        organic: 6,
        mineral: 0,
        special: <String, int>{'SPORE': 10},
        unlockItems: <String>['SPORE']),
    ElevageRecipe(
        id: 'HAMAC',
        label: 'Hamac',
        installationId: 'HAMAC',
        organic: 6,
        mineral: 1),
    ElevageRecipe(
        id: 'NID_COUCHETTE',
        label: 'Nid / couchette',
        installationId: 'NID_COUCHETTE',
        organic: 5,
        mineral: 2),
    ElevageRecipe(
        id: 'POTAGER_VERTICAL',
        label: 'Potager vertical',
        installationId: 'POTAGER_VERTICAL',
        organic: 4,
        mineral: 2,
        special: <String, int>{'SEED': 1},
        unlockItems: <String>['SEED']),
    ElevageRecipe(
        id: 'LITIERE_FONGIQUE',
        label: 'Litière fongique',
        installationId: 'LITIERE_FONGIQUE',
        organic: 4,
        mineral: 2),
    ElevageRecipe(
        id: 'BAC_GRAVIER',
        label: 'Bac à gravier',
        installationId: 'BAC_GRAVIER',
        organic: 1,
        mineral: 5),
    ElevageRecipe(
        id: 'BIBLIOTHEQUE_DATABUG',
        label: 'Bibliothèque Databug',
        installationId: 'BIBLIOTHEQUE_DATABUG',
        organic: 3,
        mineral: 3),
    ElevageRecipe(
        id: 'PARCOURS_OBSTACLES',
        label: 'Parcours d’obstacles',
        installationId: 'PARCOURS_OBSTACLES',
        organic: 5,
        mineral: 3),
    ElevageRecipe(
        id: 'CRISTAL_DECORATIF',
        label: 'Cristal décoratif',
        installationId: 'CRISTAL_DECORATIF',
        organic: 0,
        mineral: 0,
        special: <String, int>{'QUARTZ': 1},
        unlockItems: <String>['QUARTZ']),
    ElevageRecipe(
        id: 'GEODE_DECORATIVE',
        label: 'Géode décorative',
        installationId: 'GEODE_DECORATIVE',
        organic: 0,
        mineral: 2),
    ElevageRecipe(
        id: 'PLANTE_DECORATIVE',
        label: 'Plante décorative',
        installationId: 'PLANTE_DECORATIVE',
        organic: 2,
        mineral: 0,
        special: <String, int>{'SPROUT': 1},
        unlockItems: <String>['SPROUT']),
    ElevageRecipe(
        id: 'MOUSSE_DECORATIVE',
        label: 'Mousse décorative',
        installationId: 'MOUSSE_DECORATIVE',
        organic: 2,
        mineral: 0,
        special: <String, int>{'MOSS': 1},
        unlockItems: <String>['MOSS']),
    ElevageRecipe(
        id: 'PIERRE_DECORATIVE',
        label: 'Pierre décorative',
        installationId: 'PIERRE_DECORATIVE',
        organic: 0,
        mineral: 2),
    ElevageRecipe(
        id: 'CARILLON',
        label: 'Carillon',
        installationId: 'CARILLON',
        organic: 1,
        mineral: 2),
    ElevageRecipe(
        id: 'CONQUE_MUSICALE',
        label: 'Conque musicale',
        installationId: 'CONQUE_MUSICALE',
        organic: 2,
        mineral: 1),
  ],
  refugeProgression: <String, dynamic>{
    'startingAlcoveCount': 1,
    'loanChoiceCount': 2,
    'loanReturnDelayDays': 21,
    'startingBioBatteryCount': 2,
    'bioBatteryEnergy': 10,
    'bioBatteryRecipe': <String, dynamic>{
      'organic': 5,
      'mineral': 5,
      'special': <String, int>{'MUSHROOM': 1, 'ALGAE': 1, 'SALT': 5},
    },
    // Prototype accessible dans le Bio-fabricateur. La recette Target reste
    // volontairement à arbitrer avec la future Lisière V2.
    'biogeneratorRecipe': <String, dynamic>{
      'organic': 8,
      'mineral': 6,
      'special': <String, int>{'MUSHROOM': 2, 'ALGAE': 2, 'SALT': 2},
    },
    'biogenerator': <String, dynamic>{
      'organicTankCapacity': 30,
      'mineralTankCapacity': 10,
      'organicCostPerCycle': 3,
      'mineralCostPerCycle': 2,
      'energyPerCycle': 10,
      'efficiencyOrganicReduction': 1,
      'efficiencyMineralReduction': 1,
      'powerEnergyBonus': 5,
      'capacityOrganicBonus': 10,
      'capacityMineralBonus': 10,
      'minimumOrganicCost': 1,
      'minimumMineralCost': 1,
    },
    'ambientFeedback': <String, dynamic>{
      'shiverAmplitudePx': 3,
      'shiverSpeed': 120,
      'shiverBurstDuration': 650,
      'shiverPauseDuration': 1800,
      'babyVocalCooldownSeconds': 3,
    },
    'tracker': <String, dynamic>{
      'enabled': true,
      'xpForLevel1': 10,
      'xpForLevel2': 30,
      'xpForLevel3': 60,
      'carryBonusByLevel': <String, int>{'0': 0, '1': 1, '2': 2, '3': 3},
    },
    'language': <String, dynamic>{
      'juvenileNewConceptWordThreshold': 5,
      'juvenileBabyKnownConceptWordThreshold': 10,
    },
    'knowledge': <String, dynamic>{
      'observationsForHypothesis': 5,
      'evidenceForConfirmation': 5,
    },
    'maturation': <String, dynamic>{
      'observationRequirement': 4,
      'hypothesisRequirement': 3,
      'confirmationRequirement': 1,
    },
    'tamTam': <String, dynamic>{
      'totalBeats': 3,
      'requiredSuccessfulBeats': 3,
      'beatIntervalMs': 700,
      'perfectWindowMs': 120,
      'goodWindowMs': 240,
    },
    'alcoveRequirements': <Map<String, dynamic>>[
      <String, dynamic>{
        'requiredContribution': 10,
        'turnkeyBiopileCost': 12,
        'assistedBiopileCost': 4,
        'assistedResourceCosts': <String, int>{'ORGANIC': 10, 'MINERAL': 6},
        'constructionDurationSeconds': 3600,
      },
      <String, dynamic>{
        'requiredContribution': 30,
        'turnkeyBiopileCost': 24,
        'assistedBiopileCost': 8,
        'assistedResourceCosts': <String, int>{'ORGANIC': 18, 'MINERAL': 12},
        'constructionDurationSeconds': 7200,
      },
      <String, dynamic>{
        'requiredContribution': 70,
        'turnkeyBiopileCost': 40,
        'assistedBiopileCost': 14,
        'assistedResourceCosts': <String, int>{'ORGANIC': 30, 'MINERAL': 20},
        'constructionDurationSeconds': 10800,
      },
    ],
  },
);

String encodeConfig(ElevageConfig config) => jsonEncode(<String, dynamic>{
      'schemaVersion': elevageConfigSchemaVersion,
      'revision': config.revision,
      'overrides': config.toJson(),
    });
