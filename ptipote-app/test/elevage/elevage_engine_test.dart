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
    final favorite = (state.data['individuals'] as Map)[id]['generatedProfile']
        ['foodPreference'] as String;
    state = ElevageDomain.offerFood(
        state, id, favorite, now + 1, defaultElevageConfig);
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
    state.data['discoveredItemIds'] = <String>['LIMESTONE', 'ALGAE_FRAGMENT'];
    final basin = defaultElevageConfig.recipes
        .firstWhere((recipe) => recipe.id == 'BASSIN');
    state = ElevageDomain.craft(state, basin, now + 1, defaultElevageConfig);
    final instanceId =
        (state.data['installationInventory'] as Map).keys.single as String;
    state = ElevageDomain.place(state, 'alcove-1', 0, instanceId, now + 2);
    state = ElevageDomain.refreshAlcove(
        state, 'alcove-1', now + 62000, defaultElevageConfig);
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

  test('satiété est dérivée et bloque seulement un repas normal immédiat', () {
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
        50);
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

  test('une racine désirée est déplacée hors d’une zone trop humide', () {
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
    state = ElevageDomain.placeSceneItem(
        state, 'alcove-1', 'ROOT', 'ZONE_3', now + 1, defaultElevageConfig);
    final first = ElevageDomain.sceneItems(state, 'alcove-1').single;
    final outcome = ElevageDomain.sceneItemOutcome(state, id, 'alcove-1',
        first['instanceId'] as String, now + 2, defaultElevageConfig);
    expect(outcome.behavior, 'MOVE_ITEM');
    expect(outcome.targetZoneId, 'ZONE_1');
    expect(outcome.observationCount, 1);
    state = ElevageDomain.interactSceneItem(state, id, 'alcove-1',
        first['instanceId'] as String, now + 2, defaultElevageConfig);
    expect(
        ElevageDomain.sceneItems(state, 'alcove-1').single['zoneId'], 'ZONE_1');
    final observation = ((state.data['individuals'] as Map)[id]
            ['observationJournal']['observations']
        as Map)['HUMIDITY_AVOIDANCE:HUMIDITY'] as Map;
    expect(observation['count'], 1);
    expect(observation['status'], 'OBSERVED');
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
    expect(ElevageDomain.dayNightPhase(0, defaultElevageConfig), 'DAY');
    expect(
        ElevageDomain.dayNightPhase(
            const Duration(hours: 3).inMilliseconds, defaultElevageConfig),
        'NIGHT');
    final zone3 = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_3', defaultElevageConfig,
        now: 0);
    final zone2 = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
        now: 0);
    expect(zone3['humidity'], 4); // zone +2, bassin +2
    expect(zone2['humidity'], 0); // le bassin ne diffuse pas dans Z2
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

  test('le preset Prototype accélère la faim Bébé par cinq', () {
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
    (state.data['inventory']['special'] as Map)[favorite] = 1;
    state =
        ElevageDomain.offerFood(state, id, favorite, now, defaultElevageConfig);
    expect(
        ElevageDomain.hunger(
            state,
            id,
            now + const Duration(hours: 34).inMilliseconds,
            defaultElevageConfig),
        'HUNGRY');
    expect(
        ElevageDomain.hunger(
            state,
            id,
            now + const Duration(hours: 48).inMilliseconds,
            defaultElevageConfig),
        'VERY_HUNGRY');
    final target = defaultElevageConfig.copyWith(preset: ElevagePreset.target);
    expect(
        ElevageDomain.satietyPercent(
            state, id, now + const Duration(hours: 24).inMilliseconds, target),
        greaterThan(50));
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
    ((state.data['individuals'] as Map)[id]['care'] as Map)['lastMealAt'] = now;
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

  test('phase forcée et installation restent locales à leur zone', () {
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
    expect(day['humidity'], 2);
    expect(other['humidity'], 2); // Z3 de base, sans bassin.
    expect(night['light'], lessThan(day['light']!));
    expect(
        ElevageDomain.dayNightRemainingMs(now, defaultElevageConfig,
            phaseOverride: 'DAY'),
        const Duration(hours: 3).inMilliseconds);
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
    expect(inventory['generic'], <String, int>{'organic': 0, 'mineral': 0});
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

  test('confort lumineux Résonance reste local et dérivé de la config', () {
    expect(defaultElevageConfig.resonanceLightComfort(2), 1);
    expect(defaultElevageConfig.resonanceLightComfort(3), 0);
    expect(defaultElevageConfig.resonanceLightComfort(4), -1);
    expect(defaultElevageConfig.resonanceLightComfort(5), -2);
    expect(
        ElevageDomain.localComfort(
            <String, int>{'light': -1, 'temperature': 0, 'humidity': 0},
            defaultElevageConfig),
        'CONTENT');
    expect(
        ElevageDomain.localComfort(
            <String, int>{'light': 1, 'temperature': 0, 'humidity': 0},
            defaultElevageConfig),
        'DISCOMFORT');
  });
}
