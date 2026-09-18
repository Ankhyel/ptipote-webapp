/// Shared, timestamp-based weather afflictions.
///
/// The game state owns the entity maps and persistence; this file deliberately
/// stays independent from widgets and Firebase so every population follows the
/// exact same duration, immunity and treatment rules.
enum WeatherAfflictionType { heat, rain, toxic }

/// Personal modules are deliberately described as data rather than as three
/// weather booleans on a P'TIPOTE.  The current effects are protective, but
/// the generic definition keeps the three shared slots usable by later module
/// families without introducing a cargo inventory.
enum PtipoteModuleCategory { weatherProtection }

enum PtipoteModuleEffectType { preventWeatherAffliction }

class PtipoteModuleDefinition {
  const PtipoteModuleDefinition({
    required this.id,
    required this.displayName,
    required this.category,
    required this.effectType,
    required this.effectValue,
    required this.compatibleEntity,
    required this.enabled,
    required this.recipeId,
    required this.assetOrIcon,
  });

  final String id;
  final String displayName;
  final PtipoteModuleCategory category;
  final PtipoteModuleEffectType effectType;

  /// The weather-affliction type prevented by this module. Kept as a string
  /// so future non-weather effects can use the same definition shape.
  final String effectValue;
  final String compatibleEntity;
  final bool enabled;
  final String recipeId;
  final String assetOrIcon;

  bool prevents(WeatherAfflictionType type) =>
      effectType == PtipoteModuleEffectType.preventWeatherAffliction &&
      effectValue == type.id;
}

const List<PtipoteModuleDefinition> ptipoteModuleDefinitions =
    <PtipoteModuleDefinition>[
  PtipoteModuleDefinition(
    id: 'ptipoteThermalProtection',
    displayName: 'Protection thermique P’TIPOTE',
    category: PtipoteModuleCategory.weatherProtection,
    effectType: PtipoteModuleEffectType.preventWeatherAffliction,
    effectValue: 'heat',
    compatibleEntity: 'ptipote',
    enabled: true,
    recipeId: 'ptipoteThermalProtection',
    assetOrIcon: 'thermometer',
  ),
  PtipoteModuleDefinition(
    id: 'ptipoteRainProtection',
    displayName: 'Protection pluie/humidité P’TIPOTE',
    category: PtipoteModuleCategory.weatherProtection,
    effectType: PtipoteModuleEffectType.preventWeatherAffliction,
    effectValue: 'rain',
    compatibleEntity: 'ptipote',
    enabled: true,
    recipeId: 'ptipoteRainProtection',
    assetOrIcon: 'water_drop',
  ),
  PtipoteModuleDefinition(
    id: 'ptipoteToxicProtection',
    displayName: 'Protection filtrante/toxique P’TIPOTE',
    category: PtipoteModuleCategory.weatherProtection,
    effectType: PtipoteModuleEffectType.preventWeatherAffliction,
    effectValue: 'toxic',
    compatibleEntity: 'ptipote',
    enabled: true,
    recipeId: 'ptipoteToxicProtection',
    assetOrIcon: 'air',
  ),
];

/// Display names are player-facing data and were refined during the prototype.
/// Keep old crafted stacks and installed modules usable after the rename.
const Map<String, String> legacyPtipoteModuleItemNames = <String, String>{
  'Protection pluie P’TIPOTE': 'Protection pluie/humidité P’TIPOTE',
  'Protection filtrante P’TIPOTE': 'Protection filtrante/toxique P’TIPOTE',
};

String canonicalPtipoteModuleItemName(String itemName) =>
    legacyPtipoteModuleItemNames[itemName] ?? itemName;

PtipoteModuleDefinition? ptipoteModuleDefinitionForItem(String itemName) {
  final canonicalName = canonicalPtipoteModuleItemName(itemName);
  for (final definition in ptipoteModuleDefinitions) {
    if (definition.displayName == canonicalName && definition.enabled) {
      return definition;
    }
  }
  return null;
}

/// Named keys shared by the remote Dashboard and the weather-affliction
/// service. Keeping the lists here prevents a remote partial configuration
/// from silently dropping a duration reduction or a compatible treatment.
const Set<String> weatherAfflictionStructuralReductionKeys = <String>{
  'thermalBasinRain',
  'thermalBasinToxic',
  'ventilationHeat',
  'chloroCanalsRain',
  'filtrationToxic',
};

const Set<String> weatherAfflictionTreatmentReductionKeys = <String>{
  'antiPoisonToxic',
  'antiPoisonJellyToxic',
  'antiPoisonJellyHeat',
  'hydratingJellyHeat',
  'antibioticRain',
};

/// A single treatment item can own several reduction keys (for example the
/// anti-poison jelly). Target compatibility remains Dashboard-configurable,
/// while this map only associates those technical keys with real inventory
/// items.
const Map<String, String> weatherAfflictionTreatmentItemByReductionKey =
    <String, String>{
  'antiPoisonToxic': 'Anti-poison',
  'antiPoisonJellyToxic': 'Gelée anti-poison',
  'antiPoisonJellyHeat': 'Gelée anti-poison',
  'hydratingJellyHeat': 'Gelée hydratante',
  'antibioticRain': 'Antibiotique',
};

