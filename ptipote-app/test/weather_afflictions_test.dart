import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/craft_config.dart';
import 'package:ptipote_app/features/game/tower_operations_config.dart';
import 'package:ptipote_app/features/game/weather_afflictions.dart';

WeatherAfflictionConfig _configFromDefault({
  int? baseDurationHours,
  int? structuralMinimumDurationHours,
  int? moduleRefundPhysicalPercent,
  bool? refundData,
  Map<String, int>? structuralReductionHours,
  Map<String, int>? treatmentReductionHours,
  Map<String, List<String>>? treatmentTargetTypes,
}) {
  const base = defaultWeatherAfflictionConfig;
  return WeatherAfflictionConfig(
    enabled: base.enabled,
    baseDurationHours: baseDurationHours ?? base.baseDurationHours,
    immunityHours: base.immunityHours,
    treatmentCooldownHours: base.treatmentCooldownHours,
    ptipoteProductivityMultiplier: base.ptipoteProductivityMultiplier,
    residentHappinessPenalty: base.residentHappinessPenalty,
    structuralMinimumDurationHours:
        structuralMinimumDurationHours ?? base.structuralMinimumDurationHours,
    personalModuleSlots: base.personalModuleSlots,
    moduleRefundPhysicalPercent:
        moduleRefundPhysicalPercent ?? base.moduleRefundPhysicalPercent,
    moduleRefundCooldownHours: base.moduleRefundCooldownHours,
    refundData: refundData ?? base.refundData,
    structuralReductionHours:
        structuralReductionHours ?? base.structuralReductionHours,
    treatmentReductionHours:
        treatmentReductionHours ?? base.treatmentReductionHours,
    treatmentTargetTypes: treatmentTargetTypes ?? base.treatmentTargetTypes,
  );
}

