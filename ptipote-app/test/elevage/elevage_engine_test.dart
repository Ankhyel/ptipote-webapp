import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/elevage/elevage_config.dart';
import 'package:ptipote_app/features/elevage/elevage_engine.dart';

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
}