extension WeatherAfflictionTypeX on WeatherAfflictionType {
  String get id => name;

  String get emoji => switch (this) {
        WeatherAfflictionType.heat => '🔥',
        WeatherAfflictionType.rain => '🦠',
        WeatherAfflictionType.toxic => '🤢',
      };

  String get ptipoteLabel => switch (this) {
        WeatherAfflictionType.heat => 'Insolation',
        WeatherAfflictionType.rain => 'Infection',
        WeatherAfflictionType.toxic => 'Intoxiqué',
      };

  String get ptibugLabel => switch (this) {
        WeatherAfflictionType.heat => 'Surrégime',
        WeatherAfflictionType.rain => 'Humidifié',
        WeatherAfflictionType.toxic => 'Intoxiqué',
      };
}

class WeatherAffliction {
  const WeatherAffliction({
    required this.type,
    required this.startedAt,
    required this.endsAt,
    this.sourceWeatherEventId,
    this.ptibugProductionMultiplier,
  });

  final WeatherAfflictionType type;
  final DateTime startedAt;
  final DateTime endsAt;
  final String? sourceWeatherEventId;

  /// Snapshot of the unique production multiplier caused by this incident for
  /// a P'TIBUG.  The weather event may end before the health effect does; a
  /// snapshot therefore keeps the health malus stable for the whole
  /// affliction without reapplying the legacy weather malus a second time.
  /// It is null for P'TIPOTES and residents, and for legacy P'TIBUG records.
  final double? ptibugProductionMultiplier;

  bool isActiveAt(DateTime now) => now.isBefore(endsAt);

  WeatherAffliction shorten(Duration amount, DateTime now) {
    final shortened = endsAt.subtract(amount);
    return WeatherAffliction(
      type: type,
      startedAt: startedAt,
      endsAt: shortened.isBefore(now) ? now : shortened,
      sourceWeatherEventId: sourceWeatherEventId,
      ptibugProductionMultiplier: ptibugProductionMultiplier,
    );
  }

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'type': type.name,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'endsAt': endsAt.millisecondsSinceEpoch,
        'sourceWeatherEventId': sourceWeatherEventId,
        'ptibugProductionMultiplier': ptibugProductionMultiplier,
      };

  static WeatherAffliction? fromFirebase(Object? value) {
    if (value is! Map) return null;
    final type = WeatherAfflictionType.values
        .where((candidate) => candidate.name == value['type'])
        .firstOrNull;
    final startedMillis = value['startedAt'];
    final endsMillis = value['endsAt'];
    if (type == null || startedMillis is! num || endsMillis is! num) {
      return null;
    }
    return WeatherAffliction(
      type: type,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedMillis.toInt()),
      endsAt: DateTime.fromMillisecondsSinceEpoch(endsMillis.toInt()),
      sourceWeatherEventId: value['sourceWeatherEventId'] as String?,
      ptibugProductionMultiplier:
          (value['ptibugProductionMultiplier'] as num?)?.toDouble(),
    );
  }
}

class WeatherAfflictionConfig {
  const WeatherAfflictionConfig({
    required this.enabled,
    required this.baseDurationHours,
    required this.immunityHours,
    required this.treatmentCooldownHours,
    required this.ptipoteProductivityMultiplier,
    required this.residentHappinessPenalty,
    required this.structuralMinimumDurationHours,
    required this.personalModuleSlots,
    required this.moduleRefundPhysicalPercent,
    required this.moduleRefundCooldownHours,
    required this.refundData,
    required this.structuralReductionHours,
    required this.treatmentReductionHours,
    required this.treatmentTargetTypes,
  });

  final bool enabled;
  final int baseDurationHours;
  final int immunityHours;
  final int treatmentCooldownHours;
  final double ptipoteProductivityMultiplier;
  final int residentHappinessPenalty;
  final int structuralMinimumDurationHours;
  final int personalModuleSlots;
  final int moduleRefundPhysicalPercent;
  final int moduleRefundCooldownHours;

  /// Always false in this version: Knowledge/Data is never dismantled back
  /// into inventory, even when the remote config is malformed.
  final bool refundData;
  final Map<String, int> structuralReductionHours;
  final Map<String, int> treatmentReductionHours;
  final Map<String, List<String>> treatmentTargetTypes;

  /// Returns the configured duration reduction, or zero for an unknown key.
  int structuralReductionFor(String key) => structuralReductionHours[key] ?? 0;

  /// Returns the configured treatment reduction, or zero for an unknown key.
  int treatmentReductionFor(String key) => treatmentReductionHours[key] ?? 0;

  bool treatmentTargets(String reductionKey, WeatherAfflictionType type) =>
      treatmentTargetTypes[reductionKey]?.contains(type.id) ?? false;