void main() {
  test(
      'weather affliction is timestamp based and cannot end before a treatment',
      () {
    final now = DateTime(2026, 8, 21, 12);
    final affliction = WeatherAffliction(
      type: WeatherAfflictionType.toxic,
      startedAt: now,
      endsAt: now.add(const Duration(hours: 8)),
    );

    expect(affliction.isActiveAt(now.add(const Duration(hours: 7))), isTrue);
    expect(affliction.isActiveAt(now.add(const Duration(hours: 8))), isFalse);
    expect(
      affliction.shorten(const Duration(hours: 10), now).endsAt,
      now,
    );
  });

  test('afflictions serialize their stable timestamps', () {
    final now = DateTime(2026, 8, 21, 12);
    final original = WeatherAffliction(
      type: WeatherAfflictionType.heat,
      startedAt: now,
      endsAt: now.add(const Duration(hours: 8)),
      sourceWeatherEventId: 'weather-42',
      ptibugProductionMultiplier: .7,
    );

    final restored = WeatherAffliction.fromFirebase(original.toFirebase());
    expect(restored, isNotNull);
    expect(restored!.type, WeatherAfflictionType.heat);
    expect(restored.sourceWeatherEventId, 'weather-42');
    expect(restored.endsAt, original.endsAt);
    expect(restored.ptibugProductionMultiplier, .7);
    expect(
      restored
          .shorten(const Duration(hours: 3), now)
          .ptibugProductionMultiplier,
      .7,
    );
  });

  test('all public labels match the target population', () {
    expect(WeatherAfflictionType.heat.ptipoteLabel, 'Insolation');
    expect(WeatherAfflictionType.heat.ptibugLabel, 'Surrégime');
    expect(WeatherAfflictionType.rain.ptipoteLabel, 'Infection');
    expect(WeatherAfflictionType.rain.ptibugLabel, 'Humidifié');
    expect(WeatherAfflictionType.toxic.ptipoteLabel, 'Intoxiqué');
    expect(WeatherAfflictionType.toxic.ptibugLabel, 'Intoxiqué');
  });

  test('personal modules use the canonical crafted item names', () {
    expect(
      ptipoteModuleDefinitionForItem('Protection thermique P’TIPOTE')
          ?.prevents(WeatherAfflictionType.heat),
      isTrue,
    );
    expect(
      ptipoteModuleDefinitionForItem('Protection pluie/humidité P’TIPOTE')
          ?.prevents(WeatherAfflictionType.rain),
      isTrue,
    );
    expect(
      ptipoteModuleDefinitionForItem('Protection filtrante/toxique P’TIPOTE')
          ?.prevents(WeatherAfflictionType.toxic),
      isTrue,
    );
  });

  test('legacy personal protection names still resolve to their craft module',
      () {
    expect(
      canonicalPtipoteModuleItemName('Protection pluie P’TIPOTE'),
      'Protection pluie/humidité P’TIPOTE',
    );
    expect(
      canonicalPtipoteModuleItemName('Protection filtrante P’TIPOTE'),
      'Protection filtrante/toxique P’TIPOTE',
    );
    expect(
      ptipoteModuleDefinitionForItem('Protection pluie P’TIPOTE')
          ?.prevents(WeatherAfflictionType.rain),
      isTrue,
    );
  });

  test('weather icons match the public health labels', () {
    expect(WeatherAfflictionType.heat.emoji, '🔥');
    expect(WeatherAfflictionType.rain.emoji, '🦠');
    expect(WeatherAfflictionType.toxic.emoji, '🤢');
  });

  test('personal protections and treatments retain their approved recipes', () {
    final recipes = <String, CraftRecipe>{
      for (final recipe in defaultCraftConfig.recipes) recipe.id: recipe,
    };
    void expectRecipe(
      String id, {
      required String result,
      required int amount,
      required int durationMinutes,
      required Map<String, int> ingredients,
    }) {
      final recipe = recipes[id];
      expect(recipe, isNotNull, reason: 'Missing recipe: $id');
      expect(recipe!.resultItem, result);
      expect(recipe.resultAmount, amount);
      expect(recipe.durationMinutes, durationMinutes);
      expect(recipe.ingredients, ingredients);
    }

    expectRecipe(
      'ptipoteThermalProtection',
      result: 'Protection thermique P’TIPOTE',
      amount: 1,
      durationMinutes: 30,
      ingredients: const <String, int>{
        'Organique': 10,
        'Minéral': 5,
        'Réflecteur thermique': 5,
      },
    );
    expectRecipe(
      'ptipoteRainProtection',
      result: 'Protection pluie/humidité P’TIPOTE',
      amount: 1,
      durationMinutes: 30,
      ingredients: const <String, int>{
        'Organique': 15,
        'Couche imperméabilisante': 5,
      },
    );
    expectRecipe(
      'ptipoteToxicProtection',
      result: 'Protection filtrante/toxique P’TIPOTE',
      amount: 1,
      durationMinutes: 30,
      ingredients: const <String, int>{
        'Organique': 8,
        'Minéral': 7,
        'Filtre': 10,
      },
    );
    expectRecipe(
      'antiPoison',
      result: 'Anti-poison',
      amount: 4,
      durationMinutes: 10,
      ingredients: const <String, int>{'Organique': 2, 'Minéral': 1},
    );
    expectRecipe(
      'antiPoisonJelly',
      result: 'Gelée anti-poison',
      amount: 3,
      durationMinutes: 10,
      ingredients: const <String, int>{'Organique': 2, 'Minéral': 1},
    );
    expectRecipe(
      'hydratingJelly',
      result: 'Gelée hydratante',
      amount: 3,
      durationMinutes: 10,
      ingredients: const <String, int>{'Organique': 2},
    );
    expectRecipe(
      'antibiotic',
      result: 'Antibiotique',
      amount: 3,
      durationMinutes: 10,
      ingredients: const <String, int>{'Organique': 2},
    );
  });

  test('default configuration carries every approved weather rule', () {
    const config = defaultWeatherAfflictionConfig;
    expect(validateWeatherAfflictionConfig(config), isEmpty);
    expect(config.baseDurationHours, 8);
    expect(config.immunityHours, 24);
    expect(config.treatmentCooldownHours, 4);
    expect(config.ptipoteProductivityMultiplier, .70);
    expect(config.residentHappinessPenalty, 10);
    expect(config.structuralMinimumDurationHours, 2);
    expect(config.personalModuleSlots, 3);
    expect(config.moduleRefundPhysicalPercent, 50);
    expect(config.moduleRefundCooldownHours, 72);
    expect(config.refundData, isFalse);
    expect(config.structuralReductionFor('ventilationHeat'), 2);
    expect(config.structuralReductionFor('chloroCanalsRain'), 2);
    expect(config.structuralReductionFor('filtrationToxic'), 2);
    expect(config.structuralReductionFor('thermalBasinRain'), 1);
    expect(config.structuralReductionFor('thermalBasinToxic'), 1);
    expect(config.treatmentReductionFor('antiPoisonToxic'), 4);
    expect(config.treatmentReductionFor('antiPoisonJellyToxic'), 3);
    expect(config.treatmentReductionFor('antiPoisonJellyHeat'), 3);
    expect(config.treatmentReductionFor('hydratingJellyHeat'), 4);
    expect(config.treatmentReductionFor('antibioticRain'), 4);
    expect(
        config.treatmentTargets('antiPoisonToxic', WeatherAfflictionType.toxic),
        isTrue);
    expect(
        config.treatmentTargets(
            'antiPoisonJellyHeat', WeatherAfflictionType.heat),
        isTrue);
    expect(
        config.treatmentTargets('antibioticRain', WeatherAfflictionType.heat),
        isFalse);
    expect(
      config.treatmentItemsFor(WeatherAfflictionType.heat),
      unorderedEquals(<String>['Gelée anti-poison', 'Gelée hydratante']),
    );
  });

  test('Tower operations exposes the central affliction configuration', () {
    final config = defaultTowerOperationsConfig.weatherAfflictions;
    expect(config.baseDurationHours, 8);
    expect(config.moduleRefundPhysicalPercent, 50);
    expect(config.moduleRefundCooldownHours, 72);
  });

  test('configuration validation rejects invalid ranges and missing mappings',
      () {
    final invalidDuration = _configFromDefault(
      baseDurationHours: 1,
      structuralMinimumDurationHours: 2,
    );
    expect(
      validateWeatherAfflictionConfig(invalidDuration),
      contains(
        'baseDurationHours must be greater than or equal to structuralMinimumDurationHours.',
      ),
    );

    final invalidRefund = _configFromDefault(
      moduleRefundPhysicalPercent: 101,
    );
    expect(
      validateWeatherAfflictionConfig(invalidRefund),
      contains('moduleRefundPhysicalPercent must be between 0 and 100.'),
    );

    final invalidDataRefund = _configFromDefault(refundData: true);
    expect(
      validateWeatherAfflictionConfig(invalidDataRefund),
      contains('refundData must remain false: Data is never refundable.'),
    );

    final missingTreatment = _configFromDefault(
      treatmentReductionHours: <String, int>{
        ...defaultWeatherAfflictionConfig.treatmentReductionHours,
      }..remove('antibioticRain'),
    );
    expect(
      validateWeatherAfflictionConfig(missingTreatment),
      contains('Missing treatment duration reduction: antibioticRain.'),
    );

    final unknownTreatmentTarget = _configFromDefault(
      treatmentTargetTypes: <String, List<String>>{
        ...defaultWeatherAfflictionConfig.treatmentTargetTypes,
        'antiPoisonToxic': <String>['not-a-weather-type'],
      },
    );
    expect(
      validateWeatherAfflictionConfig(unknownTreatmentTarget),
      contains(
          'Unknown treatment target not-a-weather-type for antiPoisonToxic.'),
    );
  });

  test('unknown reductions are safely neutral', () {
    const config = defaultWeatherAfflictionConfig;
    expect(config.structuralReductionFor('not-a-rule'), 0);
    expect(config.treatmentReductionFor('not-a-treatment'), 0);
  });

  test('the Dashboard target mapping drives treatment compatibility', () {
    final config = _configFromDefault(
      treatmentTargetTypes: <String, List<String>>{
        ...defaultWeatherAfflictionConfig.treatmentTargetTypes,
        'antiPoisonToxic': <String>['heat'],
      },
    );

    expect(
      config.treatmentReductionForItem(
        'Anti-poison',
        WeatherAfflictionType.heat,
      ),
      4,
    );
    expect(
      config.treatmentReductionForItem(
        'Anti-poison',
        WeatherAfflictionType.toxic,
      ),
      0,
    );
  });
}
