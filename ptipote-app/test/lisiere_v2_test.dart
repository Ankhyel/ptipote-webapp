import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/lisiere_v2.dart';

void main() {
  test('les nœuds de Lisière utilisent le profil visuel du Biome', () {
    expect(
      lisiereBiomeNodeVisual(
        visualProfile: const <String, dynamic>{'groundSet': 'shore'},
        kind: LisiereResourceKind.organic,
        seed: 0,
      ),
      '🪸',
    );
    expect(
      lisiereBiomeNodeVisual(
        visualProfile: const <String, dynamic>{'groundSet': 'sand'},
        kind: LisiereResourceKind.mineral,
        seed: 1,
      ),
      '⛏️',
    );
  });

  test('a V2 biome graph has 6 to 9 connected, stable parcels', () {
    final first = createBiomeParcelGraph(biomeId: 'biome-1', seed: 1234);
    final second = createBiomeParcelGraph(biomeId: 'biome-1', seed: 1234);

    expect(first.parcels.length, inInclusiveRange(6, 9));
    expect(first.parcels.map((parcel) => parcel.id),
        second.parcels.map((parcel) => parcel.id));
    expect(first.edges.map((edge) => edge.toMap()),
        second.edges.map((edge) => edge.toMap()));
    expect(
        first.parcels.every((parcel) => parcel.connectedParcelIds.isNotEmpty),
        isTrue);
    expect(
      first.edges.every(
        (edge) => LisiereTravelDifficulty.values.contains(edge.difficulty),
      ),
      isTrue,
    );
  });

  test('travel edge durations are configured by class', () {
    const config = LisiereV2Config(
      easyTravelSeconds: 60,
      mediumTravelSeconds: 120,
      hardTravelSeconds: 180,
    );
    expect(config.travelSeconds(LisiereTravelDifficulty.easy), 60);
    expect(config.travelSeconds(LisiereTravelDifficulty.medium), 120);
    expect(config.travelSeconds(LisiereTravelDifficulty.hard), 180);
  });

  test('organic harvest gives one base Organique per vitality and awaits ecology', () {
    final node = LisiereResourceNode.organic(
      id: 'organic-1',
      parcelId: 'parcel-1',
      maxResistance: 10,
      standardYield: 1,
      visualVariant: 'grass',
    );
    const actor = LisiereHarvestActor(
      id: 'ptipote-1',
      harvestPower: 1,
      actionFrequency: 1,
      yieldModifier: 1.05,
      maxVitality: 100,
      currentVitality: 100,
    );
    final first = node.applyAction(actor);
    expect(first.creditedAmount, 1);
    expect(node.resistance, 9);
    for (var index = 0; index < 9; index += 1) {
      node.applyAction(actor);
    }
    expect(node.state, LisiereResourceNodeState.temporarilyDepleted);

    node.restoreOrganicFromBiomass();
    final second = node.applyAction(actor);
    expect(second.creditedAmount, 1);
    expect(node.resistance, 9);
  });

  test('mineral layers are finite and never regenerate', () {
    final node = LisiereResourceNode.mineral(
      id: 'mineral-1',
      parcelId: 'parcel-1',
      maxResistance: 1,
      standardYield: 10,
      remainingLayers: 2,
      visualVariant: 'rock',
    );
    const actor = LisiereHarvestActor(
      id: 'ptipote-1',
      harvestPower: 1,
      actionFrequency: 1,
      yieldModifier: 1,
      maxVitality: 100,
      currentVitality: 100,
    );
    node.applyAction(actor);
    expect(node.remainingLayers, 1);
    expect(node.state, LisiereResourceNodeState.available);
    node.applyAction(actor);
    expect(node.remainingLayers, 0);
    expect(node.state, LisiereResourceNodeState.exhausted);
    node.restoreOrganicFromBiomass();
    expect(node.state, LisiereResourceNodeState.exhausted);
  });

  test('waste nodes are finite and remain distinct from organic nodes', () {
    final node = LisiereResourceNode.waste(
      id: 'waste-1',
      parcelId: 'parcel-1',
      maxResistance: 1,
      standardYield: 1,
      remainingLayers: 1,
      visualVariant: '♻️',
    );
    const actor = LisiereHarvestActor(
      id: 'bug-1',
      harvestPower: 1,
      actionFrequency: 1,
      yieldModifier: 1,
      maxVitality: 100,
      currentVitality: 100,
    );
    expect(node.applyAction(actor).resource, LisiereResourceKind.waste);
    expect(node.state, LisiereResourceNodeState.exhausted);
  });

  test('P’TIBUG species and traits choose their real harvest speciality', () {
    final scarabe = LisierePTibugState(
      id: 'scarabe-1',
      displayName: 'Roc',
      capacity: 10,
      speciesId: 'scarabe',
      traitDefinitionIds: const <String>['mineur'],
      maintenance: LisierePTibugMaintenance(
        ptibugId: 'scarabe-1',
        dailyRation: 1,
        lastResolvedAt: DateTime.utc(2026),
      ),
    );
    final arac = LisierePTibugState(
      id: 'arac-1',
      displayName: 'Trame',
      capacity: 10,
      speciesId: 'arac',
      maintenance: LisierePTibugMaintenance(
        ptibugId: 'arac-1',
        dailyRation: 1,
        lastResolvedAt: DateTime.utc(2026),
      ),
    );
    expect(scarabe.preferredResources.single, LisiereResourceKind.mineral);
    expect(scarabe.yieldModifierFor(LisiereResourceKind.mineral), 1.1);
    expect(scarabe.yieldModifierFor(LisiereResourceKind.organic), 1);
    expect(arac.preferredResources.first, LisiereResourceKind.waste);
  });

  test('field inventories, team capacity and return reserve remain distinct',
      () {
    final inventory = LisiereFieldInventory(id: 'field-1', capacity: 5);
    expect(inventory.add(LisiereResourceKind.organic, 4), 4);
    expect(inventory.add(LisiereResourceKind.mineral, 3), 1);
    expect(inventory.amounts[LisiereResourceKind.organic], 4);
    expect(inventory.amounts[LisiereResourceKind.mineral], 1);
    expect(
      teamCapacity(
        hasTeamManagementStructure: true,
        logisticsOptimizationModules: 2,
      ),
      5,
    );
    expect(
      canSpendVitality(
        currentVitality: 17,
        actionCost: 2,
        returnCostFromDestination: 10,
      ),
      isTrue,
    );
    expect(
      canSpendVitality(
        currentVitality: 16,
        actionCost: 2,
        returnCostFromDestination: 10,
      ),
      isFalse,
    );
  });

  test('missions resolve once from timestamps and never exceed planned time',
      () {
    final startedAt = DateTime.utc(2026, 1, 1, 12);
    final mission = LisiereMissionInstance(
      id: 'mission-1',
      teamId: 'team-1',
      originId: 'camp-1',
      plannedDuration: const Duration(minutes: 30),
      startedAt: startedAt,
      routeParcelIds: const <String>['parcel-1'],
      targetParcelIds: const <String>['parcel-1'],
      randomSeed: 42,
    );
    expect(mission.resolveUntil(startedAt.add(const Duration(minutes: 10))),
        isTrue);
    expect(mission.resolveUntil(startedAt.add(const Duration(minutes: 10))),
        isFalse);
    expect(
        mission.resolveUntil(startedAt.add(const Duration(hours: 2))), isTrue);
    expect(mission.lastResolvedAt, mission.plannedEndAt);
    expect(mission.status, LisiereMissionStatus.completed);
  });

  test('mission regime and accompanied destination survive persistence', () {
    final startedAt = DateTime.utc(2026, 1, 1, 12);
    final mission = LisiereMissionInstance(
      id: 'mission-regime',
      teamId: 'team-1',
      originId: 'camp-storage-v2',
      plannedDuration: const Duration(hours: 1),
      startedAt: startedAt,
      routeParcelIds: const <String>['parcel-2'],
      targetParcelIds: const <String>['parcel-2'],
      randomSeed: 7,
      regime: LisiereHarvestRegime.intensif,
    );
    final restored = LisiereMissionInstance.fromMap(mission.toMap());
    expect(restored.regime, LisiereHarvestRegime.intensif);
    final team = LisiereTeam(
      id: 'team-1',
      ptipoteIds: const <String>['p-1'],
      fieldInventoryId: 'team-1-field',
      currentParcelId: 'parcel-2',
    );
    expect(LisiereTeam.fromMap(team.toMap()).currentParcelId, 'parcel-2');
  });

  test('mission time reserves an explicit travel and return window', () {
    final startedAt = DateTime.utc(2026, 1, 1, 12);
    final mission = LisiereMissionInstance(
      id: 'mission-travel',
      teamId: 'team-1',
      originId: 'camp-storage-v2',
      plannedDuration: const Duration(minutes: 30),
      startedAt: startedAt,
      routeParcelIds: const <String>['parcel-1'],
      targetParcelIds: const <String>['parcel-1'],
      randomSeed: 2,
      travelDuration: const Duration(minutes: 6),
    );
    expect(mission.workStartsAt, startedAt.add(const Duration(minutes: 3)));
    expect(mission.returnStartsAt, startedAt.add(const Duration(minutes: 27)));
    expect(
      mission.workDurationAt(startedAt.add(const Duration(minutes: 30))),
      const Duration(minutes: 24),
    );
    expect(mission.stageAt(startedAt.add(const Duration(minutes: 2))),
        LisiereMissionStatus.traveling);
  });

  test('danger, security, losses and boss rules are deterministic', () {
    final danger = BiomeDangerState(
      biomeId: 'biome-1',
      danger: 50,
      dangerCap: 80,
      lastResolvedAt: DateTime.utc(2026),
      bossDroneActive: true,
    );
    danger.resolveNaturalIncrease(DateTime.utc(2026, 1, 1, 4));
    expect(danger.danger, 52);
    expect(danger.markExploited('mission-1'), isTrue);
    expect(danger.danger, 47);
    expect(danger.markExploited('mission-1'), isFalse);
    expect(finalEncounterChance(biomeDanger: 50, groupSecurity: 20), 40);
    expect(truncatedLoss(15, .25), 3);
    expect(
      vitalityAfterEncounter(
        currentVitality: 20,
        maxVitality: 100,
        lossPercent: .25,
        requiredReturnVitality: 8,
      ),
      8,
    );
    expect(resolveAutonomousBossDrone(groupSecurity: 49),
        BossDroneOutcome.interrupted);
    expect(resolveAutonomousBossDrone(groupSecurity: 50),
        BossDroneOutcome.neutralized);
  });

  test('regimes change absolute action cost and frequency, never max vitality',
      () {
    expect(
      missionActionVitalityCost(
        baseActionCost: 4,
        regime: LisiereHarvestRegime.normal,
      ),
      4,
    );
    expect(
      missionActionVitalityCost(
        baseActionCost: 4,
        regime: LisiereHarvestRegime.intensif,
      ),
      5,
    );
    expect(
      effectiveActionFrequency(
        baseFrequency: 2,
        regime: LisiereHarvestRegime.doux,
      ),
      1.5,
    );
  });

  test('Récolteur needs exactly 100 training strikes before autonomous N1', () {
    var progress = const LisiereJobProgress(
      ptipoteId: 'ptipote-1',
      job: LisierePtipoteJob.recolteur,
    );
    for (var index = 0; index < 99; index += 1) {
      progress = progress.recordHarvestAction();
    }
    expect(progress.level, LisiereJobLevel.n0);
    expect(progress.currentProgress, 99);
    progress = progress.recordHarvestAction();
    expect(progress.level, LisiereJobLevel.n1);
  });

  test('Patrouilleur earns 5 XP per encounter and 15 per successful QTE', () {
    var progress = const LisiereJobProgress(
      ptipoteId: 'ptipote-1',
      job: LisierePtipoteJob.patrouilleur,
    );
    progress = progress.recordPatrolEncounter();
    expect(progress.currentProgress, 5);
    progress = progress.recordPatrolQte();
    expect(progress.currentProgress, 20);
    progress = progress.recordPatrolQte().recordPatrolQte();
    expect(progress.level, LisiereJobLevel.n1);
    expect(progress.currentProgress, 50);
  });

  test('encounter losses preserve the return reserve and toxic is explicit',
      () {
    final toxic =
        defaultLisiereEncounterResolutions[LisiereEncounterType.toxic]!;
    final drone =
        defaultLisiereEncounterResolutions[LisiereEncounterType.standardDrone]!;
    expect(toxic.appliesToxicAffliction, isTrue);
    expect(toxic.cargoLost(19), 1);
    expect(drone.cargoLost(19), 4);
    expect(
      drone.vitalityAfter(
        currentVitality: 16,
        maxVitality: 100,
        requiredReturnVitality: 5,
      ),
      5,
    );
  });

  test('snapshot persists graphs, fractional nodes and separate stocks', () {
    final snapshot = createLisiereV2Snapshot(
      biomeIds: const <String>['biome-a'],
      seed: 72,
      createdAt: DateTime.utc(2026),
    );
    snapshot.inventories['terrain-a'] =
        LisiereFieldInventory(id: 'terrain-a', capacity: 10);
    snapshot.inventories['terrain-a']!.add(LisiereResourceKind.organic, 4);
    final restored = LisiereV2Snapshot.fromMap(snapshot.toMap());
    expect(restored.graphs['biome-a']!.parcels.length, inInclusiveRange(6, 9));
    expect(restored.nodes.length, snapshot.nodes.length);
    expect(restored.inventories['terrain-a']!.used, 4);
  });

  test('autonomy is N1-only and returns before consuming its reserve', () {
    const n0 = LisiereJobProgress(
      ptipoteId: 'ptipote-1',
      job: LisierePtipoteJob.recolteur,
    );
    expect(
      canStartAutonomousHarvest(
        recolteur: n0,
        targetParcelIds: const <String>['parcel-1'],
      ),
      isFalse,
    );
    final n1 = n0.copyWith(
      harvestLearningActions: LisiereJobProgress.harvestActionsForN1,
    );
    expect(
      canStartAutonomousHarvest(
        recolteur: n1,
        targetParcelIds: const <String>['parcel-1'],
      ),
      isTrue,
    );
    final node = LisiereResourceNode.organic(
      id: 'organic-1',
      parcelId: 'parcel-1',
      maxResistance: 1,
      standardYield: 1,
      visualVariant: '🌿',
    );
    final result = resolveAutonomousHarvest(
      elapsedWork: const Duration(minutes: 5),
      targetNodes: <LisiereResourceNode>[node],
      inventory: LisiereFieldInventory(id: 'terrain', capacity: 20),
      actor: const LisiereHarvestActor(
        id: 'ptipote-1',
        harvestPower: 1,
        actionFrequency: 1,
        yieldModifier: 1,
        maxVitality: 100,
        currentVitality: 8,
      ),
      regime: LisiereHarvestRegime.normal,
      baseActionVitalityCost: 2,
      returnVitalityCost: 1,
    );
    expect(result.actionsResolved, 1);
    expect(result.finalVitality, 6);
    expect(result.stoppedForReturnReserve, isTrue);
  });

  test('P’TIBUG maintenance consumes a persisted fractional daily ration', () {
    final maintenance = LisierePTibugMaintenance(
      ptibugId: 'bug-1',
      dailyRation: 1,
      rationReserve: 1,
      lastResolvedAt: DateTime.utc(2026),
    );
    expect(
      maintenance.resolveMaintenanceUntil(DateTime.utc(2026, 1, 1, 12)),
      closeTo(.5, .0001),
    );
    expect(maintenance.rationReserve, closeTo(.5, .0001));
    maintenance.feed(.25);
    expect(maintenance.rationReserve, closeTo(.75, .0001));
  });

  test('Dashboard configuration controls V2 thresholds and travel classes', () {
    final config = LisiereV2Config.fromMap(<String, dynamic>{
      'easyTravelSeconds': 10,
      'recolteurActionsForN1': 2,
      'patrouilleurExperienceForN1': 20,
      'patrouilleurEncounterExperience': 5,
      'patrouilleurQteExperience': 15,
    });
    expect(config.travelSeconds(LisiereTravelDifficulty.easy), 10);
    var harvest = const LisiereJobProgress(
      ptipoteId: 'ptipote-1',
      job: LisierePtipoteJob.recolteur,
    );
    harvest = harvest.recordHarvestAction().recordHarvestAction();
    expect(harvest.levelFor(config), LisiereJobLevel.n1);
    var patrol = const LisiereJobProgress(
      ptipoteId: 'ptipote-1',
      job: LisierePtipoteJob.patrouilleur,
    );
    patrol = patrol.recordPatrolEncounter(config).recordPatrolQte(config);
    expect(patrol.levelFor(config), LisiereJobLevel.n1);
  });

  test('V2 snapshot keeps teams, outposts, rotations and expedition vitality',
      () {
    final snapshot = createLisiereV2Snapshot(
      biomeIds: const <String>['biome-a'],
      seed: 23,
      createdAt: DateTime.utc(2026),
    );
    snapshot.ptipotes['p-1'] = LisierePtipoteState(
      id: 'p-1',
      displayName: 'Mousse',
      currentVitality: 73,
      maxVitality: 100,
    );
    snapshot.teams['team-a'] = LisiereTeam(
      id: 'team-a',
      ptipoteIds: const <String>['p-1'],
      fieldInventoryId: 'team-a-field',
    );
    snapshot.outposts['outpost-biome-a'] = const OutpostInstance(
      id: 'outpost-biome-a',
      biomeId: 'biome-a',
      storageId: 'outpost-biome-a-storage',
      state: 'active',
    );
    snapshot.rotations['rotation-a'] = LisiereCargoRotation(
      id: 'rotation-a',
      carrierId: 'p-1',
      originInventoryId: 'team-a-field',
      destinationInventoryId: 'camp-storage-v2',
      startedAt: DateTime.utc(2026),
    );
    final restored = LisiereV2Snapshot.fromMap(snapshot.toMap());
    expect(restored.ptipotes['p-1']!.currentVitality, 73);
    expect(restored.teams['team-a']!.fieldInventoryId, 'team-a-field');
    expect(restored.outposts.values.single.biomeId, 'biome-a');
    expect(restored.rotations['rotation-a']!.state,
        LisiereCargoRotationState.collecting);
  });

  test('same persisted visit can resolve an encounter only once', () {
    final visits = <String>{};
    final first = resolveBiomeEntryEncounter(
      visitId: 'mission-a:biome-a',
      randomSeed: 9,
      biomeDanger: 100,
      groupSecurity: 0,
      resolvedVisitIds: visits,
    );
    final retry = resolveBiomeEntryEncounter(
      visitId: 'mission-a:biome-a',
      randomSeed: 9,
      biomeDanger: 100,
      groupSecurity: 0,
      resolvedVisitIds: visits,
    );
    expect(first, isNotNull);
    expect(retry, isNull);
  });

  test('P’TIPOTE cargo keeps two resource stacks while a P’TIBUG remains open',
      () {
    final cargo = LisiereFieldInventory(
      id: 'ptipote-a-cargo',
      capacity: 20,
      maxStacks: 2,
    );
    expect(cargo.add(LisiereResourceKind.organic, 5), 5);
    expect(cargo.add(LisiereResourceKind.mineral, 3), 3);
    expect(cargo.add(LisiereResourceKind.waste, 1), 0);
    expect(cargo.used, 8);
  });

  test('the starter mission completes only after its cargo reaches Camp', () {
    final mission = LisiereStarterMission();
    final camp = LisiereFieldInventory(id: 'camp-storage-v2', capacity: 50)
      ..add(LisiereResourceKind.organic, 5)
      ..add(LisiereResourceKind.mineral, 2);
    mission.refreshFromCamp(camp, DateTime.utc(2026));
    expect(mission.isCompleted, isFalse);
    camp.add(LisiereResourceKind.mineral, 1);
    mission.refreshFromCamp(camp, DateTime.utc(2026));
    expect(mission.isCompleted, isTrue);
  });

  test('regional gateways and snapshot state remain deterministic on restore',
      () {
    final snapshot = createLisiereV2Snapshot(
      biomeIds: const <String>['biome-a', 'biome-b'],
      seed: 77,
      createdAt: DateTime.utc(2026),
      biomeConnections: const <String, List<String>>{
        'biome-a': <String>['biome-b'],
        'biome-b': <String>['biome-a'],
      },
    );
    final restored = LisiereV2Snapshot.fromMap(snapshot.toMap());
    expect(restored.biomeConnections, snapshot.biomeConnections);
    expect(restored.nodes.map((id, node) => MapEntry(id, node.toMap())),
        snapshot.nodes.map((id, node) => MapEntry(id, node.toMap())));
  });

  test('P’TIBUG reserve consumes elapsed active time exactly once', () {
    final maintenance = LisierePTibugMaintenance(
      ptibugId: 'bug-1',
      dailyRation: 1,
      rationReserve: 1,
      lastResolvedAt: DateTime.utc(2026, 1, 1, 12),
    );
    expect(
      maintenance.resolveMaintenanceUntil(DateTime.utc(2026, 1, 1, 18)),
      .25,
    );
    expect(maintenance.rationReserve, .75);
    expect(
      maintenance.resolveMaintenanceUntil(DateTime.utc(2026, 1, 1, 18)),
      0,
    );
  });
}