  /// Resolves item compatibility and duration strictly from the shared
  /// Dashboard mapping, not from screen-specific hard-coded switches.
  int treatmentReductionForItem(
    String treatmentItem,
    WeatherAfflictionType type,
  ) {
    for (final entry in weatherAfflictionTreatmentItemByReductionKey.entries) {
      if (entry.value == treatmentItem && treatmentTargets(entry.key, type)) {
        return treatmentReductionFor(entry.key);
      }
    }
    return 0;
  }

  List<String> treatmentItemsFor(WeatherAfflictionType type) {
    final items = <String>{};
    for (final entry in weatherAfflictionTreatmentItemByReductionKey.entries) {
      if (treatmentTargets(entry.key, type) &&
          treatmentReductionFor(entry.key) > 0) {
        items.add(entry.value);
      }
    }
    return items.toList(growable: false);
  }
}

/// Human-readable DEV validation. The runtime parser still falls back to safe
/// defaults; this reports invalid published values before they can be used.
List<String> validateWeatherAfflictionConfig(WeatherAfflictionConfig config) {
  final errors = <String>[];
  if (config.baseDurationHours < 0) {
    errors.add('baseDurationHours must be non-negative.');
  }
  if (config.structuralMinimumDurationHours < 0) {
    errors.add('structuralMinimumDurationHours must be non-negative.');
  }
  if (config.baseDurationHours < config.structuralMinimumDurationHours) {
    errors.add(
      'baseDurationHours must be greater than or equal to structuralMinimumDurationHours.',
    );
  }
  if (config.immunityHours < 0) {
    errors.add('immunityHours must be non-negative.');
  }
  if (config.treatmentCooldownHours < 0) {
    errors.add('treatmentCooldownHours must be non-negative.');
  }
  if (config.personalModuleSlots < 0) {
    errors.add('personalModuleSlots must be non-negative.');
  }
  if (config.moduleRefundPhysicalPercent < 0 ||
      config.moduleRefundPhysicalPercent > 100) {
    errors.add('moduleRefundPhysicalPercent must be between 0 and 100.');
  }
  if (config.moduleRefundCooldownHours < 0) {
    errors.add('moduleRefundCooldownHours must be non-negative.');
  }
  if (config.refundData) {
    errors.add('refundData must remain false: Data is never refundable.');
  }
  if (config.ptipoteProductivityMultiplier < 0 ||
      config.ptipoteProductivityMultiplier > 1) {
    errors.add('ptipoteProductivityMultiplier must be between 0 and 1.');
  }
  if (config.residentHappinessPenalty < 0) {
    errors.add('residentHappinessPenalty must be non-negative.');
  }
  for (final key in weatherAfflictionStructuralReductionKeys) {
    final value = config.structuralReductionHours[key];
    if (value == null) {
      errors.add('Missing structural duration reduction: $key.');
    } else if (value < 0) {
      errors.add('Structural duration reduction $key must be non-negative.');
    }
  }
  for (final key in weatherAfflictionTreatmentReductionKeys) {
    final value = config.treatmentReductionHours[key];
    if (value == null) {
      errors.add('Missing treatment duration reduction: $key.');
    } else if (value < 0) {
      errors.add('Treatment duration reduction $key must be non-negative.');
    }
    final targets = config.treatmentTargetTypes[key];
    if (targets == null || targets.isEmpty) {
      errors.add('Missing treatment targets: $key.');
    } else {
      for (final target in targets) {
        if (!WeatherAfflictionType.values.any((type) => type.id == target)) {
          errors.add('Unknown treatment target $target for $key.');
        }
      }
    }
  }
  return errors;
}

const WeatherAfflictionConfig defaultWeatherAfflictionConfig =
    WeatherAfflictionConfig(
  enabled: true,
  baseDurationHours: 8,
  immunityHours: 24,
  treatmentCooldownHours: 4,
  ptipoteProductivityMultiplier: .70,
  residentHappinessPenalty: 10,
  structuralMinimumDurationHours: 2,
  personalModuleSlots: 3,
  moduleRefundPhysicalPercent: 50,
  moduleRefundCooldownHours: 72,
  refundData: false,
  structuralReductionHours: <String, int>{
    'thermalBasinRain': 1,
    'thermalBasinToxic': 1,
    'ventilationHeat': 2,
    'chloroCanalsRain': 2,
    'filtrationToxic': 2,
  },
  treatmentReductionHours: <String, int>{
    'antiPoisonToxic': 4,
    'antiPoisonJellyToxic': 3,
    'antiPoisonJellyHeat': 3,
    'hydratingJellyHeat': 4,
    'antibioticRain': 4,
  },
  treatmentTargetTypes: <String, List<String>>{
    'antiPoisonToxic': <String>['toxic'],
    'antiPoisonJellyToxic': <String>['toxic'],
    'antiPoisonJellyHeat': <String>['heat'],
    'hydratingJellyHeat': <String>['heat'],
    'antibioticRain': <String>['rain'],
  },
);
