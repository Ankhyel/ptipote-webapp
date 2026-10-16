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
    // Résonance choisit désormais le refuge le plus chaud et viable : Z2.
    expect(outcome.targetZoneId, 'ZONE_2');
    expect(outcome.observationCount, 1);
    state = ElevageDomain.relocateSceneItem(
        state,
        'alcove-1',
        first['instanceId'] as String,
        outcome.targetZoneId!,
        defaultElevageConfig);
    expect(
        ElevageDomain.sceneItems(state, 'alcove-1').single['zoneId'], 'ZONE_2');
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
            const Duration(hours: 4).inMilliseconds, defaultElevageConfig),
        'NIGHT');
    final zone3 = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_3', defaultElevageConfig,
        now: 0);
    final zone2 = ElevageDomain.zoneEnvironment(
        state, 'alcove-1', 'ZONE_2', defaultElevageConfig,
        now: 0);
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
        90);
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
    final requestConfig = defaultElevageConfig.copyWith(
        hungerNormalHours: 1, hungerHungryHours: 2, hungerVeryHungryHours: 3);
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
    (individual['care'] as Map)['lastMealAt'] =
        requestAt - const Duration(hours: 200).inMilliseconds;
    expect(ElevageDomain.hunger(state, id, requestAt, requestConfig),
        anyOf('HUNGRY', 'VERY_HUNGRY'));
    expect(ElevageDomain.isSleeping(individual, requestAt, requestConfig),
        isFalse);
    state = ElevageDomain.refreshRequest(state, id, requestAt, requestConfig);
    expect((state.data['individuals'] as Map)[id]['activeRequest'], isNotNull);
    expect(
        ElevageDomain.activeRequest(state, id, requestAt)?['signal'], 'Pti ?');
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
      'definitionId': 'TROU_GEOTHERMIQUE_CHAUD',
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

  test('température part de 2 la nuit, gagne 1 le jour et diffuse à +2', () {
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
      'definitionId': 'TROU_GEOTHERMIQUE_CHAUD',
      'zoneId': 'ZONE_2',
    };
    expect(scale('ZONE_2', 'DAY'), 5);
    expect(scale('ZONE_3', 'DAY'), 4); // +1 diffusé depuis Z2.
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

  test('communication garde Baby non verbal et apprend selon Contact', () {
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
    ((individual['personality'] as Map)['baseline'] as Map)['contact'] = 40;
    for (var index = 0; index < 3; index++) {
      state = ElevageDomain.recordCommunication(state, id, 'CONTENT');
    }
    expect(
        ElevageDomain.communicationExpression(
            (state.data['individuals'] as Map)[id] as Map,
            'CONTENT',
            defaultElevageConfig)['word'],
        'Bien');
    ((state.data['individuals'] as Map)[id]['personality']['baseline']
        as Map)['contact'] = 60;
    ((state.data['individuals'] as Map)[id]['communicationCounts'] as Map)
        .clear();
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
}
