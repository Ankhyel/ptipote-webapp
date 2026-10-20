import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/elevage/elevage_config.dart';
import 'package:ptipote_app/features/elevage/elevage_engine.dart';
import 'package:ptipote_app/features/elevage/elevage_presentation.dart';

void main() {
  const now = 1700000000000;

  test('état initial : Alcôves configurées et aucun individu implicite', () {
    final state = ElevageSave.initial(defaultElevageConfig, now: now);
    expect((state.data['alcoves'] as List), hasLength(4));
    expect(state.data['activeIndividualIds'], isEmpty);
  });

  test('adoption physique et Co-élevage sont persistables et exclusifs', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
      source: state,
      alcoveId: 'alcove-1',
      name: 'Silex',
      physical: true,
      physicalFigureRef: 'mock:one',
      now: now,
      config: defaultElevageConfig,
    );
    expect((state.data['activeIndividualIds'] as List), hasLength(1));
    expect(
      () => ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-2',
        name: 'Doublon',
        physical: true,
        physicalFigureRef: 'mock:one',
        now: now + 1,
        config: defaultElevageConfig,
      ),
      throwsStateError,
    );
    state = ElevageDomain.adopt(
      source: state,
      alcoveId: 'alcove-2',
      name: 'Prêt',
      physical: false,
      now: now + 2,
      config: defaultElevageConfig.copyWith(coRearingDurationHours: 1),
    );
    final id = (state.data['activeIndividualIds'] as List).last as String;
    final ownership =
        (state.data['individuals'] as Map)[id]['ownership'] as Map;
    expect(ownership['expiresAt'],
        now + 2 + const Duration(hours: 1).inMilliseconds);
  });

  test('nourriture, structure et souvenirs restent distincts', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Roche',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.addDevInventory(state);
    expect((state.data['inventory']['generic'] as Map)['organic'], 30);
    expect((state.data['inventory']['generic'] as Map)['mineral'], 30);
    expect((state.data['inventory']['special'] as Map)['LIMESTONE'], 3);
    state = ElevageDomain.setIndividualSatiety(state, id, 80, now);
    final favorite = (state.data['individuals'] as Map)[id]['generatedProfile']
        ['foodPreference'] as String;
    state = ElevageDomain.offerFood(
        state, id, favorite, now + 1, defaultElevageConfig);
    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'INTERMEDIATE';
    state = ElevageDomain.offerStructural(state, id, 'IRON', now + 2);
    final care = (state.data['individuals'] as Map)[id]['care'] as Map;
    expect(care['lastMealAt'], now + 1);
    expect((care['structuralIntake'] as Map)['total'], 2);
    expect((state.data['memoryEvents'] as Map)[id]['FIRST_FOOD'], isNotNull);
    expect((state.data['memoryEvents'] as Map)[id]['FIRST_FAVORITE_FOOD'],
        isNotNull);
  });

  test('Mini-Lisière génère trois points persistants et ne donne qu’un gain',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Roche',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.startForaging(
        state, id, 'FOREST', now, defaultElevageConfig);
    final run = (state.data['runsByIndividualId'] as Map)[id] as Map;
    expect(run['points'], hasLength(3));
    expect(ElevageDomain.foragingStatus(state, id, now), 'IN_PROGRESS');
    state = ElevageDomain.claimForaging(state, id, 'point-0', now + 20000);
    expect(ElevageDomain.foragingStatus(state, id, now + 20000), 'COMPLETED');
    expect(
        (state.data['inventory']['generic'] as Map)['organic'], greaterThan(0));
    expect(() => ElevageDomain.claimForaging(state, id, 'point-1', now + 20001),
        throwsStateError);
  });

  test('craft historique et production locale se comportent correctement', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Roche',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    state = ElevageDomain.addDevInventory(state);
    state.data['discoveredItemIds'] = <String>['LIMESTONE', 'ALGAE'];
    final basin = defaultElevageConfig.recipes
        .firstWhere((recipe) => recipe.id == 'BASSIN');
    state = ElevageDomain.craft(state, basin, now + 1, defaultElevageConfig);
    final instanceId =
        (state.data['installationInventory'] as Map).keys.single as String;
    state = ElevageDomain.place(state, 'alcove-1', 0, instanceId, now + 2);
    final fastProduction =
        defaultElevageConfig.copyWith(productionIntervalSeconds: 60);
    state = ElevageDomain.refreshAlcove(
        state, 'alcove-1', now + 62000, fastProduction);
    final placed =
        ((state.data['alcoves'] as List).first as Map)['slots'][0] as Map;
    expect((placed['productionState']['availableByItemId'] as Map)['ALGAE'], 1);
    expect((placed['paidCost'] as Map)['mineral'], 10);
  });

  test('retour de Co-élevage est idempotent', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final config = defaultElevageConfig.copyWith(coRearingDurationHours: 1);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Prêt',
        physical: false,
        now: now,
        config: config);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.processReturns(
        state, now + const Duration(hours: 1).inMilliseconds);
    expect(state.data['activeIndividualIds'], isEmpty);
    expect((state.data['coRearingReturnLedger'] as Map)[id], isNotNull);
    state = ElevageDomain.processReturns(
        state, now + const Duration(hours: 2).inMilliseconds);
    expect((state.data['pendingNotifications'] as List), hasLength(1));
  });

  test(
      'Sourcier applique les prix configurés et le déménagement agrège avant floor',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state.data['inventory']['bioPiles'] = 7;
    final config = defaultElevageConfig.copyWith(fibrousFruitPrice: 7);
    state = ElevageDomain.buyTreat(state, 'FIBROUS_FRUIT', config);
    expect(state.data['inventory']['bioPiles'], 0);
    expect((state.data['inventory']['special'] as Map)['FIBROUS_FRUIT'], 1);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][0] = <String, dynamic>{
      'acquisitionMode': 'CRAFTED',
      'paidCost': <String, dynamic>{'organic': 3, 'mineral': 1},
    };
    alcove['slots'][1] = <String, dynamic>{
      'acquisitionMode': 'CRAFTED',
      'paidCost': <String, dynamic>{'organic': 2, 'mineral': 2},
    };
    final refund = ElevageDomain.moveOutRefund(state, 'alcove-1', config);
    expect(refund, <String, int>{'organic': 2, 'mineral': 1});
  });

  test('starter réduit et Carnet individuel commencent sans révélation', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final special = state.data['inventory']['special'] as Map;
    expect(special['ROOT'], 1);
    expect(special['LEAF'], 1);
    final journal =
        (state.data['individuals'] as Map)[id]['observationJournal'] as Map;
    expect((journal['observations'] as Map), isEmpty);
  });

  test('observations dédoublonnées suivent hypothèse puis confirmation', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    final favorite = individual['generatedProfile']['foodPreference'] as String;
    (state.data['inventory']['special'] as Map)[favorite] = 4;
    state = ElevageDomain.setIndividualSatiety(state, id, 95, now);
    for (var index = 0; index < 4; index++) {
      state = ElevageDomain.offerFood(
          state,
          id,
          favorite,
          now + Duration(hours: index * 24).inMilliseconds,
          defaultElevageConfig);
    }
    final observations = ((state.data['individuals'] as Map)[id]
        ['observationJournal']['observations'] as Map);
    final observation = observations['FOOD_FAVORITE:$favorite'] as Map;
    expect(observations, hasLength(1));
    expect(observation['count'], 4);
    expect(observation['status'], 'CONFIRMED');
    final restored = ElevageSave.fromJson(state.toJson());
    expect(
        (((restored.data['individuals'] as Map)[id]['observationJournal']
            ['observations'] as Map)['FOOD_FAVORITE:$favorite']['count']),
        4);
  });

  test('satiété V2 est dérivée et bloque un repas à 100', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final favorite = (state.data['individuals'] as Map)[id]['generatedProfile']
        ['foodPreference'] as String;
    (state.data['inventory']['special'] as Map)[favorite] = 2;
    state = ElevageDomain.setIndividualSatiety(state, id, 95, now);
    state =
        ElevageDomain.offerFood(state, id, favorite, now, defaultElevageConfig);
    expect(ElevageDomain.satietyPercent(state, id, now, defaultElevageConfig),
        100);
    expect(
        ElevageDomain.satietyPercent(
            state,
            id,
            now + const Duration(hours: 24).inMilliseconds,
            defaultElevageConfig),
        0);
    expect(
        () => ElevageDomain.offerFood(
            state, id, favorite, now + 1, defaultElevageConfig),
        throwsStateError);
  });

  test('observation d’ombre est persistante et atteint ses seuils', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.observeShade(state, id, now, defaultElevageConfig);
    state = ElevageDomain.observeShade(state, id,
        now + const Duration(minutes: 10).inMilliseconds, defaultElevageConfig);
    final observation = ((state.data['individuals'] as Map)[id]
        ['observationJournal']['observations']['LIGHT_SHADE:LIGHT'] as Map);
    expect(observation['count'], 2);
    expect(observation['status'], 'SUSPECTED');
    expect(
        ((state.data['individuals'] as Map)[id]['progressionEvidence']
            as Map)['foragingCount'],
        0);
  });

  test('un objet posé quitte l’inventaire et peut être récupéré', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'ROOT', 'ZONE_2', now + 1, defaultElevageConfig);
    expect((state.data['inventory']['special'] as Map)['ROOT'], 0);
    final item = ElevageDomain.sceneItems(state, 'alcove-1').single;
    expect(item['itemId'], 'ROOT');
    expect(item['zoneId'], 'ZONE_2');
    final restored = ElevageSave.fromJson(state.toJson());
    expect(ElevageDomain.sceneItems(restored, 'alcove-1').single['itemId'],
        'ROOT');
    state = ElevageDomain.recoverSceneItem(
        state, 'alcove-1', item['instanceId'] as String);
    expect(ElevageDomain.sceneItems(state, 'alcove-1'), isEmpty);
    expect((state.data['inventory']['special'] as Map)['ROOT'], 1);
  });

  test('un Intermédiaire emporte une racine désirée hors d’une zone extrême',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'INTERMEDIATE';
    ((state.data['individuals'] as Map)[id]['generatedProfile']
        as Map)['foodPreference'] = 'ROOT';
    state = ElevageDomain.setIndividualSatiety(state, id, 60, now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][2] = <String, dynamic>{
      'definitionId': 'BASSIN',
      'zoneId': 'ZONE_3',
    };
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'ROOT', 'ZONE_3', now + 1, defaultElevageConfig);
    final first = ElevageDomain.sceneItems(state, 'alcove-1').single;
    final outcome = ElevageDomain.sceneItemOutcome(state, id, 'alcove-1',
        first['instanceId'] as String, now + 2, defaultElevageConfig);
    expect(outcome.behavior, 'FLEE_WITH_ITEM');
    // Avec la nuit locale réelle de la fixture, Z1 est le refuge viable.
    expect(outcome.targetZoneId, 'ZONE_1');
    expect(outcome.observationCount, 1);
    state = ElevageDomain.relocateSceneItem(
        state,
        'alcove-1',
        first['instanceId'] as String,
        outcome.targetZoneId!,
        defaultElevageConfig);
    expect(
        ElevageDomain.sceneItems(state, 'alcove-1').single['zoneId'], 'ZONE_1');
  });

  test(
      'consommer un objet posé le retire de la scène et conserve les règles repas',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    ((state.data['individuals'] as Map)[id]['generatedProfile']
        as Map)['foodPreference'] = 'ROOT';
    state = ElevageDomain.setIndividualSatiety(state, id, 60, now);
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'ROOT', 'ZONE_2', now + 1, defaultElevageConfig);
    final item = ElevageDomain.sceneItems(state, 'alcove-1').single;
    state = ElevageDomain.interactSceneItem(state, id, 'alcove-1',
        item['instanceId'] as String, now + 2, defaultElevageConfig);
    expect(ElevageDomain.sceneItems(state, 'alcove-1'), isEmpty);
    expect(
        ((state.data['individuals'] as Map)[id]['care'] as Map)['lastMealAt'],
        now + 2);
  });

  test('reset QA remet la partie à zéro avec son starter réduit', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    state = ElevageDomain.addDevInventory(state);
    final reset = ElevageDomain.resetGame(defaultElevageConfig, now + 1);
    expect(reset.data['activeIndividualIds'], isEmpty);
    expect((reset.data['alcoves'] as List), hasLength(4));
    expect(reset.data['runsByIndividualId'], isEmpty);
    expect(reset.data['sceneItemsByAlcoveId'], isEmpty);
    expect((reset.data['inventory']['special'] as Map),
        <String, dynamic>{'ROOT': 1, 'LEAF': 1});
  });

  test('reset Alcôves ne détruit pas les ressources portables', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state.data['inventory']['generic']['organic'] = 7;
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final reset =
        ElevageDomain.resetAlcoves(state, defaultElevageConfig, now + 1);
    expect(reset.data['activeIndividualIds'], isEmpty);
    expect(reset.data['inventory']['generic']['organic'], 7);
    expect(reset.data['installationInventory'], isEmpty);
  });

  test('tout loot normal possède un libellé français et une catégorie', () {
    for (final item in ElevageDomain.foragingLootItemIds) {
      expect(ElevagePresentation.itemLabel(item), isNot('Objet inconnu'));
      expect(ElevagePresentation.itemCategory(item), isNotEmpty);
    }
  });

  test('inventaire V1 découpe les quantités en stacks de 12', () {
    expect(ElevagePresentation.stackQuantities(0, 12), isEmpty);
    expect(ElevagePresentation.stackQuantities(12, 12), <int>[12]);
    expect(ElevagePresentation.stackQuantities(28, 12), <int>[12, 12, 4]);
  });

  test('jour/nuit et installations modifient uniquement leur micro-zone', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][2] = <String, dynamic>{
      'definitionId': 'BASSIN',
      'zoneId': 'ZONE_3',
    };
    final daytime = DateTime(2026, 1, 1, 12).millisecondsSinceEpoch;
    expect(ElevageDomain.dayNightPhase(daytime, defaultElevageConfig), 'DAY');
    expect(
        ElevageDomain.dayNightPhase(
            DateTime(2026, 1, 1, 2).millisecondsSinceEpoch,
            defaultElevageConfig),
        'NIGHT');
    final zone3 = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_3', defaultElevageConfig,
        now: daytime);
    final zone2 = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
        now: daytime);
    expect(zone3['humidity'], 4); // baseline 2/5 + bassin local +2
    expect(zone2['humidity'], 3); // diffusion +1 vers la zone adjacente
  });

  test('FOLLOW et CUDDLE créent des actions et des observations plafonnées',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final config =
        defaultElevageConfig.copyWith(observationEvidenceCooldownMinutes: 0);
    state = ElevageDomain.follow(state, id, 'ZONE_2', now + 1, config);
    state = ElevageDomain.cuddle(state, id, now + 2, config);
    final observations = ((state.data['individuals'] as Map)[id]
        ['observationJournal']['observations'] as Map);
    expect((observations['FOLLOW:GENERAL'] as Map)['status'], 'OBSERVED');
    expect((observations['CUDDLE:GENERAL'] as Map)['status'], 'OBSERVED');
    expect(
        ((state.data['individuals'] as Map)[id]['personality']['tendencies']
            as Map)['contact'],
        greaterThan(0));
  });

  test('observation différée suit OBSERVED, SUSPECTED, CONFIRMED sans spam',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final config =
        defaultElevageConfig.copyWith(observationEvidenceCooldownMinutes: 0);
    state = ElevageDomain.observeShade(state, id, now + 1, config);
    Map entry() => ((state.data['individuals'] as Map)[id]['observationJournal']
        ['observations']['LIGHT_SHADE:LIGHT'] as Map);
    expect(entry()['status'], 'OBSERVED');
    state = ElevageDomain.observeShade(state, id, now + 2, config);
    expect(entry()['status'], 'SUSPECTED');
    state = ElevageDomain.observeShade(state, id, now + 3, config);
    expect(entry()['status'], 'SUSPECTED');
    state = ElevageDomain.observeShade(state, id, now + 4, config);
    expect(entry()['status'], 'CONFIRMED');
    final evidence = entry()['meaningfulEvidenceCount'];
    state = ElevageDomain.observeShade(state, id, now + 5, config);
    expect(entry()['meaningfulEvidenceCount'], evidence);
    expect(entry()['rawBehaviorCount'], 5);
  });

  test('satiété V2 applique le taux propre à chaque stade', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.setIndividualSatiety(state, id, 100, now);
    expect(
        ElevageDomain.satietyPercent(
            state,
            id,
            now + const Duration(hours: 3).inMilliseconds,
            defaultElevageConfig),
        70);
    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'INTERMEDIATE';
    state = ElevageDomain.setIndividualSatiety(state, id, 100, now);
    expect(
        ElevageDomain.satietyPercent(
            state,
            id,
            now + const Duration(hours: 6).inMilliseconds,
            defaultElevageConfig),
        70);
    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'MATURE';
    state = ElevageDomain.setIndividualSatiety(state, id, 100, now);
    expect(
        ElevageDomain.satietyPercent(
            state,
            id,
            now + const Duration(hours: 10).inMilliseconds,
            defaultElevageConfig),
        70);
  });

  test('un objet posé fournit une décision autonome sans bouton manuel', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    ((state.data['individuals'] as Map)[id]['generatedProfile']
        as Map)['foodPreference'] = 'ROOT';
    state = ElevageDomain.setIndividualSatiety(state, id, 60, now);
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'ROOT', 'ZONE_2', now + 1, defaultElevageConfig);
    final decision = ElevageDomain.nextAutonomousSceneDecision(
        state, id, 'alcove-1', now + 2, defaultElevageConfig);
    expect(decision, isNotNull);
    expect(decision!.zoneId, 'ZONE_2');
    expect(decision.outcome.consumed, isTrue);
    state = ElevageDomain.interactSceneItem(state, id, 'alcove-1',
        decision.instanceId, now + 2, defaultElevageConfig);
    expect(ElevageDomain.sceneItems(state, 'alcove-1'), isEmpty);
  });

  test('une forte satiété fait inspecter puis ignorer un repas normal', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'ROOT', 'ZONE_1', now + 1, defaultElevageConfig);
    final item = ElevageDomain.sceneItems(state, 'alcove-1').single;
    final outcome = ElevageDomain.sceneItemOutcome(state, id, 'alcove-1',
        item['instanceId'] as String, now + 2, defaultElevageConfig);
    expect(outcome.behavior, 'OBSERVE');
    expect(outcome.consumed, isFalse);
  });

  test('décision autonome varie ses réactions et atteint Z1 ou Z4', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'ROOT', 'ZONE_1', now + 1, defaultElevageConfig);
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'LEAF', 'ZONE_4', now + 2, defaultElevageConfig);
    final first = ElevageDomain.nextAutonomousSceneDecision(
        state, id, 'alcove-1', now + 3, defaultElevageConfig);
    expect(<String>['ZONE_1', 'ZONE_4'], contains(first!.zoneId));
    final second = ElevageDomain.nextAutonomousSceneDecision(
        state, id, 'alcove-1', now + 3, defaultElevageConfig,
        lastBehavior: first.outcome.behavior);
    expect(second?.outcome.behavior, isNot(first.outcome.behavior));
  });

  test('phase forcée et installation diffusent uniquement aux zones adjacentes',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'BASSIN',
      'zoneId': 'ZONE_2',
    };
    final day = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
        now: now, phaseOverride: 'DAY');
    final night = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
        now: now, phaseOverride: 'NIGHT');
    final other = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_3', defaultElevageConfig,
        now: now, phaseOverride: 'DAY');
    expect(day['humidity'], 4);
    expect(other['humidity'], 3); // diffusion bassin Z2 → Z3, pas de reliquat.
    expect(night['light'], lessThan(day['light']!));
    expect(
        ElevageDomain.dayNightRemainingMs(now, defaultElevageConfig,
            phaseOverride: 'DAY'),
        const Duration(hours: 4).inMilliseconds);
  });

  test('migration QA V17 nettoie une ancienne save une seule fois', () {
    final legacy = ElevageSave.initial(defaultElevageConfig, now: now).toJson()
      ..remove('qaInventoryResetV17');
    legacy['inventory'] = <String, dynamic>{
      'generic': <String, int>{'organic': 99, 'mineral': 88},
      'special': <String, int>{'ROOT': 42, 'IRON': 9, 'SEED': 3},
      'bioPiles': 17,
    };
    final cleaned = ElevageSave.fromJson(legacy);
    final inventory = cleaned.data['inventory'] as Map;
    expect(inventory['generic'],
        <String, int>{'organic': 0, 'mineral': 0, 'energy': 0});
    expect(inventory['special'], <String, int>{'ROOT': 1, 'LEAF': 1});
    expect(inventory['bioPiles'], 0);
    expect(cleaned.data['qaInventoryResetV17'], isTrue);

    final persisted = cleaned.toJson();
    (persisted['inventory'] as Map)['special']['ROOT'] = 3;
    final reloaded = ElevageSave.fromJson(persisted);
    expect((reloaded.data['inventory'] as Map)['special']['ROOT'], 3);
  });

  test('zones jour et HUD moyen utilisent les quatre valeurs discrètes', () {
    final state = ElevageSave.initial(defaultElevageConfig, now: now);
    final scales = <int>[];
    for (final zone in defaultElevageConfig.sceneZones) {
      final environment = ElevageDomain.zoneEnvironment(
          state, 'alcove-1', zone.id, defaultElevageConfig,
          now: now, phaseOverride: 'DAY');
      scales.add(ElevagePresentation.environmentScale(environment['light']!));
    }
    expect(scales, <int>[2, 3, 3, 4]);
    final average = ElevageDomain.averageZoneEnvironment(
        state, 'alcove-1', defaultElevageConfig,
        now: now, phaseOverride: 'DAY');
    expect(ElevagePresentation.environmentScale(average['light']!), 3);
  });

  test('courbe Résonance reste locale et dérivée de la configuration', () {
    expect(defaultElevageConfig.resonanceLightComfort(2), 1);
    expect(defaultElevageConfig.resonanceLightComfort(3), 0);
    expect(defaultElevageConfig.resonanceLightComfort(4), -1);
    expect(defaultElevageConfig.resonanceLightComfort(5), -2);
    expect(
        ElevageDomain.localComfort(
            <String, int>{'light': 2, 'temperature': 2, 'humidity': 2},
            defaultElevageConfig),
        'NEUTRAL');
    expect(
        ElevageDomain.localComfort(
            <String, int>{'light': 4, 'temperature': 3, 'humidity': 3},
            defaultElevageConfig),
        'NEUTRAL');
  });

  test('nuit canonique, moyenne arrondie et Abri minéral restent exacts', () {
    final state = ElevageSave.initial(defaultElevageConfig, now: now);
    final night = <int>[
      for (final zone in defaultElevageConfig.sceneZones)
        ElevagePresentation.environmentScale(ElevageDomain.zoneEnvironment(
            state, 'alcove-1', zone.id, defaultElevageConfig,
            now: now, phaseOverride: 'NIGHT')['light']!),
    ];
    expect(night, <int>[1, 2, 2, 3]);
    expect((6 / 4).round(), 2);
    expect(
        defaultElevageConfig.installation('ABRI_MINERAL_PROFOND')!.humidity, 1);
  });

  test('un axe extrême domine strictement le confort local', () {
    expect(
        ElevageDomain.localComfort(
            <String, int>{'light': -2, 'temperature': -2, 'humidity': 2},
            defaultElevageConfig),
        'EXTREME');
  });

  test('personnalité V0 conserve ses poids, son tempo et sa baseline', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final individual =
        ((state.data['individuals'] as Map).values.single as Map);
    expect(
        ElevageDomain.personalityWeights(defaultElevageConfig),
        <String, double>{
          'baseline': .5,
          'baby': .25,
          'intermediate': .15,
          'adultPlasticity': .1,
        });
    final before = ElevageDomain.personalityValue(individual, 'initiative');
    ElevageDomain.follow(state, individual['id'] as String, 'ZONE_1', now + 1,
        defaultElevageConfig);
    expect(ElevageDomain.personalityValue(individual, 'initiative'), before);
    expect(ElevageDomain.evidenceForInspection(individual), anyOf(1, 2));
  });

  test('need peut rester interne, request respecte âge et initiative', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    // Résonance dort jusqu'au début de matinée ; choisir une phase éveillée
    // pour vérifier la Request indépendamment du rythme circadien.
    final requestAt = defaultElevageConfig.dayNightCycleHours *
        const Duration(hours: 1).inMilliseconds *
        3 ~/
        4;
    state = ElevageDomain.setIndividualSatiety(state, id, 0, requestAt);
    expect(ElevageDomain.hunger(state, id, requestAt, defaultElevageConfig),
        anyOf('HUNGRY', 'VERY_HUNGRY'));
    expect(
        ElevageDomain.isSleeping(individual, requestAt, defaultElevageConfig),
        isFalse);
    state = ElevageDomain.refreshRequest(
        state, id, requestAt, defaultElevageConfig);
    expect((state.data['individuals'] as Map)[id]['activeRequest'], isNotNull);
    expect(
        ElevageDomain.activeRequest(state, id, requestAt)?['signal'], 'HUNGER');
    expect(
        ElevageDomain.activeRequest(
            state, id, requestAt + const Duration(seconds: 91).inMilliseconds),
        isNull);
  });

  test('sommeil mineral décalé supporte fenêtres multiples et choisit un spot',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    individual['onboardingAwakeLock'] = false;
    expect(ElevageDomain.circadianProfile(individual), 'SHIFTED_DIURNAL');
    expect(ElevageDomain.sleepWindows(individual), hasLength(2));
    expect(
        ElevageDomain.isSleeping(individual, 0, defaultElevageConfig), isTrue);
    expect(ElevageDomain.sleepZone(state, id, 0, defaultElevageConfig),
        isNotEmpty);
  });

  test('les durées de sommeil du Dashboard règlent réellement Résonance', () {
    final config = defaultElevageConfig.copyWith(
      dayDurationHours: 3,
      nightDurationHours: 1,
      mineralDaySleepMinutes: 150,
      mineralLateNightSleepMinutes: 30,
    );
    var state = ElevageSave.initial(config, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Réglé',
        physical: false,
        now: now,
        config: config);
    final individual = ((state.data['individuals'] as Map).values.single as Map)
      ..['onboardingAwakeLock'] = false;
    const minute = Duration(minutes: 1);
    expect(ElevageDomain.isSleeping(individual, 0, config), isTrue);
    expect(
        ElevageDomain.isSleeping(
            individual, 149 * minute.inMilliseconds, config),
        isTrue);
    expect(
        ElevageDomain.isSleeping(
            individual, 150 * minute.inMilliseconds, config),
        isFalse);
    expect(
        ElevageDomain.isSleeping(
            individual, 210 * minute.inMilliseconds, config),
        isTrue);
    expect(ElevageConfig.fromJson(config.toJson()).mineralDaySleepMinutes, 150);
  });

  test('cooldown de câlin ne modifie ni faim ni structure durablement', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final before = (state.data['individuals'] as Map)[id] as Map;
    final structural =
        ((before['care'] as Map)['structuralIntake'] as Map)['total'];
    state = ElevageDomain.cuddle(state, id, now, defaultElevageConfig,
        durationMs: 5000);
    state = ElevageDomain.cuddle(state, id, now + 1, defaultElevageConfig,
        durationMs: 5000);
    state = ElevageDomain.cuddle(state, id, now + 2, defaultElevageConfig,
        durationMs: 5000);
    final individual = (state.data['individuals'] as Map)[id] as Map;
    expect((individual['social'] as Map)['lastReaction'], 'IRRITATED');
    expect(ElevageDomain.wellbeing(individual), lessThan(60));
    expect(((individual['care'] as Map)['structuralIntake'] as Map)['total'],
        structural);
  });

  test('production locale applique 3 heures, cap 6 et récolte unitaire', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][0] = <String, dynamic>{
      'definitionId': 'CULTURE_POTAGERE',
      'productionState': <String, dynamic>{
        'lastResolvedAt': now,
        'availableByItemId': <String, int>{},
      },
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 30).inMilliseconds, defaultElevageConfig);
    final refreshedAlcove = (state.data['alcoves'] as List).first as Map;
    final stock = ((refreshedAlcove['slots'][0] as Map)['productionState']
        as Map)['availableByItemId'] as Map;
    expect(stock['ROOT'], 6);
    state = ElevageDomain.harvestLocal(
        state, 'alcove-1', 0, 'ROOT', now + 1, defaultElevageConfig);
    final harvestedAlcove = (state.data['alcoves'] as List).first as Map;
    final harvestedStock = ((harvestedAlcove['slots'][0]
        as Map)['productionState'] as Map)['availableByItemId'] as Map;
    expect(harvestedStock['ROOT'], 5);
    expect((state.data['inventory']['special'] as Map)['ROOT'], 2);
  });

  test('humidité explicite diffuse une seule fois et reste traçable', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    Map<String, int> humidity() => <String, int>{
          for (final zone in defaultElevageConfig.sceneZones)
            zone.id: ElevageDomain.zoneEnvironment(
                state, 'alcove-1', zone.id, defaultElevageConfig,
                now: now, phaseOverride: 'DAY')['humidity']!,
        };
    expect(humidity(), <String, int>{
      'ZONE_1': 2,
      'ZONE_2': 2,
      'ZONE_3': 2,
      'ZONE_4': 2,
    });
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'BASSIN',
      'zoneId': 'ZONE_2',
    };
    expect(humidity(), <String, int>{
      'ZONE_1': 3,
      'ZONE_2': 4,
      'ZONE_3': 3,
      'ZONE_4': 2,
    });
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'zoneId': 'ZONE_2',
    };
    expect(humidity(), <String, int>{
      'ZONE_1': 1,
      'ZONE_2': 0,
      'ZONE_3': 1,
      'ZONE_4': 2,
    });
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'BASSIN',
      'zoneId': 'ZONE_2',
    };
    alcove['slots'][3] = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'zoneId': 'ZONE_4',
    };
    expect(humidity(), <String, int>{
      'ZONE_1': 3,
      'ZONE_2': 4,
      'ZONE_3': 2,
      'ZONE_4': 0,
    }); // somme complète avant le clamp visuel 1–5.
    alcove['slots'][3] = null;
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'FOUR_BIO_ORGANIQUE',
      'zoneId': 'ZONE_2',
    };
    expect(humidity()['ZONE_2'], 1);
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'ABRI_MINERAL_PROFOND',
      'zoneId': 'ZONE_2',
    };
    expect(humidity()['ZONE_2'], 3);
    final diagnostics = ElevageDomain.environmentDiagnostics(
        state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
        now: now, phaseOverride: 'DAY');
    expect(diagnostics['finalHumidity'], 3);
    final reloaded = ElevageSave.fromJson(state.toJson());
    expect(
        ElevageDomain.zoneEnvironment(
            reloaded, 'alcove-1', 'ZONE_2', defaultElevageConfig,
            now: now, phaseOverride: 'DAY')['humidity'],
        3);
  });

  test(
      'température part de 2 la nuit, gagne 1 le jour et Chauffage +1 reste local',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    int scale(String zone, String phase) =>
        ElevagePresentation.environmentScale(ElevageDomain.zoneEnvironment(
            state, 'alcove-1', zone, defaultElevageConfig,
            now: now, phaseOverride: phase)['temperature']!);
    expect(scale('ZONE_2', 'NIGHT'), 2);
    expect(scale('ZONE_2', 'DAY'), 3);
    expect(scale('ZONE_1', 'DAY'), 2); // ombre forte : -1 local.
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'FOUR_BIO_ORGANIQUE',
      'zoneId': 'ZONE_2',
    };
    expect(scale('ZONE_2', 'DAY'), 4);
    expect(scale('ZONE_3', 'DAY'), 3); // magnitude +1 : aucune diffusion.
    expect(scale('ZONE_4', 'DAY'), 3); // pas de diffusion à distance 2.
  });

  test('fuite choisit la meilleure zone sûre au lieu de la zone précédente',
      () {
    final state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][0] = <String, dynamic>{
      'definitionId': 'LAMPE_SOLAIRE',
      'zoneId': 'ZONE_1',
    };
    alcove['slots'][2] = <String, dynamic>{
      'definitionId': 'TOIT_SERRE',
      'zoneId': 'ZONE_3',
    };
    alcove['slots'][3] = <String, dynamic>{
      'definitionId': 'ABRI_FIBREUX',
      'zoneId': 'ZONE_4',
    };
    expect(
        ElevageDomain.findBestSafeZone(
            state, 'alcove-1', defaultElevageConfig, now,
            phaseOverride: 'DAY', excludingZoneId: 'ZONE_3'),
        'ZONE_2');
  });

  test('préhension par stade emporte le bon objet sans déplacer de structure',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final individual =
        ((state.data['individuals'] as Map).values.single as Map);
    expect(ElevageDomain.canCarrySceneItem(individual, 'IRON'), isFalse);
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    expect(ElevageDomain.canCarrySceneItem(individual, 'IRON'), isTrue);
    expect(ElevageDomain.canCarrySceneItem(individual, 'ROOT'), isTrue);
    expect(ElevageDomain.canCarrySceneItem(individual, 'BASSIN'), isFalse);
  });

  test('fer en zone extrême est emporté, puis absorbé dans une zone sûre', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'INTERMEDIATE';
    (state.data['inventory']['special'] as Map)['IRON'] = 1;
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][2] = <String, dynamic>{
      'definitionId': 'BASSIN',
      'zoneId': 'ZONE_3',
    };
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'IRON', 'ZONE_3', now + 1, defaultElevageConfig);
    final item = ElevageDomain.sceneItems(state, 'alcove-1').single;
    final outcome = ElevageDomain.sceneItemOutcome(state, id, 'alcove-1',
        item['instanceId'] as String, now + 2, defaultElevageConfig);
    expect(outcome.behavior, 'FLEE_WITH_ITEM');
    state = ElevageDomain.relocateSceneItem(
        state,
        'alcove-1',
        item['instanceId'] as String,
        outcome.targetZoneId!,
        defaultElevageConfig);
    state = ElevageDomain.interactSceneItem(state, id, 'alcove-1',
        item['instanceId'] as String, now + 3, defaultElevageConfig);
    expect(ElevageDomain.sceneItems(state, 'alcove-1'), isEmpty);
    expect(
        ((state.data['individuals'] as Map)[id]['care']['structuralIntake']
            as Map)['total'],
        greaterThan(0));
  });

  test('baseline humidité 2/5 reste viable et les effets s’additionnent', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    int scale(String zone) =>
        ElevagePresentation.environmentScale(ElevageDomain.zoneEnvironment(
            state, 'alcove-1', zone, defaultElevageConfig,
            now: now, phaseOverride: 'DAY')['humidity']!);
    expect(scale('ZONE_2'), 2);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'ABRI_MINERAL_PROFOND',
      'zoneId': 'ZONE_2',
    };
    expect(scale('ZONE_2'), 3);
    alcove['slots'][2] = <String, dynamic>{
      'definitionId': 'BASSIN',
      'zoneId': 'ZONE_3',
    };
    expect(scale('ZONE_3'), 4);
  });

  test('communication garde Baby non verbal et apprend par concept', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    individual['onboardingAwakeLock'] = false;
    expect(
        ElevageDomain.communicationExpression(
            individual, 'CONTENT', defaultElevageConfig)['word'],
        isNull);
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    for (var index = 0; index < 5; index++) {
      state = ElevageDomain.recordCommunication(state, id, 'CONTENT');
    }
    expect(
        ElevageDomain.communicationExpression(
            (state.data['individuals'] as Map)[id] as Map,
            'CONTENT',
            defaultElevageConfig)['word'],
        'Bien');
    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'MATURE';
    expect(
        ElevageDomain.communicationExpression(
            (state.data['individuals'] as Map)[id] as Map,
            'ABSORB',
            defaultElevageConfig,
            precise: 'Fer')['word'],
        'Fer');
  });

  test('interruption réduit sans annuler selon Tempo et Initiative', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final individual =
        ((state.data['individuals'] as Map).values.single as Map);
    ((individual['personality'] as Map)['baseline'] as Map)['tempo'] = 40;
    ((individual['personality'] as Map)['baseline'] as Map)['initiative'] = 40;
    expect(
        ElevageDomain.interruptedRemainingMs(individual, 10000,
            eventType: 'NEW_ITEM'),
        4000); // Baby spontané : -6 s.
    expect(
        ElevageDomain.interruptedRemainingMs(individual, 10000,
            eventType: 'CUDDLE'),
        4000); // Baby accompagné : -6 s.
    ((individual['personality'] as Map)['baseline'] as Map)['tempo'] = 60;
    ((individual['personality'] as Map)['baseline'] as Map)['initiative'] = 60;
    expect(
        ElevageDomain.interruptedRemainingMs(individual, 10000,
            eventType: 'NEW_ITEM'),
        6000); // Baby posé : -4 s.
    expect(
        ElevageDomain.interruptedRemainingMs(individual, 10000,
            eventType: 'CUDDLE'),
        6000); // Baby autonome : -4 s.
  });

  test('réveil manuel sort du sommeil sans réveil sur simple lecture', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: 0,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    individual['onboardingAwakeLock'] = false;
    expect(
        ElevageDomain.isSleeping(individual, 0, defaultElevageConfig), isTrue);
    state = ElevageDomain.wake(state, id, 0, defaultElevageConfig);
    final woken = (state.data['individuals'] as Map)[id] as Map;
    expect(ElevageDomain.isSleeping(woken, 1, defaultElevageConfig), isFalse);
    expect((woken['sleep'] as Map)['wakeCount'], 1);
  });

  test('onomatopées Dashboard se sérialisent et restent validées', () {
    final config =
        defaultElevageConfig.copyWith(vocalizations: <String, String>{
      ...defaultElevageConfig.vocalizations,
      'CONTENT': 'Rrr !',
    });
    validateElevageConfig(config);
    final restored = ElevageConfig.fromJson(config.toJson());
    expect(restored.vocalizations['CONTENT'], 'Rrr !');
    expect(
        () => validateElevageConfig(
                config.copyWith(vocalizations: <String, String>{
              ...config.vocalizations,
              'CONTENT': '   ',
            })),
        throwsFormatException);
  });

  test('Lot 20 distingue structure, meuble et décoration', () {
    const config = defaultElevageConfig;
    expect(config.installation('BASSIN')!.category, 'STRUCTURE');
    expect(config.installation('HAMAC')!.category, 'MEUBLE');
    expect(config.installation('CRISTAL_DECORATIF')!.category, 'DECORATION');
    expect(config.installation('FORMATION_METALLIQUE')!.productive, isFalse);
    expect(
        config.installation('FORMATION_METALLIQUE')!.resonanceMaterial, 'IRON');
  });

  test('formation métallique coûte du fer et résonne sans être consommée', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'INTERMEDIATE';
    (state.data['inventory']['special'] as Map)['IRON'] = 10;
    (state.data['discoveredItemIds'] as List).add('IRON');
    final recipe = defaultElevageConfig.recipes
        .firstWhere((entry) => entry.id == 'FORMATION_METALLIQUE');
    state = ElevageDomain.craft(state, recipe, now, defaultElevageConfig);
    expect((state.data['inventory']['special'] as Map)['IRON'], 0);
    final instanceId =
        (state.data['installationInventory'] as Map).keys.single as String;
    state = ElevageDomain.place(state, 'alcove-1', 1, instanceId, now + 1);
    final before = ((state.data['individuals'] as Map)[id]['care']
        ['structuralIntake'] as Map)['total'];
    state = ElevageDomain.resonateFormation(
        state, id, 'alcove-1', instanceId, now + 2, defaultElevageConfig);
    expect(
        ((state.data['individuals'] as Map)[id]['care']['structuralIntake']
            as Map)['total'],
        before + defaultElevageConfig.resonanceGainPerUse);
    expect(
        ((state.data['alcoves'] as List).first as Map)['slots'][1], isNotNull);
  });

  test('mobilité habitat respecte les stades et garde les structures fixes',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    expect(
        ElevageDomain.canCarryHabitatItem(individual,
            defaultElevageConfig.installation('CRISTAL_DECORATIF')!),
        isFalse);
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    expect(
        ElevageDomain.canCarryHabitatItem(individual,
            defaultElevageConfig.installation('CRISTAL_DECORATIF')!),
        isTrue);
    expect(
        ElevageDomain.canCarryHabitatItem(
            individual, defaultElevageConfig.installation('HAMAC')!),
        isFalse);
    (individual['lifecycle'] as Map)['stage'] = 'MATURE';
    expect(
        ElevageDomain.canCarryHabitatItem(
            individual, defaultElevageConfig.installation('HAMAC')!),
        isTrue);
    expect(
        ElevageDomain.canCarryHabitatItem(
            individual, defaultElevageConfig.installation('BASSIN')!),
        isFalse);
  });

  test('séjour configuré et environnement restent strictement entre 0 et 5',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final individual =
        ((state.data['individuals'] as Map).values.single as Map);
    expect(
        ElevageDomain.zoneStaySeconds(
            individual, 'NEUTRAL', defaultElevageConfig),
        anyOf(25, 35));
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][0] = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'zoneId': 'ZONE_1',
    };
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'zoneId': 'ZONE_2',
    };
    final environment = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_1', defaultElevageConfig,
        now: now, phaseOverride: 'NIGHT');
    expect(
        environment.values.every((value) => value >= 0 && value <= 5), isTrue);
    expect(environment['humidity'], 0);
  });

  test('objet habitat quitte l’inventaire, se récupère et reste déplacé', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    const instanceId = 'decor-crystal-1';
    (state.data['habitatInventory'] as Map)[instanceId] = <String, dynamic>{
      'instanceId': instanceId,
      'definitionId': 'CRISTAL_DECORATIF',
    };
    state = ElevageDomain.placeHabitatItem(
        state, 'alcove-1', instanceId, 'ZONE_2', now, defaultElevageConfig);
    expect((state.data['habitatInventory'] as Map), isEmpty);
    expect(ElevageDomain.habitatItems(state, 'alcove-1').single['zoneId'],
        'ZONE_2');
    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'INTERMEDIATE';
    state = ElevageDomain.moveHabitatItem(
        state, id, 'alcove-1', instanceId, 'ZONE_3', now, defaultElevageConfig);
    expect(ElevageDomain.habitatItems(state, 'alcove-1').single['zoneId'],
        'ZONE_3');
    state = ElevageDomain.recoverHabitatItem(state, 'alcove-1', instanceId);
    expect((state.data['habitatInventory'] as Map)[instanceId], isNotNull);
  });

  test('affinité décorative est déterministe, persistée et plafonnée', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final crystal = defaultElevageConfig.installation('CRISTAL_DECORATIF')!;
    state = ElevageDomain.persistDecorPreference(state, id, crystal);
    final individual = (state.data['individuals'] as Map)[id] as Map;
    final first = Map<String, dynamic>.from(
        (individual['decorPreferences'] as Map)[crystal.id] as Map);
    state = ElevageDomain.persistDecorPreference(state, id, crystal);
    expect(
        (state.data['individuals'] as Map)[id]['decorPreferences'][crystal.id],
        first);
    final updatedIndividual = (state.data['individuals'] as Map)[id] as Map;
    (updatedIndividual['decorPreferences'] as Map)['already-liked'] =
        <String, dynamic>{'liked': true, 'group': 'CRYSTAL'};
    const secondCrystal = ElevageInstallationDefinition(
        id: 'CRISTAL_DECORATIF_2',
        label: 'Cristal de test',
        description: 'Test',
        category: 'DECORATION',
        decorCategory: 'CRYSTAL',
        light: 0,
        temperature: 0,
        humidity: 0);
    state = ElevageDomain.persistDecorPreference(state, id, secondCrystal);
    final second = ((state.data['individuals'] as Map)[id]['decorPreferences']
        ['CRISTAL_DECORATIF_2'] as Map);
    expect(second['chance'], 100);
  });

  test('un P’TIPOTE autonome réorganise rarement une décoration appréciée', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    ((individual['personality'] as Map)['baseline'] as Map)['initiative'] = 90;
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    (individual['decorPreferences'] as Map)['CRISTAL_DECORATIF'] =
        <String, dynamic>{'liked': true, 'group': 'CRYSTAL'};
    (state.data['habitatItemsByAlcoveId'] as Map)['alcove-1'] =
        <Map<String, dynamic>>[
      <String, dynamic>{
        'instanceId': 'decor-crystal-1',
        'definitionId': 'CRISTAL_DECORATIF',
        'zoneId': 'ZONE_2',
        'reorganizationCooldownUntil': 0,
      }
    ];
    final decision = ElevageDomain.nextHabitatReorganization(
        state, id, 'alcove-1', now, defaultElevageConfig,
        phaseOverride: 'DAY');
    expect(decision, isNotNull);
    expect(decision!['instanceId'], 'decor-crystal-1');
    expect(decision['targetZoneId'], isNot('ZONE_2'));
    state = ElevageDomain.moveHabitatItem(
        state,
        id,
        'alcove-1',
        decision['instanceId']!,
        decision['targetZoneId']!,
        now,
        defaultElevageConfig);
    expect(
        ElevageDomain.nextHabitatReorganization(
            state, id, 'alcove-1', now + 1, defaultElevageConfig,
            phaseOverride: 'DAY'),
        isNull);
  });

  test('le hamac est une station de repos sans production', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Faradet',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    (state.data['habitatItemsByAlcoveId'] as Map)['alcove-1'] =
        <Map<String, dynamic>>[
      <String, dynamic>{
        'instanceId': 'hamac-1',
        'definitionId': 'HAMAC',
        'zoneId': 'ZONE_1',
      }
    ];
    final before =
        ((state.data['individuals'] as Map)[id]['wellbeing'] as Map)['value'];
    state = ElevageDomain.useFurniture(
        state, id, 'alcove-1', 'hamac-1', now, defaultElevageConfig);
    final item = ElevageDomain.habitatItems(state, 'alcove-1').single;
    expect(item['lastUsedAt'], now);
    expect(item['interactionCount'], 1);
    expect((state.data['individuals'] as Map)[id]['wellbeing']['value'],
        greaterThan(before));
    expect(defaultElevageConfig.installation('HAMAC')!.productive, isFalse);
  });

  test('les composants spécifiques d’une recette sont configurables', () {
    final hamac = defaultElevageConfig.recipes
        .firstWhere((recipe) => recipe.id == 'HAMAC')
        .copyWith(special: <String, int>{'SEED': 2, 'IRON': 1});
    final config = defaultElevageConfig.copyWith(
        recipes: defaultElevageConfig.recipes
            .map((recipe) => recipe.id == 'HAMAC' ? hamac : recipe)
            .toList());
    validateElevageConfig(config);
    final restored = ElevageConfig.fromJson(config.toJson());
    expect(
        restored.recipes.firstWhere((recipe) => recipe.id == 'HAMAC').special,
        <String, int>{'SEED': 2, 'IRON': 1});
    expect(
        () => validateElevageConfig(config.copyWith(recipes: <ElevageRecipe>[
              ...config.recipes.where((recipe) => recipe.id != 'HAMAC'),
              hamac.copyWith(special: <String, int>{'UNKNOWN_ITEM': 1}),
            ])),
        throwsFormatException);
  });

  test('les effets d’habitat sont configurables par catégorie', () {
    final config = defaultElevageConfig
        .copyWith(installationEffects: <String, Map<String, int>>{
      'ABRI_FIBREUX': <String, int>{
        'light': 1,
        'temperature': -2,
        'humidity': 1,
      },
      'ABRI_MINERAL_PROFOND': <String, int>{
        'light': -2,
        'temperature': -1,
        'humidity': 0,
      },
      'HAMAC': <String, int>{'wellbeing': 3},
      'CRISTAL_DECORATIF': <String, int>{'wellbeing': 2},
    });
    validateElevageConfig(config);
    expect(config.installation('ABRI_FIBREUX')!.light, 1);
    expect(config.installation('ABRI_MINERAL_PROFOND')!.temperature, -1);
    expect(config.installation('HAMAC')!.wellbeingImpact, 3);
    expect(config.installation('CRISTAL_DECORATIF')!.wellbeingImpact, 2);
    expect(
        ElevageConfig.fromJson(config.toJson())
            .installation('HAMAC')!
            .wellbeingImpact,
        3);
    expect(
        () => validateElevageConfig(
                config.copyWith(installationEffects: <String, Map<String, int>>{
              'HAMAC': <String, int>{'humidity': 2},
            })),
        throwsFormatException);
  });

  test('les Formations ne conservent jamais de stock de production', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][0] = <String, dynamic>{
      'definitionId': 'FORMATION_METALLIQUE',
      'productionState': <String, dynamic>{
        'lastResolvedAt': now,
        'availableByItemId': <String, int>{'IRON': 6},
      },
    };
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'CULTURE_POTAGERE',
      'productionState': <String, dynamic>{
        'lastResolvedAt': now,
        'availableByItemId': <String, int>{},
      },
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 3).inMilliseconds, defaultElevageConfig);
    final slots =
        ((state.data['alcoves'] as List).first as Map)['slots'] as List;
    expect((slots[0] as Map).containsKey('productionState'), isFalse);
    expect(
        ((slots[1] as Map)['productionState'] as Map)['availableByItemId']
            ['ROOT'],
        1);
    expect(
        () => ElevageDomain.harvestLocal(
            state, 'alcove-1', 0, 'IRON', now, defaultElevageConfig),
        throwsStateError);
  });

  test('matrice écologique distingue les trois Natures de test', () {
    String comfort(String family, String nature, Map<String, int> zone) =>
        ElevageDomain.localComfort(zone, defaultElevageConfig,
            family: family, nature: nature);

    // Les trois zones centrales demandées ne racontent pas la même histoire
    // biologique selon la Nature active.
    expect(
        comfort('VEGETAL', 'PHOTOSYNTHESIS', <String, int>{
          'light': 5,
          'temperature': 3,
          'humidity': 2,
        }),
        'IDEAL');
    expect(
        comfort('MINERAL', 'RESONANCE', <String, int>{
          'light': 3,
          'temperature': 4,
          'humidity': 2,
        }),
        'IDEAL');
    expect(
        comfort('FUNGAL', 'DECOMPOSITION', <String, int>{
          'light': 1,
          'temperature': 2,
          'humidity': 4,
        }),
        'IDEAL');

    // 2/2/2 n'est plus l'optimum implicite de toutes les familles.
    expect(
        comfort('VEGETAL', 'PHOTOSYNTHESIS', <String, int>{
          'light': 2,
          'temperature': 2,
          'humidity': 2,
        }),
        'BAD');
    expect(
        comfort('MINERAL', 'RESONANCE', <String, int>{
          'light': 2,
          'temperature': 2,
          'humidity': 2,
        }),
        'NEUTRAL');
    expect(
        comfort('FUNGAL', 'DECOMPOSITION', <String, int>{
          'light': 2,
          'temperature': 2,
          'humidity': 2,
        }),
        'NEUTRAL');
  });

  test('worst axis et safe-zone utilisent le profil de Nature actif', () {
    String comfort(String family, String nature, Map<String, int> zone) =>
        ElevageDomain.localComfort(zone, defaultElevageConfig,
            family: family, nature: nature);
    expect(
        comfort('MINERAL', 'RESONANCE', <String, int>{
          'light': 3,
          'temperature': 4,
          'humidity': 5,
        }),
        'EXTREME');
    expect(
        comfort('VEGETAL', 'PHOTOSYNTHESIS', <String, int>{
          'light': 1,
          'temperature': 3,
          'humidity': 2,
        }),
        'BAD');
    expect(
        comfort('VEGETAL', 'PHOTOSYNTHESIS', <String, int>{
          'light': 5,
          'temperature': 5,
          'humidity': 2,
        }),
        'EXTREME');
    expect(
        comfort('FUNGAL', 'DECOMPOSITION', <String, int>{
          'light': 5,
          'temperature': 2,
          'humidity': 4,
        }),
        'EXTREME');
    expect(
        comfort('FUNGAL', 'DECOMPOSITION', <String, int>{
          'light': 1,
          'temperature': 5,
          'humidity': 4,
        }),
        'EXTREME');

    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Chloro',
        physical: false,
        family: 'VEGETAL',
        nature: 'PHOTOSYNTHESIS',
        now: now,
        config: defaultElevageConfig);
    final individual =
        ((state.data['individuals'] as Map).values.single as Map);
    expect(individual['family'], 'VEGETAL');
    expect(individual['nature'], 'PHOTOSYNTHESIS');
    expect(defaultElevageConfig.profileForIndividual(individual).preferredLight,
        5);

    const zones = <String, Map<String, int>>{
      'A': <String, int>{'light': 5, 'temperature': 3, 'humidity': 2},
      'B': <String, int>{'light': 3, 'temperature': 4, 'humidity': 2},
      'C': <String, int>{'light': 1, 'temperature': 2, 'humidity': 4},
    };
    expect(
        ElevageDomain.bestZoneFromEnvironment(zones, defaultElevageConfig,
            family: 'VEGETAL', nature: 'PHOTOSYNTHESIS'),
        'A');
    expect(
        ElevageDomain.bestZoneFromEnvironment(zones, defaultElevageConfig,
            family: 'MINERAL', nature: 'RESONANCE'),
        'B');
    expect(
        ElevageDomain.bestZoneFromEnvironment(zones, defaultElevageConfig,
            family: 'FUNGAL', nature: 'DECOMPOSITION'),
        'C');

    final photo = defaultElevageConfig
        .natureProfile('VEGETAL', 'PHOTOSYNTHESIS')
        .copyWith(preferredLight: 4);
    final configured = defaultElevageConfig.copyWith(
        natureProfiles: defaultElevageConfig.natureProfiles
            .map((entry) => entry.id == photo.id ? photo : entry)
            .toList());
    validateElevageConfig(configured);
    expect(
        ElevageConfig.fromJson(configured.toJson())
            .natureProfile('VEGETAL', 'PHOTOSYNTHESIS')
            .preferredLight,
        4);
  });

  test('producteurs biologiques suivent leurs sorties Dashboard indépendantes',
      () {
    final configured = defaultElevageConfig
        .copyWith(producerOutputs: <String, List<ElevageProductionOutput>>{
      ...defaultElevageConfig.producerOutputs,
      'CULTURE_POTAGERE': const <ElevageProductionOutput>[
        ElevageProductionOutput(
            resourceId: 'ROOT',
            quantityPerCycle: 2,
            productionSeconds: 10,
            maxLocalStock: 3),
        ElevageProductionOutput(
            resourceId: 'LEAF',
            quantityPerCycle: 1,
            productionSeconds: 20,
            maxLocalStock: 4),
      ],
    });
    validateElevageConfig(configured);
    var state = ElevageSave.initial(configured, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    (alcove['slots'] as List)[0] = <String, dynamic>{
      'instanceId': 'culture-test',
      'definitionId': 'CULTURE_POTAGERE',
      'productionState': <String, dynamic>{
        'lastResolvedAt': now,
        'lastResolvedAtByItemId': <String, int>{'ROOT': now, 'LEAF': now},
        'availableByItemId': <String, int>{},
      },
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(seconds: 20).inMilliseconds, configured);
    final refreshedAlcove = (state.data['alcoves'] as List).first as Map;
    final stock = (((refreshedAlcove['slots'] as List).first
        as Map)['productionState'] as Map)['availableByItemId'] as Map;
    expect(stock['ROOT'], 3,
        reason: 'cap par sortie appliqué après deux cycles');
    expect(stock['LEAF'], 1, reason: 'horloge LEAF indépendante');
    final restored = ElevageConfig.fromJson(configured.toJson());
    expect(restored.outputsFor('CULTURE_POTAGERE').first.quantityPerCycle, 2);
  });

  test('résonance végétale et fongique conserve la structure cible', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Mycel',
        physical: false,
        family: 'FUNGAL',
        nature: 'DECOMPOSITION',
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    final slots =
        ((state.data['alcoves'] as List).first as Map)['slots'] as List;
    slots[0] = <String, dynamic>{
      'instanceId': 'mycelium',
      'definitionId': 'COLONIE_MYCELIENNE',
    };
    state = ElevageDomain.resonateFormation(
        state, id, 'alcove-1', 'mycelium', now + 1, defaultElevageConfig);
    final structure = ((state.data['individuals'] as Map)[id]['care']
        ['structuralIntake'] as Map);
    expect(structure['total'], 1);
    expect((structure['byMaterial'] as Map)['FUNGAL_RESONANCE'], 1);
    expect((slots[0] as Map)['definitionId'], 'COLONIE_MYCELIENNE');
  });

  test(
      'onboarding garde une nouvelle adoption éveillée puis Baby explore localement',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Hawl',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    expect(individual['onboardingAwakeLock'], isTrue);
    expect(ElevageDomain.isSleeping(individual, now, defaultElevageConfig),
        isFalse);
    final target = ElevageDomain.exploratoryZoneTarget(
        state, 'alcove-1', 'ZONE_1', individual, defaultElevageConfig, now);
    expect(target, 'ZONE_2', reason: 'Baby n’obtient pas un GPS vers Z4');
    final signal = ElevageDomain.environmentalSignal(
        <String, int>{'light': 3, 'temperature': 3, 'humidity': 2},
        individual,
        defaultElevageConfig);
    expect(signal?['icon'], 'DISCOMFORT');
    expect(signal?['vocalization'], 'Nnh…');
  });

  test('une adoption nocturne reste éveillée jusqu’à la nuit suivante', () {
    final cycle = defaultElevageConfig.dayNightCycleHours *
        const Duration(hours: 1).inMilliseconds;
    final day = defaultElevageConfig.dayDurationHours *
        const Duration(hours: 1).inMilliseconds;
    final adoptedAt = day + 1;
    var state = ElevageSave.initial(defaultElevageConfig, now: adoptedAt);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Veille',
        physical: false,
        now: adoptedAt,
        config: defaultElevageConfig);
    final individual =
        ((state.data['individuals'] as Map).values.single as Map);
    expect(individual['onboardingSleepAllowedAt'], cycle + day);
    expect(
        ElevageDomain.isSleeping(individual, cycle + 1, defaultElevageConfig),
        isFalse);
  });

  test('migration Réserve V21 agrège les inventaires historiques une fois', () {
    final legacy = ElevageSave.initial(defaultElevageConfig, now: now).toJson();
    legacy['sharedReserveMigrationV21'] = false;
    final alcoves = legacy['alcoves'] as List;
    (alcoves[0] as Map)['inventory'] = <String, dynamic>{
      'generic': <String, int>{'organic': 1},
      'special': <String, int>{'FRUIT': 2},
    };
    (alcoves[1] as Map)['inventory'] = <String, dynamic>{
      'generic': <String, int>{'mineral': 4},
      'special': <String, int>{'FRUIT': 3},
    };
    final migrated = ElevageSave.fromJson(legacy);
    final inventory = migrated.data['inventory'] as Map;
    expect((inventory['special'] as Map)['FRUIT'], 5);
    expect((inventory['generic'] as Map)['organic'], 1);
    expect((inventory['generic'] as Map)['mineral'], 4);
    final reloaded = ElevageSave.fromJson(migrated.toJson());
    expect(((reloaded.data['inventory'] as Map)['special'] as Map)['FRUIT'], 5);
    expect(
        (reloaded.data['alcoves'] as List)
            .every((alcove) => !(alcove as Map).containsKey('inventory')),
        isTrue);
  });

  test('Recycleur V1 échange des ressources spécifiques sans duplication', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final special = state.data['inventory']['special'] as Map;
    special['FRUIT'] = 2;
    special['QUARTZ'] = 3;
    state = ElevageDomain.recycle(state, 'FRUIT', 2, defaultElevageConfig);
    state = ElevageDomain.recycle(state, 'QUARTZ', 3, defaultElevageConfig);
    final inventory = state.data['inventory'] as Map;
    expect((inventory['special'] as Map)['FRUIT'], 0);
    expect((inventory['special'] as Map)['QUARTZ'], 0);
    expect((inventory['generic'] as Map)['organic'], 2);
    expect((inventory['generic'] as Map)['mineral'], 3);
    expect(defaultElevageConfig.recycleRule('ORGANIC'), isNull);
    expect(
        ElevageConfig.fromJson(defaultElevageConfig.toJson())
            .recycleRule('QUARTZ')
            ?.recycleOutputType,
        'MINERAL');
    expect(
        () => ElevageDomain.recycle(state, 'ORGANIC', 1, defaultElevageConfig),
        throwsStateError);
  });

  test(
      'placement utilise la Réserve et refuse clairement les objets non posables',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final special = state.data['inventory']['special'] as Map;
    special['FRUIT'] = 2;
    special['SEED'] = 1;
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'FRUIT', 'ZONE_2', now, defaultElevageConfig);
    expect((state.data['inventory']['special'] as Map)['FRUIT'], 1);
    final placed = ElevageDomain.sceneItems(state, 'alcove-1');
    expect(placed, hasLength(1));
    expect(placed.single['itemId'], 'FRUIT');
    expect(placed.single['placedItemInstanceId'], placed.single['instanceId']);
    expect(ElevageDomain.placeableSceneItems.contains('SEED'), isTrue);
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'SEED', 'ZONE_3', now + 1, defaultElevageConfig);
    expect(ElevageDomain.sceneItems(state, 'alcove-1'), hasLength(2));
  });

  test('migration Algues fusionne le fragment legacy une seule fois', () {
    final legacy = ElevageSave.initial(defaultElevageConfig, now: now).toJson();
    final special = legacy['inventory']['special'] as Map;
    special['ALGAE'] = 2;
    special['ALGAE_FRAGMENT'] = 5;
    (legacy['individuals'] as Map)['legacy'] = <String, dynamic>{
      'generatedProfile': <String, dynamic>{'foodPreference': 'ALGAE_FRAGMENT'},
    };
    final migrated = ElevageSave.fromJson(legacy);
    expect((migrated.data['inventory']['special'] as Map)['ALGAE'], 7);
    expect(
        (migrated.data['inventory']['special'] as Map)
            .containsKey('ALGAE_FRAGMENT'),
        isFalse);
    expect(
        ((migrated.data['individuals'] as Map)['legacy']['generatedProfile']
            ['foodPreference']),
        'ALGAE');
    final reloaded = ElevageSave.fromJson(migrated.toJson());
    expect((reloaded.data['inventory']['special'] as Map)['ALGAE'], 7);
  });

  test('énergie ne convertit plus la Réserve sans source locale', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final generic = state.data['inventory']['generic'] as Map;
    generic['organic'] = 4;
    generic['mineral'] = 2;
    generic['energy'] = 0;
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][0] = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'zoneId': 'ZONE_1',
      'maintenanceState': <String, dynamic>{
        'status': 'ACTIVE',
        'lastResolvedAt': now,
      },
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 4).inMilliseconds, defaultElevageConfig);
    final after = state.data['inventory']['generic'] as Map;
    expect(after['organic'], 4);
    expect(after['mineral'], 2);
    expect(after['energy'], 0);
    final refreshed =
        ((state.data['alcoves'] as List).first as Map)['slots'][0] as Map;
    expect(refreshed['maintenanceState']['status'], 'INACTIVE_NO_RESOURCE');
  });

  test('structure ENERGY en pause ne crée ni énergie ni stock négatif', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final generic = state.data['inventory']['generic'] as Map;
    generic['organic'] = 1;
    generic['mineral'] = 0;
    generic['energy'] = 0;
    final alcove = (state.data['alcoves'] as List).first as Map;
    final installation = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'zoneId': 'ZONE_2',
      'maintenanceState': <String, dynamic>{
        'status': 'ACTIVE',
        'lastResolvedAt': now,
      },
    };
    alcove['slots'][1] = installation;
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 2).inMilliseconds, defaultElevageConfig);
    expect((state.data['inventory']['generic'] as Map)['energy'], 0);
    expect((state.data['inventory']['generic'] as Map)['organic'], 1);
    final refreshedInstallation =
        ((state.data['alcoves'] as List).first as Map)['slots'][1] as Map;
    expect(refreshedInstallation['maintenanceState']['status'],
        'INACTIVE_NO_RESOURCE');
  });

  test('Chauffage consomme l’Énergie locale, s’arrête et redémarre', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final generic = state.data['inventory']['generic'] as Map;
    generic['organic'] = 1;
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['localEnergy'] = 1;
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'FOUR_BIO_ORGANIQUE',
      'zoneId': 'ZONE_2',
      'maintenanceState': <String, dynamic>{
        'status': 'ACTIVE',
        'lastResolvedAt': now,
      },
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 1).inMilliseconds, defaultElevageConfig);
    expect((state.data['inventory']['generic'] as Map)['organic'], 1);
    expect(((state.data['alcoves'] as List).first as Map)['localEnergy'], 0);
    expect(
        ElevageDomain.zoneEnvironment(
            state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
            now: now, phaseOverride: 'NIGHT')['temperature'],
        3);
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 2).inMilliseconds, defaultElevageConfig);
    expect(
        ElevageDomain.zoneEnvironment(
            state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
            now: now, phaseOverride: 'NIGHT')['temperature'],
        2);
    ((state.data['alcoves'] as List).first as Map)['localEnergy'] = 1;
    state = ElevageDomain.refreshAlcove(
        state,
        'alcove-1',
        now + const Duration(hours: 2).inMilliseconds + 1,
        defaultElevageConfig);
    expect(
        ElevageDomain.zoneEnvironment(
            state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
            now: now, phaseOverride: 'NIGHT')['temperature'],
        3);
  });

  test('migration Trou géothermique conserve l’installation en Four', () {
    final legacy = ElevageSave.initial(defaultElevageConfig, now: now).toJson();
    final alcove = (legacy['alcoves'] as List).first as Map;
    alcove['slots'][1] = <String, dynamic>{
      'instanceId': 'legacy-hole',
      'definitionId': 'TROU_GEOTHERMIQUE_CHAUD',
      'zoneId': 'ZONE_2',
    };
    final migrated = ElevageSave.fromJson(legacy);
    final installed =
        ((migrated.data['alcoves'] as List).first as Map)['slots'][1] as Map;
    expect(installed['instanceId'], 'legacy-hole');
    expect(installed['definitionId'], 'FOUR_BIO_ORGANIQUE');
  });

  test('structures legacy reçoivent des slots modules vides sans changer effet',
      () {
    final legacy = ElevageSave.initial(defaultElevageConfig, now: now).toJson();
    final alcove = (legacy['alcoves'] as List).first as Map;
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'FOUR_BIO_ORGANIQUE',
      'zoneId': 'ZONE_2',
    };
    final migrated = ElevageSave.fromJson(legacy);
    final installed =
        ((migrated.data['alcoves'] as List).first as Map)['slots'][1] as Map;
    expect(installed['installedModules'], isEmpty);
    expect(
        ElevageDomain.zoneEnvironment(
            migrated, 'alcove-1', 'ZONE_2', defaultElevageConfig,
            now: now, phaseOverride: 'NIGHT')['temperature'],
        3);
  });

  test('POWER augmente Four et Ventilation, EFFICIENCY allonge le coût réel',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'FOUR_BIO_ORGANIQUE',
      'zoneId': 'ZONE_2',
      'installedModules': <dynamic>[
        <String, dynamic>{
          'instanceId': 'power-one',
          'moduleId': 'MODULE_POWER_BASIC'
        }
      ],
    };
    expect(
        ElevageDomain.zoneEnvironment(
            state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
            now: now, phaseOverride: 'NIGHT')['temperature'],
        4);
    expect(
        ElevageDomain.zoneEnvironment(
            state, 'alcove-1', 'ZONE_1', defaultElevageConfig,
            now: now, phaseOverride: 'NIGHT')['temperature'],
        2,
        reason:
            'POWER porte le chauffage à +2 local et diffuse +1 au-dessus de la base propre à Z1');
    alcove['slots'][1] = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'zoneId': 'ZONE_2',
      'installedModules': <dynamic>[
        <String, dynamic>{
          'instanceId': 'power-two',
          'moduleId': 'MODULE_POWER_BASIC'
        }
      ],
    };
    expect(
        ElevageDomain.zoneEnvironment(
            state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
            now: now, phaseOverride: 'DAY')['humidity'],
        0);
    final generic = state.data['inventory']['generic'] as Map;
    generic['energy'] = 0;
    generic['organic'] = 2;
    generic['mineral'] = 1;
    alcove['slots'][1]['installedModules'] = <dynamic>[
      <String, dynamic>{
        'instanceId': 'efficient',
        'moduleId': 'MODULE_EFFICIENCY_BASIC'
      }
    ];
    alcove['slots'][1]['maintenanceState'] = <String, dynamic>{
      'status': 'ACTIVE',
      'lastResolvedAt': now,
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 2).inMilliseconds, defaultElevageConfig);
    // 2 h is shorter than the 2 h 30 efficiency interval: no conversion.
    expect((state.data['inventory']['generic'] as Map)['energy'], 0);
  });

  test('CAPACITY augmente le cap Culture puis le retrait revient au cap base',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][0] = <String, dynamic>{
      'definitionId': 'CULTURE_POTAGERE',
      'zoneId': 'ZONE_1',
      'installedModules': <dynamic>[
        <String, dynamic>{
          'instanceId': 'capacity',
          'moduleId': 'MODULE_CAPACITY_BASIC'
        }
      ],
      'productionState': <String, dynamic>{
        'lastResolvedAt': now,
        'availableByItemId': <String, int>{},
      },
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 30).inMilliseconds, defaultElevageConfig);
    final culture =
        ((state.data['alcoves'] as List).first as Map)['slots'][0] as Map;
    expect((culture['productionState']['availableByItemId'] as Map)['ROOT'], 9);
    culture['installedModules'] = <dynamic>[];
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 33).inMilliseconds, defaultElevageConfig);
    final afterRemoval =
        ((state.data['alcoves'] as List).first as Map)['slots'][0] as Map;
    expect(
        (afterRemoval['productionState']['availableByItemId'] as Map)['ROOT'],
        9);
  });

  test('installation module respecte stacking, incompatibilité et persistance',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][1] = <String, dynamic>{
      'instanceId': 'vent',
      'definitionId': 'VENTILATION',
      'zoneId': 'ZONE_2'
    };
    final modules = state.data['moduleInventory'] as Map;
    for (final id in <String>['one', 'two', 'three']) {
      modules[id] = <String, dynamic>{
        'instanceId': id,
        'moduleId': 'MODULE_POWER_BASIC'
      };
    }
    state = ElevageDomain.installModule(
        state, 'alcove-1', 1, 'one', defaultElevageConfig);
    state = ElevageDomain.installModule(
        state, 'alcove-1', 1, 'two', defaultElevageConfig);
    expect(
        () => ElevageDomain.installModule(
            state, 'alcove-1', 1, 'three', defaultElevageConfig),
        throwsStateError);
    final reloaded = ElevageSave.fromJson(state.toJson());
    final installed =
        ((reloaded.data['alcoves'] as List).first as Map)['slots'][1] as Map;
    expect((installed['installedModules'] as List), hasLength(2));
  });

  test('Refuge démarre avec une seule Alcôve prête et Contribution cumulée',
      () {
    final target = defaultElevageConfig.copyWith(
        devMode: false, preset: ElevagePreset.target);
    var state = ElevageSave.initial(target, now: now);
    final alcoves = state.data['alcoves'] as List;
    expect((alcoves.first as Map)['progressState'], 'READY');
    expect((alcoves[1] as Map)['progressState'], 'LOCKED');
    state = ElevageDomain.addContribution(state, 10);
    expect(ElevageDomain.contribution(state), 10);
    expect(ElevageDomain.alcoveProgressState(state, 'alcove-2', target, now),
        'AVAILABLE_TO_BUILD');
  });

  test('migration Contribution vers Confiance conserve la progression', () {
    final raw = ElevageSave.initial(defaultElevageConfig, now: now).toJson();
    final progress = raw['refugeProgress'] as Map;
    progress
      ..remove('trust')
      ..remove('trustHistory')
      ..remove('trustEventIds')
      ..remove('trustMigrationV224')
      ..['contribution'] = 184;
    final migrated = ElevageSave.fromJson(raw);
    expect(ElevageDomain.trust(migrated), 184);
    expect(ElevageDomain.contribution(migrated), 184);
    expect(
        (migrated.data['refugeProgress'] as Map)['trustMigrationV224'], isTrue);
  });

  test('Confiance crédite adoption puis connaissance une seule fois', () {
    final progression =
        Map<String, dynamic>.from(defaultElevageConfig.refugeProgression);
    progression['knowledge'] = <String, dynamic>{
      'observationsForHypothesis': 1,
      'evidenceForConfirmation': 1,
    };
    final config =
        defaultElevageConfig.copyWith(refugeProgression: progression);
    var state = ElevageSave.initial(config, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Hawl',
        physical: false,
        now: now,
        config: config);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    expect(ElevageDomain.trust(state), 10);
    state = ElevageDomain.recordKnowledgeObservation(
        state, id, 'IRON_AFFINITY', now + 1, config);
    state = ElevageDomain.refreshRefugeProgress(state, now + 1, config);
    expect(ElevageDomain.trust(state), 13); // Observation + Hypothèse.
    state = ElevageDomain.recordKnowledgeObservation(
        state, id, 'IRON_AFFINITY', now + 2, config);
    state = ElevageDomain.refreshRefugeProgress(state, now + 2, config);
    expect(ElevageDomain.trust(state), 19); // Observation + Découverte.
    state = ElevageDomain.refreshRefugeProgress(state, now + 3, config);
    expect(ElevageDomain.trust(state), 19);
    expect(
        ElevageDomain.trustHistory(state)
            .where((entry) => entry['reasonType'] == 'HYPOTHESIS'),
        hasLength(1));
  });

  test('Confiance pénalise chaque P’TIPOTE critique par tranches de 24h', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Hawl',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    state = ElevageDomain.setTrust(state, 100, now: now);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    ((state.data['individuals'] as Map)[id]['wellbeing'] as Map)['value'] = 19;
    state =
        ElevageDomain.refreshRefugeProgress(state, now, defaultElevageConfig);
    state = ElevageDomain.refreshRefugeProgress(state,
        now + const Duration(hours: 49).inMilliseconds, defaultElevageConfig);
    expect(ElevageDomain.trust(state), 80);
    state = ElevageDomain.refreshRefugeProgress(state,
        now + const Duration(hours: 49).inMilliseconds, defaultElevageConfig);
    expect(ElevageDomain.trust(state), 80);
    ((state.data['individuals'] as Map)[id]['wellbeing'] as Map)['value'] = 21;
    state = ElevageDomain.refreshRefugeProgress(state,
        now + const Duration(hours: 50).inMilliseconds, defaultElevageConfig);
    expect(ElevageDomain.trust(state), 80);
  });

  test('évolution Juvénile crédite la Confiance une seule fois', () {
    final progression =
        Map<String, dynamic>.from(defaultElevageConfig.refugeProgression);
    progression['maturation'] = <String, dynamic>{
      'observationRequirement': 0,
      'hypothesisRequirement': 0,
      'confirmationRequirement': 0,
    };
    final config =
        defaultElevageConfig.copyWith(refugeProgression: progression);
    var state = ElevageSave.initial(config, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Hawl',
        physical: false,
        now: now,
        config: config);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final evolvedAt = now + const Duration(hours: 25).inMilliseconds;
    state = ElevageDomain.metamorphose(state, id, evolvedAt, config);
    expect(ElevageDomain.trust(state), 60);
    final reloaded = ElevageSave.fromJson(state.toJson());
    expect(
        ElevageDomain.trustHistory(reloaded)
            .where((entry) => entry['reasonType'] == 'INTERMEDIATE_EVOLUTION'),
        hasLength(1));
  });

  test('Confiance applique le malus critique séparément à deux P’TIPOTES', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    for (final entry in <(String, String)>[
      ('alcove-1', 'Hawl'),
      ('alcove-2', 'Noma'),
    ]) {
      state = ElevageDomain.adopt(
          source: state,
          alcoveId: entry.$1,
          name: entry.$2,
          physical: false,
          now: now,
          config: defaultElevageConfig);
    }
    state = ElevageDomain.setTrust(state, 100, now: now);
    for (final id in state.data['activeIndividualIds'] as List) {
      (((state.data['individuals'] as Map)[id] as Map)['wellbeing']
          as Map)['value'] = 19;
    }
    state =
        ElevageDomain.refreshRefugeProgress(state, now, defaultElevageConfig);
    state = ElevageDomain.refreshRefugeProgress(state,
        now + const Duration(hours: 24).inMilliseconds, defaultElevageConfig);
    expect(ElevageDomain.trust(state), 80);
  });

  test(
      'Cuisine V1 répartit la satiété sèche et humide sans perdre la composition',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Hawl',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.addDevInventory(state);
    state = ElevageDomain.cookMeal(
        state,
        const <String>['ROOT', 'LEAF', 'MOSS'],
        false,
        now,
        defaultElevageConfig);
    final dry = ElevageDomain.cookedMeals(state).single;
    expect(dry['portionCount'], 3);
    expect(dry['batchSatiety'], 70);
    expect(dry['ingredientIds'], const <String>['ROOT', 'LEAF', 'MOSS']);
    state = ElevageDomain.setIndividualSatiety(state, id, 0, now);
    state = ElevageDomain.offerCookedMeal(
        state, id, dry['instanceId'] as String, now + 1, defaultElevageConfig);
    expect(
        ElevageDomain.satietyPercent(state, id, now + 1, defaultElevageConfig),
        24);
    state.data['waterTank'] = 5.0;
    state = ElevageDomain.cookMeal(
        state,
        const <String>['ROOT', 'LEAF', 'MOSS'],
        true,
        now + 2,
        defaultElevageConfig);
    final wet = ElevageDomain.cookedMeals(state).last;
    expect(wet['portionCount'], 4);
    expect(wet['batchSatiety'], 60);
    expect(ElevageDomain.waterTank(state), 4);
  });

  test('météo déterministe remplit l’eau et utilise la nuit locale 00–04', () {
    final progression =
        Map<String, dynamic>.from(defaultElevageConfig.refugeProgression);
    progression['weather'] = <String, dynamic>{
      'weatherBlockHours': 4,
      'weatherClearWeight': 0,
      'weatherLightRainWeight': 0,
      'weatherHeavyRainWeight': 1,
      'lightRainDurationHours': 2,
      'heavyRainDurationHours': 4,
      'lightRainLightDelta': -1,
      'lightRainTemperatureDelta': 0,
      'heavyRainLightDelta': -1,
      'heavyRainTemperatureDelta': -1,
      'rainWaterPerHour': 5,
      'nightStartHour': 0,
      'nightEndHour': 4,
    };
    final config =
        defaultElevageConfig.copyWith(refugeProgression: progression);
    final start = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    var state = ElevageSave.initial(config, now: start);
    (state.data['weather'] as Map)['lastUpdatedAt'] = start;
    state = ElevageDomain.refreshWeather(
        state, start + const Duration(hours: 4).inMilliseconds, config);
    expect(ElevageDomain.waterTank(state), 20);
    expect(ElevageDomain.weatherTypeAt(start + 1, config), 'HEAVY_RAIN');
    expect(ElevageDomain.weatherEffectsAt(start + 1, config),
        const <String, int>{'light': -1, 'temperature': -1});
    expect(
        ElevageDomain.dayNightPhase(
            DateTime(2026, 1, 1, 2).millisecondsSinceEpoch, config),
        'NIGHT');
    expect(
        ElevageDomain.dayNightPhase(
            DateTime(2026, 1, 1, 4).millisecondsSinceEpoch, config),
        'DAY');
  });

  test('petite pluie ne remplit l’eau que pendant les deux premières heures',
      () {
    final progression =
        Map<String, dynamic>.from(defaultElevageConfig.refugeProgression);
    progression['weather'] = <String, dynamic>{
      'weatherBlockHours': 4,
      'weatherClearWeight': 0,
      'weatherLightRainWeight': 1,
      'weatherHeavyRainWeight': 0,
      'lightRainDurationHours': 2,
      'heavyRainDurationHours': 4,
      'lightRainLightDelta': -1,
      'lightRainTemperatureDelta': 0,
      'heavyRainLightDelta': -1,
      'heavyRainTemperatureDelta': -1,
      'rainWaterPerHour': 5,
      'nightStartHour': 0,
      'nightEndHour': 4,
    };
    final config =
        defaultElevageConfig.copyWith(refugeProgression: progression);
    final start = DateTime(2026, 1, 1, 4).millisecondsSinceEpoch;
    var state = ElevageSave.initial(config, now: start);
    state = ElevageDomain.refreshWeather(
      state,
      start + const Duration(hours: 4).inMilliseconds,
      config,
    );

    expect(ElevageDomain.waterTank(state), 10);
    expect(ElevageDomain.weatherEffectsAt(start + 1, config),
        const <String, int>{'light': -1, 'temperature': 0});
    expect(
      ElevageDomain.weatherEffectsAt(
        start + const Duration(hours: 3).inMilliseconds,
        config,
      ),
      const <String, int>{'light': 0, 'temperature': 0},
    );
  });

  test('chantier assisté consomme moins de Bio-piles et devient prêt', () {
    final target = defaultElevageConfig.copyWith(
        devMode: false, preset: ElevagePreset.target);
    var state = ElevageSave.initial(target, now: now);
    state = ElevageDomain.setContribution(state, 10);
    final inventory = state.data['inventory'] as Map;
    inventory['bioPiles'] = 4;
    final generic = inventory['generic'] as Map;
    generic['organic'] = 10;
    generic['mineral'] = 6;
    state = ElevageDomain.startAlcoveConstruction(
        state, 'alcove-2', 'ASSISTED', now, target);
    expect(((state.data['alcoves'] as List)[1] as Map)['progressState'],
        'UNDER_CONSTRUCTION');
    state = ElevageDomain.refreshRefugeProgress(
        state, now + const Duration(hours: 1).inMilliseconds, target);
    expect(
        ((state.data['alcoves'] as List)[1] as Map)['progressState'], 'READY');
    expect(ElevageDomain.contribution(state), 10);
  });

  test('Bio-batterie de départ alimente localement la ventilation', () {
    final target = defaultElevageConfig.copyWith(
        devMode: false, preset: ElevagePreset.target);
    var state = ElevageSave.initial(target, now: now);
    final inventory = state.data['inventory'] as Map;
    final batteries = state.data['batteryInventory'] as Map;
    final batteryId = batteries.keys.first as String;
    state = ElevageDomain.insertBattery(state, 'alcove-1', batteryId, now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][0] = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'alcoveId': 'alcove-1',
      'maintenanceState': <String, dynamic>{
        'status': 'ACTIVE',
        'lastResolvedAt': now
      },
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 2).inMilliseconds, target);
    final refreshed = (state.data['alcoves'] as List).first as Map;
    expect((refreshed['batterySlot'] as Map)['currentEnergy'], 9);
    expect(inventory['generic'], isNotNull);
  });

  test('Bio-pile n’utilise plus la recette du Biogénérateur', () {
    final target = defaultElevageConfig.copyWith(
        devMode: false, preset: ElevagePreset.target);
    final state = ElevageSave.initial(target, now: now);
    expect(() => ElevageDomain.craftBioBattery(state, now, target),
        throwsStateError);
  });

  test('Batterie exportable consomme la Réserve et 100 Energy locale', () {
    final target = defaultElevageConfig.copyWith(
        devMode: false, preset: ElevagePreset.target);
    var state = ElevageSave.initial(target, now: now);
    final inventory = state.data['inventory'] as Map;
    final generic = inventory['generic'] as Map;
    generic['organic'] = 1;
    generic['mineral'] = 1;
    ((state.data['alcoves'] as List).first as Map)['localEnergy'] = 100;
    state = ElevageDomain.craftBatteryExport(state, 'alcove-1', now, target);
    final afterInventory = state.data['inventory'] as Map;
    final afterGeneric = afterInventory['generic'] as Map;
    expect(afterGeneric['organic'], 0);
    expect(afterGeneric['mineral'], 0);
    expect(((state.data['alcoves'] as List).first as Map)['localEnergy'], 0);
    expect((afterInventory['special'] as Map)['BATTERY_EXPORT'], 1);
  });

  test(
      'Sel se recycle en Minéral et aucun prélèvement magique ne remplace la pile',
      () {
    final target = defaultElevageConfig.copyWith(
        devMode: false, preset: ElevagePreset.target);
    var state = ElevageSave.initial(target, now: now);
    final special = (state.data['inventory'] as Map)['special'] as Map;
    special['SALT'] = 1;
    state = ElevageDomain.recycle(state, 'SALT', 1, target);
    expect(((state.data['inventory'] as Map)['generic'] as Map)['mineral'], 1);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['slots'][0] = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'alcoveId': 'alcove-1',
      'maintenanceState': <String, dynamic>{
        'status': 'ACTIVE',
        'lastResolvedAt': now
      },
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 2).inMilliseconds, target);
    final refreshed = (state.data['alcoves'] as List).first as Map;
    expect((refreshed['slots'][0] as Map)['maintenanceState']['status'],
        'INACTIVE_NO_RESOURCE');
  });

  test('prêt juvénile propose deux choix puis est restitué après Mature', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Prêt',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    for (final concept in <String>[
      'IRON_AFFINITY',
      'ROOT_FOOD_PREFERENCE',
      'PLAYER_CONTACT',
    ]) {
      for (var index = 0; index < 5; index++) {
        state = ElevageDomain.recordKnowledgeObservation(
            state, id, concept, now + index, defaultElevageConfig);
      }
    }
    for (var index = 0; index < 5; index++) {
      state = ElevageDomain.recordKnowledgeObservation(
          state, id, 'IRON_AFFINITY', now + 10 + index, defaultElevageConfig);
    }
    final juvenileAt = now + const Duration(hours: 25).inMilliseconds;
    state =
        ElevageDomain.metamorphose(state, id, juvenileAt, defaultElevageConfig);
    final individual = (state.data['individuals'] as Map)[id] as Map;
    expect((individual['loanOffer'] as Map)['choices'], hasLength(2));
    state = ElevageDomain.chooseJuvenileLoan(
        state, id, 'FORMATION_METALLIQUE', juvenileAt, defaultElevageConfig);
    final loanId = (((state.data['individuals'] as Map)[id] as Map)['loan']
        as Map)['instanceId'] as String;
    expect(
        (state.data['installationInventory'] as Map)[loanId]
            ['loanedFromRefuge'],
        isTrue);
    final readyForMature = (state.data['individuals'] as Map)[id] as Map;
    (readyForMature['lifecycle'] as Map)['stageEnteredAt'] =
        juvenileAt - const Duration(hours: 73).inMilliseconds;
    ((readyForMature['preferenceDiscovery'] as Map)['foodPreference']
        as Map)['status'] = 'CONFIRMED';
    final care = readyForMature['care'] as Map;
    care['metabolicMeals'] = 5;
    (care['structuralIntake'] as Map)['total'] = 6;
    care['autonomousMealCount'] = 1;
    (readyForMature['progressionEvidence'] as Map)['personalityEvents'] = 5;
    state = ElevageDomain.metamorphose(
        state, id, juvenileAt + 1, defaultElevageConfig);
    final due = ((state.data['individuals'] as Map)[id]['loan']
        as Map)['returnDueAt'] as int;
    state =
        ElevageDomain.refreshRefugeProgress(state, due, defaultElevageConfig);
    expect((state.data['installationInventory'] as Map).containsKey(loanId),
        isFalse);
  });

  test('Biogénérateur : cuves, Efficiency, Power et Capacity', () {
    final target = defaultElevageConfig.copyWith(
        devMode: false, preset: ElevagePreset.target);
    var state = ElevageSave.initial(target, now: now);
    final inventory = state.data['inventory'] as Map;
    final generic = inventory['generic'] as Map;
    generic['organic'] = 40;
    generic['mineral'] = 20;
    final generators = state.data['biogeneratorInventory'] as Map;
    generators['generator-test'] = <String, dynamic>{
      'instanceId': 'generator-test',
      'definitionId': 'BIOGENERATOR',
      'tanks': <String, int>{'organic': 0, 'mineral': 0},
      'installedModules': <dynamic>[],
    };
    state = ElevageDomain.installBiogenerator(
        state, 'alcove-1', 'generator-test', now);
    state = ElevageDomain.transferBiogeneratorFuel(
        state, 'alcove-1', 'ORGANIC', 30, target);
    state = ElevageDomain.transferBiogeneratorFuel(
        state, 'alcove-1', 'MINERAL', 10, target);
    final alcove = (state.data['alcoves'] as List).first as Map;
    final generator = alcove['biogeneratorSlot'] as Map;
    expect(ElevageDomain.biogeneratorCycleProfile(generator, target),
        <String, int>{'organic': 3, 'mineral': 2, 'energy': 10});
    final modules = state.data['moduleInventory'] as Map;
    modules['eff'] = <String, dynamic>{
      'instanceId': 'eff',
      'moduleId': 'MODULE_EFFICIENCY_BASIC'
    };
    modules['power'] = <String, dynamic>{
      'instanceId': 'power',
      'moduleId': 'MODULE_POWER_BASIC'
    };
    modules['cap'] = <String, dynamic>{
      'instanceId': 'cap',
      'moduleId': 'MODULE_CAPACITY_BASIC'
    };
    state = ElevageDomain.installBiogeneratorModule(
        state, 'alcove-1', 'eff', target);
    state = ElevageDomain.installBiogeneratorModule(
        state, 'alcove-1', 'power', target);
    state = ElevageDomain.installBiogeneratorModule(
        state, 'alcove-1', 'cap', target);
    final installed = ((state.data['alcoves'] as List).first
        as Map)['biogeneratorSlot'] as Map;
    expect(ElevageDomain.biogeneratorCycleProfile(installed, target),
        <String, int>{'organic': 2, 'mineral': 1, 'energy': 15});
    expect(ElevageDomain.biogeneratorTankCapacities(installed, target),
        <String, int>{'organic': 40, 'mineral': 20});
  });

  test('Biogénérateur alimente localement sans aspirer la Réserve', () {
    final target = defaultElevageConfig.copyWith(
        devMode: false, preset: ElevagePreset.target);
    var state = ElevageSave.initial(target, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['biogeneratorSlot'] = <String, dynamic>{
      'instanceId': 'generator',
      'definitionId': 'BIOGENERATOR',
      'tanks': <String, int>{'organic': 3, 'mineral': 2},
      'installedModules': <dynamic>[],
    };
    alcove['slots'][0] = <String, dynamic>{
      'definitionId': 'VENTILATION',
      'alcoveId': 'alcove-1',
      'maintenanceState': <String, dynamic>{
        'status': 'ACTIVE',
        'lastResolvedAt': now,
      },
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(hours: 2).inMilliseconds, target);
    final refreshed = (state.data['alcoves'] as List).first as Map;
    expect(refreshed['localEnergy'], 9);
    expect(
        ((refreshed['biogeneratorSlot'] as Map)['tanks'] as Map)['organic'], 0);
    expect(
        ((refreshed['biogeneratorSlot'] as Map)['tanks'] as Map)['mineral'], 0);
  });

  test('inconfort ambiant Baby persiste sans objet et cesse au retour optimal',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Hawl',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    expect(
        ElevageDomain.ambientEnvironmentalFeedback(
            <String, int>{'light': 3, 'temperature': 1, 'humidity': 2},
            individual,
            defaultElevageConfig)!['body'],
        'SHIVER');
    expect(
        ElevageDomain.ambientEnvironmentalFeedback(
            <String, int>{'light': 3, 'temperature': 4, 'humidity': 2},
            individual,
            defaultElevageConfig),
        isNull);
  });

  test('besoin exprimé est distinct de l’inconfort corporel', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Hawl',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    const cold = <String, int>{'light': 3, 'temperature': 1, 'humidity': 2};
    expect(
        ElevageDomain.expressedEnvironmentalNeed(
            cold, individual, defaultElevageConfig),
        isNull);
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    expect(
        ElevageDomain.expressedEnvironmentalNeed(
            cold, individual, defaultElevageConfig),
        <String, String>{'need': 'HEAT', 'axis': 'temperature'});
    expect(
        ElevageDomain.environmentalNeedExpression(
            individual, 'HEAT', defaultElevageConfig),
        'Pti ! 🔥');
    individual['conceptExposures'] = <String, dynamic>{
      'HEAT': <String, int>{'total': 5, 'baby': 0},
    };
    expect(
        ElevageDomain.environmentalNeedExpression(
            individual, 'HEAT', defaultElevageConfig),
        'veux chaleur 🔥');
  });

  test('Pisteur persiste par individu et reste séparé du stade', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Trace',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.addTrackerXp(state, id, 200, defaultElevageConfig);
    final individual = (state.data['individuals'] as Map)[id] as Map;
    expect(
        ElevageDomain.trackerProfession(
            individual, defaultElevageConfig)['level'],
        2);
    expect(
        ElevageDomain.trackerCarryBonus(individual, defaultElevageConfig), 2);
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    final reloaded = ElevageSave.fromJson(state.toJson());
    final persisted = (reloaded.data['individuals'] as Map)[id] as Map;
    expect(
        ElevageDomain.trackerProfession(
            persisted, defaultElevageConfig)['level'],
        2);
    final reset =
        ElevageDomain.setTrackerXp(reloaded, id, 100, defaultElevageConfig);
    final resetIndividual = (reset.data['individuals'] as Map)[id] as Map;
    expect(
        ElevageDomain.trackerProfession(
            resetIndividual, defaultElevageConfig)['level'],
        1);
  });

  test('langage Juvénile garde le seuil 5 ou 10 selon la mémoire Bébé', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Parole',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    for (var index = 0; index < 5; index++) {
      state = ElevageDomain.recordConceptExposure(state, id, 'IRON');
    }
    expect(
        ElevageDomain.communicationExpression(
            (state.data['individuals'] as Map)[id] as Map,
            'ABSORB',
            defaultElevageConfig,
            precise: 'Fer',
            conceptId: 'IRON')['word'],
        'Fer');
    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'BABY';
    for (var index = 0; index < 5; index++) {
      state = ElevageDomain.recordConceptExposure(state, id, 'ROOT');
    }
    (state.data['individuals'] as Map)[id]['lifecycle']['stage'] =
        'INTERMEDIATE';
    expect(
        ElevageDomain.communicationExpression(
            (state.data['individuals'] as Map)[id] as Map,
            'CONTENT',
            defaultElevageConfig,
            precise: 'Racine',
            conceptId: 'ROOT')['word'],
        isNull);
    for (var index = 0; index < 5; index++) {
      state = ElevageDomain.recordConceptExposure(state, id, 'ROOT');
    }
    expect(
        ElevageDomain.communicationExpression(
            (state.data['individuals'] as Map)[id] as Map,
            'CONTENT',
            defaultElevageConfig,
            precise: 'Racine',
            conceptId: 'ROOT')['word'],
        'Racine');
  });

  test(
      'connaissance agrège par concept et bloque la maturation sans confirmation',
      () {
    final progression =
        Map<String, dynamic>.from(defaultElevageConfig.refugeProgression);
    progression['knowledge'] = <String, dynamic>{
      'observationsForHypothesis': 1,
      'evidenceForConfirmation': 99,
    };
    final hypothesisOnlyConfig =
        defaultElevageConfig.copyWith(refugeProgression: progression);
    var state = ElevageSave.initial(hypothesisOnlyConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Savoir',
        physical: false,
        now: now,
        config: hypothesisOnlyConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    (individual['lifecycle'] as Map)['stageEnteredAt'] =
        now - const Duration(hours: 25).inMilliseconds;
    for (final concept in <String>[
      'IRON_AFFINITY',
      'ROOT_FOOD_PREFERENCE',
      'PLAYER_CONTACT',
    ]) {
      state = ElevageDomain.recordKnowledgeObservation(
          state, id, concept, now, hypothesisOnlyConfig);
    }
    state = ElevageDomain.recordKnowledgeObservation(
        state, id, 'IRON_AFFINITY', now + 1, hypothesisOnlyConfig);
    final knowledge = ElevageDomain.knowledgeEntries(
        (state.data['individuals'] as Map)[id] as Map);
    expect(knowledge.where((entry) => entry['conceptId'] == 'IRON_AFFINITY'),
        hasLength(1));
    expect(
        ElevageDomain.metamorphosisAvailable(
            state, id, now, hypothesisOnlyConfig),
        isFalse);
    final confirmationProgression =
        Map<String, dynamic>.from(hypothesisOnlyConfig.refugeProgression);
    confirmationProgression['knowledge'] = <String, dynamic>{
      'observationsForHypothesis': 1,
      'evidenceForConfirmation': 1,
    };
    final confirmationConfig = hypothesisOnlyConfig.copyWith(
        refugeProgression: confirmationProgression);
    state = ElevageDomain.recordKnowledgeObservation(
        state, id, 'IRON_AFFINITY', now + 2, confirmationConfig);
    expect(
        ElevageDomain.metamorphosisAvailable(
            state, id, now, confirmationConfig),
        isTrue);
  });

  test('Tam Tam évalue les taps sur les mêmes beats que son animation', () {
    const config = defaultElevageConfig;
    expect(ElevageDomain.tamTamTapGrade(20, 0, config), 'MISS');
    final grades = <String>[
      for (var beat = 0; beat < config.tamTamTotalBeats; beat++)
        ElevageDomain.tamTamTapGrade(
            ElevageDomain.tamTamBeatTargetMs(beat, config), beat, config),
    ];
    expect(ElevageDomain.tamTamSucceeded(grades, config), isTrue);
    expect(
        ElevageDomain.tamTamSucceeded(
            const <String>['MISS', 'MISS', 'MISS'], config),
        isFalse);
  });

  test('pools alimentaires par Type et stade gardent les goûts inconnus', () {
    Map<String, dynamic> individual(String family, String stage) =>
        <String, dynamic>{
          'family': family,
          'lifecycle': <String, dynamic>{'stage': stage},
        };

    final vegetal = individual('VEGETAL', 'BABY');
    expect(ElevageDomain.canEat(vegetal, 'LEAF', defaultElevageConfig), isTrue);
    expect(
        ElevageDomain.canEat(vegetal, 'ALGAE', defaultElevageConfig), isFalse);
    expect(ElevageDomain.canEat(vegetal, 'FIBROUS_FRUIT', defaultElevageConfig),
        isTrue);
    vegetal['lifecycle']['stage'] = 'INTERMEDIATE';
    expect(
        ElevageDomain.canEat(vegetal, 'ALGAE', defaultElevageConfig), isTrue);
    expect(ElevageDomain.canEat(vegetal, 'LIMESTONE', defaultElevageConfig),
        isTrue);

    final fungal = individual('FUNGAL', 'BABY');
    expect(ElevageDomain.canEat(fungal, 'ROOT', defaultElevageConfig), isTrue);
    expect(
        ElevageDomain.canEat(fungal, 'FRUIT', defaultElevageConfig), isFalse);
    fungal['lifecycle']['stage'] = 'INTERMEDIATE';
    expect(ElevageDomain.canEat(fungal, 'FRUIT', defaultElevageConfig), isTrue);

    final mineral = individual('MINERAL', 'BABY');
    expect(ElevageDomain.canEat(mineral, 'MOSS', defaultElevageConfig), isTrue);
    expect(ElevageDomain.canEat(mineral, 'MUSHROOM', defaultElevageConfig),
        isFalse);
    mineral['lifecycle']['stage'] = 'MATURE';
    expect(
        ElevageDomain.canEat(mineral, 'FRUIT', defaultElevageConfig), isTrue);
  });

  test('Baby inspecte la matière structurelle sans l’absorber', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Silex',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    (state.data['inventory']['special'] as Map)['IRON'] = 1;
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'IRON', 'ZONE_1', now + 1, defaultElevageConfig);
    final instance = (state.data['sceneItemsByAlcoveId'] as Map)['alcove-1'][0]
        ['instanceId'] as String;
    final babyOutcome = ElevageDomain.sceneItemOutcome(
        state, id, 'alcove-1', instance, now + 2, defaultElevageConfig);
    expect(babyOutcome.behavior, 'STRUCTURAL_INTEREST');
    expect(babyOutcome.consumed, isFalse);
    expect(
        ElevageDomain.canAbsorb((state.data['individuals'] as Map)[id] as Map,
            'IRON', defaultElevageConfig),
        isFalse);

    ((state.data['individuals'] as Map)[id]['lifecycle'] as Map)['stage'] =
        'INTERMEDIATE';
    expect(
        ElevageDomain.canAbsorb((state.data['individuals'] as Map)[id] as Map,
            'IRON', defaultElevageConfig),
        isTrue);
    (state.data['inventory']['special'] as Map)['IRON'] = 1;
    state = ElevageDomain.offerStructural(
        state, id, 'IRON', now + 3, defaultElevageConfig);
    expect(
        ((state.data['individuals'] as Map)[id]['care']['structuralIntake']
            as Map)['total'],
        2);
  });

  test(
      'nids transforment seulement l’environnement ressenti et Capacity le cap',
      () {
    const raw = <String, int>{'light': 4, 'temperature': 2, 'humidity': 2};
    final thermal = ElevageDomain.experiencedEnvironment(
        raw, defaultElevageConfig.installation('THERMAL_NEST'));
    final shaded = ElevageDomain.experiencedEnvironment(
        raw, defaultElevageConfig.installation('SHADED_NEST'));
    final hygroscopic = ElevageDomain.experiencedEnvironment(
        raw, defaultElevageConfig.installation('HYGROSCOPIC_NEST'));
    expect(raw, <String, int>{'light': 4, 'temperature': 2, 'humidity': 2});
    expect(thermal['temperature'], 3);
    expect(shaded['light'], 3);
    expect(hygroscopic['humidity'], 3);

    final outputs = ElevageDomain.effectiveProducerOutputs(<String, dynamic>{
      'installedModules': <Map<String, dynamic>>[
        <String, dynamic>{'moduleId': 'MODULE_CAPACITY_BASIC'},
      ],
    }, 'CULTURE_POTAGERE', defaultElevageConfig);
    expect(outputs.map((output) => output.maxLocalStock), everyElement(9));
  });

  test('Exploration initialise les neuf secteurs avec leurs stocks canoniques',
      () {
    final state = ElevageSave.initial(defaultElevageConfig, now: now);
    final sectors = ElevageDomain.explorationState(state)['sectors']
        as Map<String, dynamic>;
    final expected = <String, List<int>>{
      'FORET_HUMIDE_LISIERE': <int>[30, 30],
      'FORET_HUMIDE_SOUS_BOIS': <int>[40, 20],
      'FORET_HUMIDE_FORET_PROFONDE': <int>[50, 10],
      'LITTORAL_PLAGE': <int>[5, 30],
      'LITTORAL_DUNE': <int>[10, 40],
      'LITTORAL_CRIQUE': <int>[25, 70],
      'COLLINE_PLATEAU': <int>[20, 40],
      'COLLINE_GROTTE': <int>[20, 100],
      'COLLINE_SOMMET': <int>[30, 30],
    };
    expect(sectors, hasLength(9));
    for (final entry in expected.entries) {
      final sector = sectors[entry.key] as Map;
      expect(sector['organic'], entry.value[0]);
      expect(sector['mineral'], entry.value[1]);
      expect(sector['discovered'], isFalse);
    }
  });

  test('Exploration régénère seulement l’Organique et restaure la stamina', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.startExploration(
        state, 'FORET_HUMIDE_LISIERE', now, defaultElevageConfig);
    final exploration = ElevageDomain.explorationState(state);
    expect(exploration['stamina'], 9);
    final sector =
        (exploration['sectors'] as Map)['FORET_HUMIDE_LISIERE'] as Map;
    final mineralAfterRun = sector['mineral'];
    sector['organic'] = 30;
    sector['lastOrganicAt'] = now;

    state = ElevageDomain.refreshExploration(state,
        now + const Duration(hours: 14).inMilliseconds, defaultElevageConfig);
    final refreshedSector = (ElevageDomain.explorationState(state)['sectors']
        as Map)['FORET_HUMIDE_LISIERE'] as Map;
    expect(refreshedSector['organic'], 100);
    expect(refreshedSector['mineral'], mineralAfterRun);
    expect(ElevageDomain.explorationState(state)['stamina'], 10);
  });

  test(
      'Exploration applique les coûts déclaratifs et ne tire jamais un loot impossible',
      () {
    expect(
        ElevageDomain.explorationLootCostsFor(
            <String, dynamic>{'resourceCategory': 'GENERIC_ORGANIC'},
            defaultElevageConfig),
        <String, int>{'organic': 1, 'mineral': 0});
    expect(
        ElevageDomain.explorationLootCostsFor(
            <String, dynamic>{'resourceCategory': 'ORGANIC_SPECIFIC'},
            defaultElevageConfig),
        <String, int>{'organic': 5, 'mineral': 0});
    expect(
        ElevageDomain.explorationLootCostsFor(
            <String, dynamic>{'resourceCategory': 'GENERIC_MINERAL'},
            defaultElevageConfig),
        <String, int>{'organic': 0, 'mineral': 1});
    expect(
        ElevageDomain.explorationLootCostsFor(
            <String, dynamic>{'resourceCategory': 'MINERAL_SPECIFIC'},
            defaultElevageConfig),
        <String, int>{'organic': 0, 'mineral': 3});

    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final sector = (ElevageDomain.explorationState(state)['sectors']
        as Map)['LITTORAL_DUNE'] as Map;
    sector['organic'] = 0;
    sector['mineral'] = 2;
    state = ElevageDomain.startExploration(
        state, 'LITTORAL_DUNE', now, defaultElevageConfig);
    final results = (ElevageDomain.explorationState(state)['activeRun']
        as Map)['results'] as List;
    final resources =
        results.whereType<Map>().map((result) => result['resourceId']).toList();
    expect(resources, isNot(contains('SALT')));
    expect(resources, isNot(contains('QUARTZ')));
    expect(sector['organic'], greaterThanOrEqualTo(0));
    expect(sector['mineral'], greaterThanOrEqualTo(0));
  });

  test(
      'Exploration persiste un run, limite à trois slots et dépose le loot dans la Réserve',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.startExploration(
        state, 'LITTORAL_CRIQUE', now, defaultElevageConfig);
    final restored = ElevageSave.fromJson(state.toJson());
    final run = ElevageDomain.explorationState(restored)['activeRun'] as Map;
    expect((run['results'] as List), hasLength(3));
    expect(run['status'], 'IN_PROGRESS');
    expect(
        () => ElevageDomain.startExploration(
            restored, 'COLLINE_GROTTE', now + 1, defaultElevageConfig),
        throwsStateError);

    state = ElevageDomain.refreshExploration(restored,
        now + const Duration(seconds: 25).inMilliseconds, defaultElevageConfig);
    expect(
        (ElevageDomain.explorationState(state)['activeRun'] as Map)['status'],
        'READY');
    final beforeInventory = state.data['inventory'] as Map;
    final before = <Map>[
      beforeInventory['generic'] as Map,
      beforeInventory['special'] as Map,
    ].fold<int>(0, (sum, stock) {
      return sum +
          stock.values.fold<int>(
              0, (subtotal, value) => subtotal + (value as num).toInt());
    });
    state = ElevageDomain.claimExploration(state,
        now + const Duration(seconds: 26).inMilliseconds, defaultElevageConfig);
    final claimed = ElevageDomain.explorationState(state)['activeRun'] as Map;
    expect(claimed['status'], 'CLAIMED');
    final inventory = state.data['inventory'] as Map;
    final after = <Map>[
      inventory['generic'] as Map,
      inventory['special'] as Map
    ].fold<int>(0, (sum, stock) {
      return sum +
          stock.values.fold<int>(
              0, (subtotal, value) => subtotal + (value as num).toInt());
    });
    expect(after, greaterThan(before));
  });

  test('Exploration refuse une sortie lorsque la stamina est épuisée', () {
    final state = ElevageSave.initial(defaultElevageConfig, now: now);
    ElevageDomain.explorationState(state)['stamina'] = 0;
    expect(
        () => ElevageDomain.startExploration(
            state, 'COLLINE_GROTTE', now, defaultElevageConfig),
        throwsStateError);
  });

  test('Exploration applique les overrides sectoriels du Dashboard', () {
    final progression =
        Map<String, dynamic>.from(defaultElevageConfig.refugeProgression);
    final exploration =
        Map<String, dynamic>.from(progression['exploration'] as Map);
    exploration['sectorOverrides'] = <String, dynamic>{
      'LITTORAL_DUNE': <String, dynamic>{
        'initialOrganic': 12,
        'initialMineral': 34,
        'maxOrganic': 80,
        'enabled': false,
      },
    };
    progression['exploration'] = exploration;
    final config =
        defaultElevageConfig.copyWith(refugeProgression: progression);
    final state = ElevageSave.initial(config, now: now);
    final sector = (ElevageDomain.explorationState(state)['sectors']
        as Map)['LITTORAL_DUNE'] as Map;
    expect(sector['organic'], 12);
    expect(sector['mineral'], 34);
    final regenerated = ElevageDomain.refreshExploration(
        state, now + const Duration(hours: 14).inMilliseconds, config);
    expect(
        ((ElevageDomain.explorationState(regenerated)['sectors']
            as Map)['LITTORAL_DUNE'] as Map)['organic'],
        80);
    expect(
        () =>
            ElevageDomain.startExploration(state, 'LITTORAL_DUNE', now, config),
        throwsStateError);
  });

  test(
      'Exploration refuse Baby mais accepte un Juvénile et attribue XP à la fin',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Hawl',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    expect(
        () => ElevageDomain.startExploration(
            state, 'FORET_HUMIDE_LISIERE', now, defaultElevageConfig,
            companionPtipoteId: id),
        throwsStateError);
    final individual = (state.data['individuals'] as Map)[id] as Map;
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    (individual['professions'] as Map)['TRACKER'] = <String, dynamic>{
      'professionId': 'TRACKER',
      'xp': 90,
      'level': 0,
    };
    state = ElevageDomain.startExploration(
        state, 'FORET_HUMIDE_LISIERE', now, defaultElevageConfig,
        companionPtipoteId: id);
    var run = ElevageDomain.explorationState(state)['activeRun'] as Map;
    expect(run['companionPtipoteId'], id);
    expect(run['slots'], 3);
    final startedIndividual = (state.data['individuals'] as Map)[id] as Map;
    expect(((startedIndividual['explorationStamina'] as Map)['current']), 9);
    state = ElevageDomain.refreshExploration(state,
        now + const Duration(seconds: 25).inMilliseconds, defaultElevageConfig);
    state = ElevageDomain.claimExploration(state,
        now + const Duration(seconds: 26).inMilliseconds, defaultElevageConfig);
    final refreshed = (state.data['individuals'] as Map)[id] as Map;
    expect(
        ElevageDomain.trackerProfession(refreshed, defaultElevageConfig)['xp'],
        100);
    expect(
        ElevageDomain.trackerProfession(
            refreshed, defaultElevageConfig)['level'],
        1);
    run = ElevageDomain.explorationState(state)['activeRun'] as Map;
    expect(run['trackerXpGained'], 10);
    expect(run['trackerLevelAfter'], 1);
  });

  test('Pisteur ajoute ses slots cumulés et endurance régénère hors ligne', () {
    for (final entry in <int, int>{0: 3, 1: 4, 2: 5, 3: 6}.entries) {
      var state = ElevageSave.initial(defaultElevageConfig, now: now);
      state = ElevageDomain.adopt(
          source: state,
          alcoveId: 'alcove-1',
          name: 'Trace',
          physical: false,
          now: now,
          config: defaultElevageConfig);
      final id = (state.data['activeIndividualIds'] as List).single as String;
      final individual = (state.data['individuals'] as Map)[id] as Map;
      (individual['lifecycle'] as Map)['stage'] = 'MATURE';
      state = ElevageDomain.forceTrackerLevel(
          state, id, entry.key, defaultElevageConfig);
      state = ElevageDomain.startExploration(
          state, 'LITTORAL_CRIQUE', now, defaultElevageConfig,
          companionPtipoteId: id);
      expect(
          (ElevageDomain.explorationState(state)['activeRun'] as Map)['slots'],
          entry.value);
    }
    var enduranceState = ElevageSave.initial(defaultElevageConfig, now: now);
    enduranceState = ElevageDomain.adopt(
        source: enduranceState,
        alcoveId: 'alcove-1',
        name: 'Endure',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id =
        (enduranceState.data['activeIndividualIds'] as List).single as String;
    final individual = (enduranceState.data['individuals'] as Map)[id] as Map;
    (individual['explorationStamina'] as Map)['current'] = 0;
    (individual['explorationStamina'] as Map)['lastUpdatedAt'] = now;
    enduranceState = ElevageDomain.refreshExploration(enduranceState,
        now + const Duration(minutes: 5).inMilliseconds, defaultElevageConfig);
    expect(
        ((enduranceState.data['individuals'] as Map)[id]['explorationStamina']
            ['current']),
        1);
  });

  test('Le biais Minéral ne crée pas de loot ni ne contourne le stock local',
      () {
    final progression =
        Map<String, dynamic>.from(defaultElevageConfig.refugeProgression);
    final exploration =
        Map<String, dynamic>.from(progression['exploration'] as Map)
          ..['typeLootBiasMultipliers'] = <String, double>{'MINERAL': 10};
    exploration['sectorOverrides'] = <String, dynamic>{
      'COLLINE_GROTTE': <String, dynamic>{
        'initialOrganic': 100,
        'initialMineral': 2,
        'lootTable': <Map<String, dynamic>>[
          <String, dynamic>{
            'resourceId': 'ROOT',
            'resourceCategory': 'ORGANIC_SPECIFIC',
            'weight': 1,
            'enabled': true,
          },
          <String, dynamic>{
            'resourceId': 'IRON',
            'resourceCategory': 'MINERAL_SPECIFIC',
            'weight': 999,
            'enabled': true,
          },
        ],
      },
    };
    progression['exploration'] = exploration;
    final config =
        defaultElevageConfig.copyWith(refugeProgression: progression);
    var state = ElevageSave.initial(config, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Ore',
        physical: false,
        now: now,
        config: config);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final individual = (state.data['individuals'] as Map)[id] as Map;
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    individual['family'] = 'MINERAL';
    state = ElevageDomain.startExploration(state, 'COLLINE_GROTTE', now, config,
        companionPtipoteId: id);
    final results = (ElevageDomain.explorationState(state)['activeRun']
        as Map)['results'] as List;
    expect(results.map((entry) => (entry as Map)['resourceId']),
        everyElement('ROOT'));
    final sector = (ElevageDomain.explorationState(state)['sectors']
        as Map)['COLLINE_GROTTE'] as Map;
    expect(sector['mineral'], 2);
    expect(sector['organic'], 85);
  });

  test('Satiety V2 décroît hors ligne, se recharge par valeur et reste bornée',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Nourri',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.setIndividualSatiety(state, id, 80, now);
    expect(
        ElevageDomain.satietyPercent(
            state,
            id,
            now + const Duration(hours: 3).inMilliseconds,
            defaultElevageConfig),
        50);
    final individual = (state.data['individuals'] as Map)[id] as Map;
    individual['family'] = 'VEGETAL';
    state = ElevageDomain.setIndividualSatiety(state, id, 40, now);
    (state.data['inventory']['special'] as Map)['FRUIT'] = 1;
    state =
        ElevageDomain.offerFood(state, id, 'FRUIT', now, defaultElevageConfig);
    expect(
        ElevageDomain.satietyPercent(state, id, now, defaultElevageConfig), 60);
    ((state.data['individuals'] as Map)[id] as Map)['family'] = 'FUNGAL';
    state = ElevageDomain.setIndividualSatiety(state, id, 60, now);
    (state.data['inventory']['special'] as Map)['ROOT'] = 1;
    state =
        ElevageDomain.offerFood(state, id, 'ROOT', now, defaultElevageConfig);
    expect(
        ElevageDomain.satietyPercent(state, id, now, defaultElevageConfig), 80);
    state = ElevageDomain.setIndividualSatiety(state, id, 95, now);
    (state.data['inventory']['special'] as Map)['ROOT'] = 1;
    state =
        ElevageDomain.offerFood(state, id, 'ROOT', now, defaultElevageConfig);
    expect(ElevageDomain.satietyPercent(state, id, now, defaultElevageConfig),
        100);
    state = ElevageDomain.setIndividualSatiety(state, id, 5, now);
    expect(
        ElevageDomain.satietyPercent(
            state,
            id,
            now + const Duration(hours: 10).inMilliseconds,
            defaultElevageConfig),
        0);
  });

  test('Satiety V2 garde les seuils, pools et préférences séparés', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Seuil',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    state = ElevageDomain.setIndividualSatiety(state, id, 70, now);
    expect(
        ElevageDomain.hunger(state, id, now, defaultElevageConfig), 'SATIATED');
    state = ElevageDomain.setIndividualSatiety(state, id, 69, now);
    expect(
        ElevageDomain.hunger(state, id, now, defaultElevageConfig), 'HUNGRY');
    state = ElevageDomain.setIndividualSatiety(state, id, 49, now);
    expect(ElevageDomain.hunger(state, id, now, defaultElevageConfig),
        'VERY_HUNGRY');
    final individual = (state.data['individuals'] as Map)[id] as Map;
    individual['family'] = 'VEGETAL';
    expect(ElevageDomain.canEat(individual, 'ALGAE', defaultElevageConfig),
        isFalse);
    expect(defaultElevageConfig.foodSatietyValue('LEAF'), 10);
    expect(defaultElevageConfig.foodSatietyValue('MOSS'), 10);
    expect(defaultElevageConfig.foodSatietyValue('ALGAE'), 15);
    expect(defaultElevageConfig.foodSatietyValue('ROOT'), 20);
    expect(defaultElevageConfig.foodSatietyValue('FRUIT'), 20);
    expect(defaultElevageConfig.foodSatietyValue('MUSHROOM'), 20);
    expect(defaultElevageConfig.foodSatietyValue('FIBROUS_FRUIT'), 10);
  });

  test('les expressions de faim respectent Baby, Juvénile et Mature', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Parleur',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    const signalAt = ((now ~/ 1000 ~/ 40) + 1) * 40 * 1000;
    state = ElevageDomain.setIndividualSatiety(state, id, 60, signalAt);
    expect(
        ElevageDomain.hungerExpression(
            state, id, signalAt, defaultElevageConfig)?['voice'],
        'Pti…');
    final individual = (state.data['individuals'] as Map)[id] as Map;
    (individual['lifecycle'] as Map)['stage'] = 'INTERMEDIATE';
    expect(
        ElevageDomain.hungerExpression(
            state, id, signalAt, defaultElevageConfig)?['voice'],
        'Pti !');
    (individual['conceptExposures'] as Map)['HUNGER'] = <String, dynamic>{
      'total': 5,
      'baby': 0
    };
    expect(
        ElevageDomain.hungerExpression(
            state, id, signalAt, defaultElevageConfig)?['voice'],
        'faim');
    final communication = Map<String, dynamic>.from(
        defaultElevageConfig.refugeProgression['communication'] as Map);
    communication['HUNGER'] = <String, String>{
      'juvenileText': 'ventre vide',
      'matureText': 'J’ai faim.',
    };
    communication['VERY_HUNGRY'] = <String, String>{
      'juvenileText': 'ventre vide !',
      'matureText': 'Mon ventre réclame à manger.',
    };
    final configured = defaultElevageConfig.copyWith(refugeProgression: {
      ...defaultElevageConfig.refugeProgression,
      'communication': communication,
    });
    expect(
        ElevageDomain.hungerExpression(
            state, id, signalAt, configured)?['voice'],
        'ventre vide');
    (individual['lifecycle'] as Map)['stage'] = 'MATURE';
    state = ElevageDomain.setIndividualSatiety(state, id, 30, signalAt);
    expect(
        ElevageDomain.hungerExpression(
            state, id, signalAt, configured)?['voice'],
        'Mon ventre réclame à manger.');
  });

  test('migration Satiety V2 protège une ancienne sauvegarde récemment nourrie',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    state = ElevageDomain.adopt(
        source: state,
        alcoveId: 'alcove-1',
        name: 'Legacy',
        physical: false,
        now: now,
        config: defaultElevageConfig);
    final id = (state.data['activeIndividualIds'] as List).single as String;
    final legacy = state.toJson();
    legacy['satietyV22Migration'] = false;
    legacy['savedAt'] = now;
    final care = (legacy['individuals'] as Map)[id]['care'] as Map;
    care
      ..remove('satiety')
      ..remove('satietyUpdatedAt')
      ..['lastMealAt'] = now - const Duration(hours: 25).inMilliseconds;
    final migrated = ElevageSave.fromJson(legacy);
    expect(
        ElevageDomain.satietyPercent(migrated, id, now, defaultElevageConfig),
        70);
    expect(migrated.data['satietyV22Migration'], isTrue);
  });

  test('endurance Exploration se régénère par paliers de cinq minutes', () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    ElevageDomain.explorationState(state)
      ..['stamina'] = 9
      ..['lastStaminaAt'] = now;
    state = ElevageDomain.refreshExploration(state,
        now + const Duration(minutes: 4).inMilliseconds, defaultElevageConfig);
    expect(ElevageDomain.explorationState(state)['stamina'], 9);
    state = ElevageDomain.refreshExploration(state,
        now + const Duration(minutes: 5).inMilliseconds, defaultElevageConfig);
    expect(ElevageDomain.explorationState(state)['stamina'], 10);
  });

  test('Biogénérateur produit automatiquement, respecte son cycle et son cap',
      () {
    var state = ElevageSave.initial(defaultElevageConfig, now: now);
    final alcove = (state.data['alcoves'] as List).first as Map;
    alcove['localEnergy'] = 0;
    alcove['biogeneratorSlot'] = <String, dynamic>{
      'instanceId': 'generator-auto',
      'definitionId': 'BIOGENERATOR',
      'cycleStartedAt': now,
      'tanks': <String, int>{'organic': 10, 'mineral': 5},
      'installedModules': <dynamic>[],
    };
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(seconds: 9).inMilliseconds, defaultElevageConfig);
    expect((state.data['alcoves'] as List).first['localEnergy'], 0);
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(seconds: 10).inMilliseconds, defaultElevageConfig);
    final refreshed = (state.data['alcoves'] as List).first as Map;
    final tanks = (refreshed['biogeneratorSlot'] as Map)['tanks'] as Map;
    expect(refreshed['localEnergy'], 10);
    expect(tanks['organic'], 7);
    expect(tanks['mineral'], 3);
    refreshed['localEnergy'] = 200;
    state = ElevageDomain.refreshAlcove(state, 'alcove-1',
        now + const Duration(seconds: 30).inMilliseconds, defaultElevageConfig);
    expect((state.data['alcoves'] as List).first['localEnergy'], 200);
  });
}
