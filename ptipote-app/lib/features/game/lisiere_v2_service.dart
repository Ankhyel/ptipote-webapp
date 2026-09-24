import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'lisiere_v2.dart';
import 'ptibug_config.dart';

/// Atomic persistence boundary for V2 Lisière state.
///
/// It deliberately lives outside the V1 `zone0` document. A retry reads the
/// latest snapshot in a Firestore transaction, applies one action at most once
/// at that boundary, then writes every affected physical stock together.
class LisiereV2Service {
  LisiereV2Service({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _document(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('game')
      .doc('zone0V2Lisiere');

  Future<LisiereV2Snapshot?> load() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final data = (await _document(user.uid).get()).data();
    return data == null ? null : LisiereV2Snapshot.fromMap(data);
  }

  /// Creates the seeded parcel graphs once. Retrying during onboarding returns
  /// the exact prior graph, so reopening the app never reshuffles the Region.
  Future<LisiereV2Snapshot> ensureCreated({
    required Iterable<String> biomeIds,
    required int seed,
    required DateTime createdAt,
    Map<String, List<String>> biomeConnections = const <String, List<String>>{},
    Map<String, int> biomeSeeds = const <String, int>{},
    Map<String, Map<String, dynamic>> biomeVisualProfiles =
        const <String, Map<String, dynamic>>{},
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour initialiser la Lisière.');
    }
    final reference = _document(user.uid);
    return _firestore.runTransaction<LisiereV2Snapshot>((transaction) async {
      final existing = (await transaction.get(reference)).data();
      if (existing != null) {
        final snapshot = LisiereV2Snapshot.fromMap(existing);
        // The early local V2 document did not include gateway data. This
        // compatible fill never overwrites an already persisted region.
        var changed = false;
        for (final entry in biomeConnections.entries) {
          if (!snapshot.biomeConnections.containsKey(entry.key)) {
            snapshot.biomeConnections[entry.key] =
                List<String>.from(entry.value);
            changed = true;
          }
        }
        if (changed) {
          transaction.set(reference, snapshot.toMap(), SetOptions(merge: true));
        }
        return snapshot;
      }
      final snapshot = createLisiereV2Snapshot(
        biomeIds: biomeIds,
        seed: seed,
        createdAt: createdAt,
        biomeConnections: biomeConnections,
        biomeSeeds: biomeSeeds,
        biomeVisualProfiles: biomeVisualProfiles,
      );
      transaction.set(reference, <String, dynamic>{
        ...snapshot.toMap(),
        'ownerId': user.uid,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'serverUpdatedAt': FieldValue.serverTimestamp(),
      });
      return snapshot;
    });
  }

  Future<void> save(LisiereV2Snapshot snapshot) async {
    final user = _auth.currentUser;
    if (user == null) return;
    snapshot.updatedAt = DateTime.now();
    await _document(user.uid).set(<String, dynamic>{
      ...snapshot.toMap(),
      'ownerId': user.uid,
      'serverUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<LisiereV2Snapshot> _mutate(
    void Function(LisiereV2Snapshot snapshot) change,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise pour la Lisière.');
    final reference = _document(user.uid);
    return _firestore.runTransaction<LisiereV2Snapshot>((transaction) async {
      final data = (await transaction.get(reference)).data();
      if (data == null) throw StateError('Lisière non initialisée.');
      final snapshot = LisiereV2Snapshot.fromMap(data);
      change(snapshot);
      snapshot.updatedAt = DateTime.now();
      transaction.set(
          reference,
          <String, dynamic>{
            ...snapshot.toMap(),
            'ownerId': user.uid,
            'serverUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return snapshot;
    });
  }

  /// Cargo belongs to a carrier, never to an invisible group pouch. A linked
  /// P’TIBUG is selected first in the player-defined team order; two-slot
  /// P’TIPOTE inventories provide the fallback.
  LisiereFieldInventory? _cargoDestination(
    LisiereV2Snapshot snapshot,
    LisiereTeam team,
    LisiereResourceKind resource,
  ) {
    final ids = <String>[
      ...team.ptibugIds
          .where((id) => !team.unavailableCarrierIds.contains(id))
          .map((id) => 'ptibug-$id-cargo'),
      ...team.ptipoteIds
          .where((id) => !team.unavailableCarrierIds.contains(id))
          .map((id) => 'ptipote-$id-cargo'),
    ];
    for (final id in ids) {
      final inventory = snapshot.inventories[id];
      if (inventory != null && inventory.canAccept(resource)) return inventory;
    }
    return null;
  }

  List<LisiereFieldInventory> _cargoInventories(
    LisiereV2Snapshot snapshot,
    LisiereTeam team, {
    bool availableOnly = false,
  }) =>
      <String>[
        ...team.ptibugIds
            .where((id) =>
                !availableOnly || !team.unavailableCarrierIds.contains(id))
            .map((id) => 'ptibug-$id-cargo'),
        ...team.ptipoteIds
            .where((id) =>
                !availableOnly || !team.unavailableCarrierIds.contains(id))
            .map((id) => 'ptipote-$id-cargo'),
      ]
          .map((id) => snapshot.inventories[id])
          .whereType<LisiereFieldInventory>()
          .toList();

  double _groupSecurity(LisiereV2Snapshot snapshot, LisiereTeam team) {
    final members = team.ptipoteIds
        .map((id) => snapshot.ptipotes[id])
        .whereType<LisierePtipoteState>()
        .toList();
    if (members.isEmpty) return 0;
    return members.fold<double>(0, (total, item) => total + item.security) /
        members.length;
  }

  String? _biomeForParcel(LisiereV2Snapshot snapshot, String parcelId) {
    for (final graph in snapshot.graphs.values) {
      if (graph.parcels.any((parcel) => parcel.id == parcelId)) {
        return graph.biomeId;
      }
    }
    return null;
  }

  int _shortestTravelSeconds(
    BiomeParcelGraph graph,
    String fromParcelId,
    String toParcelId,
  ) {
    if (fromParcelId == toParcelId) return 0;
    final distances = <String, int>{fromParcelId: 0};
    final remaining = graph.parcels.map((parcel) => parcel.id).toSet();
    while (remaining.isNotEmpty) {
      final current = remaining.where(distances.containsKey).fold<String?>(
          null,
          (best, id) =>
              best == null || distances[id]! < distances[best]! ? id : best);
      if (current == null) break;
      if (current == toParcelId) return distances[current]!;
      remaining.remove(current);
      for (final edge in graph.edges.where(
        (edge) => edge.fromParcelId == current || edge.toParcelId == current,
      )) {
        final next =
            edge.fromParcelId == current ? edge.toParcelId : edge.fromParcelId;
        final candidate = distances[current]! +
            lisiereV2Config.travelSeconds(edge.difficulty);
        if (candidate < (distances[next] ?? 1 << 30)) {
          distances[next] = candidate;
        }
      }
    }
    return lisiereV2Config.hardTravelSeconds;
  }

  int _regionalTravelSeconds(
    LisiereV2Snapshot snapshot,
    String fromBiomeId,
    String toBiomeId,
  ) {
    if (fromBiomeId == toBiomeId) return 0;
    final distances = <String, int>{fromBiomeId: 0};
    final pending = <String>[fromBiomeId];
    while (pending.isNotEmpty) {
      final current = pending.removeAt(0);
      final currentDistance = distances[current]!;
      for (final next
          in snapshot.biomeConnections[current] ?? const <String>[]) {
        if (!snapshot.graphs.containsKey(next)) continue;
        final candidate = currentDistance + lisiereV2Config.hardTravelSeconds;
        if (candidate >= (distances[next] ?? 1 << 30)) continue;
        if (next == toBiomeId) return candidate;
        distances[next] = candidate;
        pending.add(next);
      }
    }
    throw StateError('Aucune passerelle régionale ne relie ces deux biomes.');
  }

  Duration _plannedTravel(
    LisiereV2Snapshot snapshot,
    LisiereTeam team,
    List<String> targets,
  ) {
    if (targets.isEmpty) return Duration.zero;
    var seconds = 0;
    var current = team.currentParcelId;
    for (final target in targets) {
      final targetBiome = _biomeForParcel(snapshot, target);
      final currentBiome =
          current == null ? targetBiome : _biomeForParcel(snapshot, current);
      if (current != null &&
          currentBiome == targetBiome &&
          targetBiome != null) {
        seconds += _shortestTravelSeconds(
          snapshot.graphs[targetBiome]!,
          current,
          target,
        );
      } else if (current != null && currentBiome != targetBiome) {
        if (currentBiome == null || targetBiome == null) {
          throw StateError('Parcelle de départ ou d’arrivée introuvable.');
        }
        seconds += _regionalTravelSeconds(snapshot, currentBiome, targetBiome);
      } else {
        seconds += lisiereV2Config.easyTravelSeconds;
      }
      current = target;
    }
    if (current != null) {
      seconds += lisiereV2Config.easyTravelSeconds;
    }
    return Duration(seconds: seconds);
  }

  /// Read-only preview used by the mission sheet. It shares the exact routing
  /// calculation used when the mission starts.
  Duration estimateAutonomousTravel(
    LisiereV2Snapshot snapshot,
    LisiereTeam team,
    List<String> targets,
  ) =>
      _plannedTravel(snapshot, team, targets);

  void _applyEncounter(
    LisiereV2Snapshot snapshot,
    LisiereTeam team,
    LisiereEncounterResolution encounter,
    String visitId,
  ) {
    final members = team.ptipoteIds
        .map((id) => snapshot.ptipotes[id])
        .whereType<LisierePtipoteState>()
        .toList();
    if (members.isEmpty) return;
    const returnVitality = 5;
    for (final member in members) {
      member.currentVitality = encounter.vitalityAfter(
        currentVitality: member.currentVitality,
        maxVitality: member.maxVitality,
        requiredReturnVitality:
            returnVitality + lisiereV2Config.returnSafetyReserve,
      );
    }
    var loss = encounter.cargoLost(
      _cargoInventories(snapshot, team)
          .fold<int>(0, (total, inventory) => total + inventory.used),
    );
    for (final inventory in _cargoInventories(snapshot, team)) {
      for (final kind in LisiereResourceKind.values) {
        if (loss <= 0) break;
        loss -= inventory.remove(kind, loss);
      }
    }
    if (encounter.appliesToxicAffliction) {
      snapshot.pendingToxicAfflictions[visitId] = members.first.id;
    }
    for (final member in members) {
      final key = '${member.id}:${LisierePtipoteJob.patrouilleur.name}';
      final progress = snapshot.jobProgress[key];
      if (progress != null) {
        snapshot.jobProgress[key] = progress.recordPatrolEncounter();
      }
    }
  }

  String _rotationDestination(
    LisiereV2Snapshot snapshot,
    LisiereTeam team,
  ) {
    final teamBiome = team.currentParcelId == null
        ? null
        : _biomeForParcel(snapshot, team.currentParcelId!);
    final preferred = snapshot.outposts.values.where(
      (outpost) =>
          (teamBiome == null || outpost.biomeId == teamBiome) &&
          (snapshot.inventories[outpost.storageId]?.remainingCapacity ?? 0) > 0,
    );
    return preferred.firstOrNull?.storageId ?? 'camp-storage-v2';
  }

  void _scheduleRotation(
    LisiereV2Snapshot snapshot,
    LisiereTeam team,
    String carrierId,
    String sourceInventoryId,
    DateTime now,
  ) {
    if (team.unavailableCarrierIds.contains(carrierId) ||
        snapshot.rotations.values.any((rotation) =>
            rotation.carrierId == carrierId &&
            rotation.state != LisiereCargoRotationState.completed &&
            rotation.state != LisiereCargoRotationState.blocked)) {
      return;
    }
    final source = snapshot.inventories[sourceInventoryId];
    if (source == null || source.used == 0) return;
    final destination = _rotationDestination(snapshot, team);
    if ((snapshot.inventories[destination]?.remainingCapacity ?? 0) <= 0) {
      return;
    }
    final travel = team.currentParcelId == null
        ? Duration.zero
        : Duration(seconds: lisiereV2Config.easyTravelSeconds);
    final id = 'rotation-$carrierId-${now.microsecondsSinceEpoch}';
    snapshot.rotations[id] = LisiereCargoRotation(
      id: id,
      carrierId: carrierId,
      teamId: team.id,
      originInventoryId: sourceInventoryId,
      destinationInventoryId: destination,
      startedAt: now,
      travelDuration: travel,
      state: LisiereCargoRotationState.travelingToOutpost,
    );
    team.unavailableCarrierIds.add(carrierId);
  }

  void _resolveRotation(
    LisiereV2Snapshot snapshot,
    LisiereCargoRotation rotation,
    DateTime now,
  ) {
    if (rotation.state == LisiereCargoRotationState.completed ||
        rotation.state == LisiereCargoRotationState.blocked) {
      return;
    }
    final outboundEnds = rotation.startedAt.add(rotation.travelDuration);
    if (now.isBefore(outboundEnds)) {
      rotation.state = LisiereCargoRotationState.travelingToOutpost;
      return;
    }
    final source = snapshot.inventories[rotation.originInventoryId];
    final destination = snapshot.inventories[rotation.destinationInventoryId];
    if (source == null || destination == null) {
      rotation.state = LisiereCargoRotationState.blocked;
      return;
    }
    for (final kind in LisiereResourceKind.values) {
      final moved = destination.add(kind, source.amounts[kind] ?? 0);
      source.remove(kind, moved);
    }
    if (rotation.destinationInventoryId == 'camp-storage-v2') {
      snapshot.starterMission.refreshFromCamp(destination, now);
    }
    if (source.used > 0) {
      rotation.state = LisiereCargoRotationState.blocked;
      return;
    }
    final returnsAt = outboundEnds.add(rotation.travelDuration);
    if (now.isBefore(returnsAt)) {
      rotation.state = LisiereCargoRotationState.returning;
      return;
    }
    rotation.state = LisiereCargoRotationState.completed;
    final team =
        rotation.teamId == null ? null : snapshot.teams[rotation.teamId];
    team?.unavailableCarrierIds.remove(rotation.carrierId);
  }

  /// Links real figurines once, preserving their V2 expedition vitality after
  /// that point. A physical scan only refreshes the presentation/stat source,
  /// never the cargo or state of an active mission.
  Future<LisiereV2Snapshot> linkPtipotes(
    Iterable<LisierePtipoteState> ptipotes,
  ) =>
      _mutate((snapshot) {
        for (final ptipote in ptipotes) {
          final existing = snapshot.ptipotes[ptipote.id];
          if (existing == null) {
            snapshot.ptipotes[ptipote.id] = ptipote;
          } else {
            // Presentation and equipment-derived stats are refreshed from the
            // real figurine, but expedition vitality remains V2-owned.
            snapshot.ptipotes[ptipote.id] = LisierePtipoteState(
              id: ptipote.id,
              displayName: ptipote.displayName,
              currentVitality: existing.currentVitality
                  .clamp(
                    0,
                    ptipote.maxVitality,
                  )
                  .toInt(),
              maxVitality: ptipote.maxVitality,
              carryCapacity: ptipote.carryCapacity,
              harvestPower: ptipote.harvestPower,
              actionFrequency: ptipote.actionFrequency,
              yieldModifier: ptipote.yieldModifier,
              organicYieldModifier: ptipote.organicYieldModifier,
              mineralYieldModifier: ptipote.mineralYieldModifier,
              wasteYieldModifier: ptipote.wasteYieldModifier,
              security: ptipote.security,
            );
          }
        }
      });

  /// The detailed projection keeps its own encounter history, while the
  /// territorial danger value is copied from the server-owned Biome state.
  Future<LisiereV2Snapshot> syncSharedBiomeDanger(
    Map<String, int> dangerByBiome,
  ) =>
      _mutate((snapshot) {
        for (final entry in dangerByBiome.entries) {
          final danger = snapshot.dangers[entry.key];
          if (danger != null) {
            danger.danger = entry.value.clamp(0, danger.dangerCap).toInt();
          }
        }
      });

  Future<LisiereV2Snapshot> assignJob({
    required String ptipoteId,
    required LisierePtipoteJob job,
  }) =>
      _mutate((snapshot) {
        if (!snapshot.ptipotes.containsKey(ptipoteId)) {
          throw StateError('P’TIPOTE non relié à la Lisière.');
        }
        final key = '$ptipoteId:${job.name}';
        snapshot.jobProgress.putIfAbsent(
          key,
          () => LisiereJobProgress(ptipoteId: ptipoteId, job: job),
        );
      });

  /// Only a V2 runtime link is stored here. It can be created from an existing
  /// V1 collection P’TIBUG without moving V1 stocks or modifying V1 saves.
  Future<LisiereV2Snapshot> linkPTibugs(
    Iterable<LisierePTibugState> ptibugs,
  ) =>
      _mutate((snapshot) {
        for (final ptibug in ptibugs) {
          final existing = snapshot.ptibugs[ptibug.id];
          snapshot.ptibugs[ptibug.id] = existing == null
              ? ptibug
              : LisierePTibugState(
                  id: ptibug.id,
                  displayName: ptibug.displayName,
                  capacity: ptibug.capacity,
                  speciesId: ptibug.speciesId,
                  traitDefinitionIds: ptibug.traitDefinitionIds,
                  currentVitality: existing.currentVitality
                      .clamp(
                        0,
                        ptibug.maxVitality,
                      )
                      .toInt(),
                  maxVitality: ptibug.maxVitality,
                  maintenance: existing.maintenance,
                );
        }
      });

  Future<LisiereV2Snapshot> createTeam({
    required String teamId,
    required List<String> ptipoteIds,
    List<String> ptibugIds = const <String>[],
    bool hasTeamManagementStructure = false,
    int logisticsOptimizationModules = 0,
  }) =>
      _mutate((snapshot) {
        if (ptipoteIds.isEmpty) {
          throw StateError('Une équipe doit avoir un P’TIPOTE.');
        }
        if (ptipoteIds.toSet().length != ptipoteIds.length ||
            ptipoteIds.any((id) => !snapshot.ptipotes.containsKey(id))) {
          throw StateError('Sélection de P’TIPOTES invalide.');
        }
        final capacity = teamCapacity(
          hasTeamManagementStructure: hasTeamManagementStructure,
          logisticsOptimizationModules: logisticsOptimizationModules,
        );
        if (ptipoteIds.length + ptibugIds.length > capacity) {
          throw StateError('Capacité d’équipe dépassée ($capacity).');
        }
        if (ptibugIds.any((id) => !snapshot.ptibugs.containsKey(id))) {
          throw StateError('P’TIBUG non relié à la Lisière.');
        }
        final inventoryId = 'team-$teamId-field';
        snapshot.inventories.putIfAbsent(
          inventoryId,
          () => LisiereFieldInventory(id: inventoryId, capacity: 80),
        );
        for (final ptipoteId in ptipoteIds) {
          final ptipote = snapshot.ptipotes[ptipoteId]!;
          snapshot.inventories.putIfAbsent(
            'ptipote-$ptipoteId-cargo',
            () => LisiereFieldInventory(
              id: 'ptipote-$ptipoteId-cargo',
              capacity: ptipote.carryCapacity,
              maxStacks: 2,
            ),
          );
        }
        for (final ptibugId in ptibugIds) {
          final ptibug = snapshot.ptibugs[ptibugId]!;
          snapshot.inventories.putIfAbsent(
            'ptibug-$ptibugId-cargo',
            () => LisiereFieldInventory(
              id: 'ptibug-$ptibugId-cargo',
              capacity: ptibug.capacity,
            ),
          );
        }
        snapshot.teams[teamId] = LisiereTeam(
          id: teamId,
          ptipoteIds: List<String>.from(ptipoteIds),
          ptibugIds: List<String>.from(ptibugIds),
          fieldInventoryId: inventoryId,
          hasTeamManagementStructure: hasTeamManagementStructure,
          logisticsOptimizationModules: logisticsOptimizationModules,
        );
      });

  Future<LisiereV2Snapshot> buildOutpost({
    required String biomeId,
    String? parcelId,
  }) =>
      _mutate((snapshot) {
        if (!snapshot.graphs.containsKey(biomeId)) {
          throw StateError('Biome inconnu.');
        }
        if (snapshot.outposts.values.any((item) => item.biomeId == biomeId)) {
          throw StateError('Un avant-poste existe déjà dans ce biome.');
        }
        final id = 'outpost-$biomeId';
        final storageId = '$id-storage';
        snapshot.inventories[storageId] =
            LisiereFieldInventory(id: storageId, capacity: 180);
        snapshot.outposts[id] = OutpostInstance(
          id: id,
          biomeId: biomeId,
          parcelId: parcelId,
          storageId: storageId,
          state: 'active',
        );
      });

  /// Accompanied movement is immediate, like a small RTS: the selected team
  /// walks to a connected target while the app is active. Autonomous missions
  /// keep using the timestamp resolver and travel edges separately.
  Future<LisiereV2Snapshot> moveAccompaniedTeam({
    required String teamId,
    required String targetParcelId,
  }) =>
      _mutate((snapshot) {
        final team = snapshot.teams[teamId];
        final target = snapshot.graphs.values
            .expand((graph) => graph.parcels)
            .where((parcel) => parcel.id == targetParcelId)
            .firstOrNull;
        if (team == null || target == null) {
          throw StateError('Équipe ou parcelle introuvable.');
        }
        // The graph is connected. The visual prototype lets the team find its
        // path automatically to the clicked target; exact path timing remains
        // part of the autonomous resolver.
        team.currentParcelId = targetParcelId;
      });

  Future<LisiereV2Snapshot> startAutonomousMission({
    required String missionId,
    required String teamId,
    required List<String> targetParcelIds,
    required LisiereMissionDuration duration,
    LisiereHarvestRegime regime = LisiereHarvestRegime.normal,
    required DateTime startedAt,
  }) =>
      _mutate((snapshot) {
        final team = snapshot.teams[teamId];
        if (team == null) throw StateError('Équipe introuvable.');
        if (snapshot.missions.values.any((mission) =>
            mission.teamId == teamId &&
            mission.status != LisiereMissionStatus.completed &&
            mission.status != LisiereMissionStatus.cancelled)) {
          throw StateError('Cette équipe est déjà en mission.');
        }
        if (targetParcelIds.isEmpty ||
            targetParcelIds.any((id) =>
                !snapshot.nodes.values.any((node) => node.parcelId == id))) {
          throw StateError('Cible de mission invalide.');
        }
        final eligible = team.ptipoteIds.any((id) {
          final progress =
              snapshot.jobProgress['$id:${LisierePtipoteJob.recolteur.name}'];
          return progress != null &&
              canStartAutonomousHarvest(
                recolteur: progress,
                targetParcelIds: targetParcelIds,
              );
        });
        if (!eligible) {
          throw StateError(
              'Un Récolteur N1 est requis pour une mission autonome.');
        }
        final route = List<String>.from(targetParcelIds);
        final travel = _plannedTravel(snapshot, team, route);
        if (travel >= duration.duration) {
          throw StateError(
            'Cette durée ne couvre pas le trajet aller-retour. Choisis une mission plus longue.',
          );
        }
        snapshot.missions[missionId] = LisiereMissionInstance(
          id: missionId,
          teamId: teamId,
          originId: 'camp-storage-v2',
          plannedDuration: duration.duration,
          startedAt: startedAt,
          routeParcelIds: route,
          targetParcelIds: route,
          randomSeed: lisiereStableSeed(missionId),
          travelDuration: travel,
          routeBiomeIds: route
              .map((id) => _biomeForParcel(snapshot, id))
              .whereType<String>()
              .toSet()
              .toList(),
          regime: regime,
          status: LisiereMissionStatus.traveling,
        );
      });

  /// Runs elapsed work from timestamps. This routine is idempotent because a
  /// mission advances from `lastResolvedAt` only once within its transaction.
  Future<LisiereV2Snapshot> resolveAutonomousMissions(DateTime now) =>
      _mutate((snapshot) {
        for (final danger in snapshot.dangers.values) {
          danger.resolveNaturalIncrease(now);
        }
        for (final rotation in snapshot.rotations.values) {
          _resolveRotation(snapshot, rotation, now);
        }
        for (final mission in snapshot.missions.values) {
          if (mission.status == LisiereMissionStatus.completed ||
              mission.status == LisiereMissionStatus.cancelled ||
              !now.isAfter(mission.lastResolvedAt)) {
            continue;
          }
          final team = snapshot.teams[mission.teamId];
          if (team == null || team.ptipoteIds.isEmpty) {
            mission.status = LisiereMissionStatus.blocked;
            continue;
          }
          final legacyInventory = snapshot.inventories[team.fieldInventoryId];
          if (legacyInventory == null) {
            mission.status = LisiereMissionStatus.blocked;
            continue;
          }
          final members = team.ptipoteIds
              .map((id) => snapshot.ptipotes[id])
              .whereType<LisierePtipoteState>()
              .toList();
          if (members.isEmpty) {
            mission.status = LisiereMissionStatus.blocked;
            continue;
          }
          final actor = members.firstWhere(
            (item) =>
                snapshot
                    .jobProgress[
                        '${item.id}:${LisierePtipoteJob.recolteur.name}']
                    ?.level ==
                LisiereJobLevel.n1,
            orElse: () => members.first,
          );
          final bounded =
              now.isAfter(mission.plannedEndAt) ? mission.plannedEndAt : now;
          final workUntil = bounded.isAfter(mission.returnStartsAt)
              ? mission.returnStartsAt
              : bounded;
          final workFrom = mission.lastResolvedAt.isAfter(mission.workStartsAt)
              ? mission.lastResolvedAt
              : mission.workStartsAt;
          final elapsed = workUntil.isAfter(workFrom)
              ? workUntil.difference(workFrom)
              : Duration.zero;
          final targets = snapshot.nodes.values
              .where((node) => mission.targetParcelIds.contains(node.parcelId))
              .toList();
          final cargoInventories =
              _cargoInventories(snapshot, team, availableOnly: true);
          final activeCargo = cargoInventories.firstOrNull ?? legacyInventory;
          var mustReturn = false;
          for (final biomeId in mission.routeBiomeIds) {
            final entryId = '${mission.id}:$biomeId';
            if (!mission.resolvedBiomeEntryIds.add(entryId)) continue;
            final danger = snapshot.dangers[biomeId];
            if (danger == null) continue;
            final security = _groupSecurity(snapshot, team);
            if (danger.bossDroneActive) {
              final outcome =
                  resolveAutonomousBossDrone(groupSecurity: security);
              danger.lastBossDroneOutcome = outcome.name;
              if (outcome == BossDroneOutcome.neutralized) {
                danger.bossDroneActive = false;
              } else {
                _applyEncounter(
                  snapshot,
                  team,
                  defaultLisiereEncounterResolutions[
                      LisiereEncounterType.standardDrone]!,
                  '$entryId:boss',
                );
                mustReturn = true;
                break;
              }
            }
            final encounter = resolveBiomeEntryEncounter(
              visitId: entryId,
              randomSeed: mission.randomSeed,
              biomeDanger: danger.danger,
              groupSecurity: security,
              resolvedVisitIds: snapshot.resolvedVisitIds,
            );
            if (encounter != null) {
              _applyEncounter(snapshot, team, encounter, entryId);
            }
          }
          if (!mustReturn && elapsed > Duration.zero) {
            final activeBugCount = team.ptibugIds
                .map((id) => snapshot.ptibugs[id])
                .whereType<LisierePTibugState>()
                .where((bug) => !bug.maintenance.isSleeping)
                .length;
            final workPerActor = Duration(
              milliseconds: elapsed.inMilliseconds ~/ (1 + activeBugCount),
            );
            final ptipoteResult = resolveAutonomousHarvest(
              elapsedWork: workPerActor,
              targetNodes: targets,
              inventory: activeCargo,
              inventories: cargoInventories.isEmpty
                  ? <LisiereFieldInventory>[legacyInventory]
                  : cargoInventories,
              actor: actor.harvestActor,
              regime: mission.regime,
              baseActionVitalityCost: 1,
              returnVitalityCost: 5,
            );
            actor.currentVitality = ptipoteResult.finalVitality;
            mustReturn = ptipoteResult.stoppedForReturnReserve ||
                ptipoteResult.stoppedForCapacity;
            for (final bugId in team.ptibugIds) {
              final bug = snapshot.ptibugs[bugId];
              if (bug == null || bug.maintenance.isSleeping) continue;
              final preferred = <LisiereResourceNode>[
                ...targets.where(
                    (node) => bug.preferredResources.contains(node.kind)),
                ...targets.where(
                    (node) => !bug.preferredResources.contains(node.kind)),
              ];
              final preferredKind = preferred.isEmpty
                  ? LisiereResourceKind.organic
                  : preferred.first.kind;
              final result = resolveAutonomousHarvest(
                elapsedWork: workPerActor,
                targetNodes: preferred,
                inventory: activeCargo,
                inventories: cargoInventories.isEmpty
                    ? <LisiereFieldInventory>[legacyInventory]
                    : cargoInventories,
                actor: LisiereHarvestActor(
                  id: bug.id,
                  harvestPower: 1,
                  actionFrequency: 1,
                  yieldModifier: bug.yieldModifierFor(preferredKind),
                  maxVitality: bug.maxVitality,
                  currentVitality: bug.currentVitality,
                ),
                regime: mission.regime,
                baseActionVitalityCost: 1,
                returnVitalityCost: 5,
              );
              bug.currentVitality = result.finalVitality;
              mustReturn = mustReturn ||
                  result.stoppedForReturnReserve ||
                  result.stoppedForCapacity;
            }
            for (final biomeId in mission.routeBiomeIds) {
              snapshot.dangers[biomeId]?.markExploited(mission.id);
              mission.workedBiomeIds.add(biomeId);
            }
            for (final carrierId in team.ptibugIds) {
              final inventoryId = snapshot.ptibugs.containsKey(carrierId)
                  ? 'ptibug-$carrierId-cargo'
                  : 'ptipote-$carrierId-cargo';
              final cargo = snapshot.inventories[inventoryId];
              if (cargo != null && cargo.remainingCapacity == 0) {
                _scheduleRotation(snapshot, team, carrierId, inventoryId, now);
              }
            }
          }
          mission.resolveUntil(bounded);
          mission.status = mustReturn
              ? LisiereMissionStatus.returning
              : mission.stageAt(bounded);
          if (bounded == mission.plannedEndAt) {
            mission.status = LisiereMissionStatus.depositing;
            for (final carrierId in <String>[
              ...team.ptibugIds,
              ...team.ptipoteIds,
            ]) {
              final sourceId = snapshot.ptibugs.containsKey(carrierId)
                  ? 'ptibug-$carrierId-cargo'
                  : 'ptipote-$carrierId-cargo';
              _scheduleRotation(snapshot, team, carrierId, sourceId, bounded);
            }
          }
        }
      });

  Future<LisiereV2Snapshot> advanceRotation(String rotationId) =>
      _mutate((snapshot) {
        final rotation = snapshot.rotations[rotationId];
        if (rotation == null) throw StateError('Rotation introuvable.');
        _resolveRotation(snapshot, rotation, DateTime.now());
      });

  Future<LisiereV2Snapshot> startReturnRotation({
    required String teamId,
    String destinationInventoryId = 'camp-storage-v2',
  }) =>
      _mutate((snapshot) {
        final team = snapshot.teams[teamId];
        if (team == null ||
            !snapshot.inventories.containsKey(destinationInventoryId)) {
          throw StateError('Équipe ou stockage de destination introuvable.');
        }
        final carrierIds = <String>[
          ...team.ptibugIds,
          ...team.ptipoteIds,
        ];
        for (final carrierId in carrierIds) {
          final sourceId = snapshot.ptibugs.containsKey(carrierId)
              ? 'ptibug-$carrierId-cargo'
              : 'ptipote-$carrierId-cargo';
          final source = snapshot.inventories[sourceId];
          if (source == null || source.used == 0) continue;
          _scheduleRotation(
            snapshot,
            team,
            carrierId,
            sourceId,
            DateTime.now(),
          );
          return;
        }
        throw StateError('Aucune cargaison à ramener.');
      });

  Future<LisiereV2Snapshot> resolvePTibugMaintenance(DateTime now) =>
      _mutate((snapshot) {
        for (final ptibug in snapshot.ptibugs.values) {
          final requestedRation = now.isAfter(ptibug.maintenance.lastResolvedAt)
              ? now
                      .difference(ptibug.maintenance.lastResolvedAt)
                      .inMilliseconds /
                  const Duration(days: 1).inMilliseconds *
                  ptibug.maintenance.dailyRation
              : 0.0;
          final paidRation = ptibug.maintenance.resolveMaintenanceUntil(now);
          if (paidRation + .0001 < requestedRation) {
            ptibug.maintenance.startSleep(
              now: now,
              duration: const Duration(hours: 12),
            );
          }
        }
      });

  Future<LisiereV2Snapshot> acknowledgeToxicAffliction(String visitId) =>
      _mutate((snapshot) {
        snapshot.pendingToxicAfflictions.remove(visitId);
      });

  Future<LisiereV2Snapshot> resolveBossDrone({
    required String biomeId,
    required String teamId,
    required bool accompaniedQteSucceeded,
  }) =>
      _mutate((snapshot) {
        final danger = snapshot.dangers[biomeId];
        final team = snapshot.teams[teamId];
        if (danger == null || team == null) {
          throw StateError('Biome ou équipe introuvable.');
        }
        danger.bossDroneActive = true;
        final members = team.ptipoteIds
            .map((id) => snapshot.ptipotes[id])
            .whereType<LisierePtipoteState>()
            .toList();
        final security = members.isEmpty
            ? 0.0
            : members.fold<double>(0, (total, item) => total + item.security) /
                members.length;
        final outcome = accompaniedQteSucceeded && security >= 50
            ? BossDroneOutcome.neutralized
            : BossDroneOutcome.interrupted;
        danger.lastBossDroneOutcome = outcome.name;
        if (outcome == BossDroneOutcome.neutralized) {
          danger.bossDroneActive = false;
          danger.danger = (danger.danger - 25).clamp(0, danger.dangerCap);
        }
        if (outcome == BossDroneOutcome.interrupted && members.isNotEmpty) {
          final affected = members.first;
          const drone = LisiereEncounterResolution(
            type: LisiereEncounterType.standardDrone,
            cargoLossPercent: .25,
            vitalityLossPercent: .15,
            appliesToxicAffliction: false,
          );
          affected.currentVitality = drone.vitalityAfter(
            currentVitality: affected.currentVitality,
            maxVitality: affected.maxVitality,
            requiredReturnVitality: 5 + lisiereV2Config.returnSafetyReserve,
          );
          final fieldInventory = snapshot.inventories[team.fieldInventoryId];
          var loss = drone.cargoLost(fieldInventory?.used ?? 0);
          if (fieldInventory != null) {
            for (final resource in LisiereResourceKind.values) {
              if (loss <= 0) break;
              loss -= fieldInventory.remove(resource, loss);
            }
          }
          for (final mission in snapshot.missions.values) {
            if (mission.teamId == teamId &&
                mission.status != LisiereMissionStatus.completed) {
              mission.status = LisiereMissionStatus.returning;
            }
          }
        }
        for (final ptipote in members) {
          final key = '${ptipote.id}:${LisierePtipoteJob.patrouilleur.name}';
          final patrol = snapshot.jobProgress[key];
          if (patrol != null && accompaniedQteSucceeded) {
            snapshot.jobProgress[key] = patrol.recordPatrolQte();
          }
        }
      });

  Future<LisiereV2Snapshot> feedPTibug({
    required String ptibugId,
    required double ration,
  }) =>
      _mutate((snapshot) {
        final ptibug = snapshot.ptibugs[ptibugId];
        if (ptibug == null) throw StateError('P’TIBUG introuvable.');
        final camp = snapshot.inventories['camp-storage-v2'];
        final hours = ration.clamp(
          0.5,
          pTibugConfig.cultivation.targetAutonomyHours.toDouble(),
        );
        final species = PTibugSpecies.values.firstWhere(
          (value) => value.name == ptibug.speciesId,
          orElse: () => PTibugSpecies.scarabe,
        );
        // The material part of the V1 hourly cultivation cost is paid from
        // the one physical Camp stock. V1 energy remains in its own existing
        // household system rather than becoming a duplicate V2 resource.
        final organicCost =
            ((pTibugConfig.cultivation.organicPerActiveHour[species] ?? 0) *
                    hours)
                .ceil();
        final mineralCost =
            ((pTibugConfig.cultivation.mineralPerActiveHour[species] ?? 0) *
                    hours)
                .ceil();
        if (camp == null ||
            (camp.amounts[LisiereResourceKind.organic] ?? 0) < organicCost ||
            (camp.amounts[LisiereResourceKind.mineral] ?? 0) < mineralCost) {
          throw StateError(
              'Stock insuffisant : $organicCost Organique et $mineralCost Minéral requis.');
        }
        camp.remove(LisiereResourceKind.organic, organicCost);
        camp.remove(LisiereResourceKind.mineral, mineralCost);
        ptibug.maintenance.feed(
          ptibug.maintenance.dailyRation * hours / Duration.hoursPerDay,
        );
        ptibug.maintenance.sleepUntil = null;
      });

  Future<LisiereHarvestCommit> harvestWithLinkedPtipote({
    required String actionId,
    required String nodeId,
    required String inventoryId,
    required String ptipoteId,
    required bool isTraining,
    int? sharedMineralLimit,
    int? sharedOrganicLimit,
    int? sharedWasteLimit,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise pour récolter.');
    final reference = _document(user.uid);
    return _firestore.runTransaction<LisiereHarvestCommit>((transaction) async {
      final data = (await transaction.get(reference)).data();
      if (data == null) throw StateError('Lisière non initialisée.');
      final snapshot = LisiereV2Snapshot.fromMap(data);
      final actionIds = List<String>.from(
          data['harvestActionIds'] as List? ?? const <String>[]);
      if (actionIds.contains(actionId)) {
        return const LisiereHarvestCommit.duplicate();
      }
      final ptipote = snapshot.ptipotes[ptipoteId];
      final node = snapshot.nodes[nodeId];
      final requestedInventory = snapshot.inventories[inventoryId];
      if (ptipote == null || node == null || requestedInventory == null) {
        throw StateError('P’TIPOTE, ressource ou stock introuvable.');
      }
      if (isTraining &&
          !canSpendVitality(
            currentVitality: ptipote.currentVitality,
            actionCost: 1,
            returnCostFromDestination: 5,
          )) {
        throw StateError('Vitalité insuffisante pour garantir le retour.');
      }
      final toolActor = LisiereHarvestActor(
        id: ptipote.id,
        // The player tool always deals one damage per second. Training adds
        // the P’TIPOTE's own strike alongside it; it never becomes an
        // abstract harvest button.
        harvestPower: 1 + (isTraining ? ptipote.harvestPower : 0),
        actionFrequency: 1,
        yieldModifier: isTraining ? ptipote.yieldModifierFor(node.kind) : 1,
        maxVitality: ptipote.maxVitality,
        currentVitality: ptipote.currentVitality,
      );
      final team = snapshot.teams.values
          .where((item) => item.fieldInventoryId == inventoryId)
          .firstOrNull;
      final inventory = team == null
          ? requestedInventory
          : _cargoDestination(snapshot, team, node.kind);
      if (inventory == null || !inventory.canAccept(node.kind)) {
        throw StateError(
          'Cargaison pleine : cette équipe doit ramener ses matériaux.',
        );
      }
      final resolution = node.applyAction(toolActor);
      final sharedLimit = resolution.resource == LisiereResourceKind.mineral
          ? sharedMineralLimit
          : resolution.resource == LisiereResourceKind.organic
              ? sharedOrganicLimit
              : resolution.resource == LisiereResourceKind.waste
                  ? sharedWasteLimit
                  : null;
      final creditedAmount = sharedLimit == null
          ? resolution.creditedAmount
          : resolution.creditedAmount.clamp(0, sharedLimit).toInt();
      final accepted = inventory.add(
        resolution.resource,
        creditedAmount,
      );
      if (isTraining) {
        ptipote.currentVitality =
            (ptipote.currentVitality - 1).clamp(0, ptipote.maxVitality).toInt();
      }
      final key = '$ptipoteId:${LisierePtipoteJob.recolteur.name}';
      final progress = snapshot.jobProgress.putIfAbsent(
        key,
        () => LisiereJobProgress(
          ptipoteId: ptipoteId,
          job: LisierePtipoteJob.recolteur,
        ),
      );
      if (isTraining) {
        snapshot.jobProgress[key] = progress.recordHarvestAction();
      }
      snapshot.updatedAt = DateTime.now();
      transaction.set(
          reference,
          <String, dynamic>{
            ...snapshot.toMap(),
            'ownerId': user.uid,
            'harvestActionIds': <String>[...actionIds.take(199), actionId],
            'serverUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return LisiereHarvestCommit(
        resolution: creditedAmount == resolution.creditedAmount
            ? resolution
            : HarvestResolution(
                nodeId: resolution.nodeId,
                resource: resolution.resource,
                creditedAmount: creditedAmount,
                remainder: resolution.remainder,
                productiveUnitCompleted: resolution.productiveUnitCompleted,
                nodeState: resolution.nodeState,
              ),
        acceptedAmount: accepted,
        duplicate: false,
      );
    });
  }

  /// Aligns the local 2D projection with the server-authoritative Organic
  /// node after a shared harvest or an offline ecology resolution.
  Future<void> synchronizeSharedOrganicNode({
    required String nodeId,
    required double vitality,
    required String nodeState,
  }) async {
    await _mutate((snapshot) {
      final node = snapshot.nodes[nodeId];
      if (node == null || node.kind != LisiereResourceKind.organic) return;
      node.resistance = vitality.clamp(0, node.maxResistance);
      node.isDestroyed = nodeState == 'destroyed';
    });
  }

  Future<void> synchronizeSharedWasteNode({
    required String nodeId,
    required double vitality,
  }) async {
    await _mutate((snapshot) {
      final node = snapshot.nodes[nodeId];
      if (node == null || node.kind != LisiereResourceKind.waste) return;
      node.resistance = vitality.clamp(0, node.maxResistance);
      if (node.resistance <= 0) node.remainingLayers = 0;
    });
  }

  /// One deterministic visit is persisted before its UI consequence is shown.
  /// The caller applies the already-existing V1 toxic affliction once when the
  /// returned result requests it; the V2 encounter id prevents duplicate UI.
  Future<LisiereEncounterCommit?> enterBiome({
    required String visitId,
    required String biomeId,
    required String teamId,
  }) async {
    LisiereEncounterCommit? result;
    await _mutate((snapshot) {
      final danger = snapshot.dangers[biomeId];
      final team = snapshot.teams[teamId];
      if (danger == null || team == null) {
        throw StateError('Biome ou équipe introuvable.');
      }
      danger.resolveNaturalIncrease(DateTime.now());
      final members = team.ptipoteIds
          .map((id) => snapshot.ptipotes[id])
          .whereType<LisierePtipoteState>()
          .toList();
      if (members.isEmpty) {
        throw StateError('Aucun P’TIPOTE dans cette équipe.');
      }
      final security =
          members.fold<double>(0, (total, item) => total + item.security) /
              members.length;
      final encounter = resolveBiomeEntryEncounter(
        visitId: visitId,
        randomSeed: lisiereStableSeed(teamId),
        biomeDanger: danger.danger,
        groupSecurity: security,
        resolvedVisitIds: snapshot.resolvedVisitIds,
      );
      if (encounter == null) return;
      final affected = members.first;
      final returnVitality = 5 + lisiereV2Config.returnSafetyReserve;
      affected.currentVitality = encounter.vitalityAfter(
        currentVitality: affected.currentVitality,
        maxVitality: affected.maxVitality,
        requiredReturnVitality: returnVitality,
      );
      var cargoLoss = encounter.cargoLost(
        _cargoInventories(snapshot, team)
            .fold<int>(0, (total, inventory) => total + inventory.used),
      );
      for (final inventory in _cargoInventories(snapshot, team)) {
        for (final resource in LisiereResourceKind.values) {
          if (cargoLoss <= 0) break;
          cargoLoss -= inventory.remove(resource, cargoLoss);
        }
        if (cargoLoss <= 0) break;
      }
      final patrolKey = '${affected.id}:${LisierePtipoteJob.patrouilleur.name}';
      final patrol = snapshot.jobProgress[patrolKey];
      if (patrol != null) {
        snapshot.jobProgress[patrolKey] = patrol.recordPatrolEncounter();
      }
      result = LisiereEncounterCommit(
        visitId: visitId,
        ptipoteId: affected.id,
        type: encounter.type,
        appliesToxicAffliction: encounter.appliesToxicAffliction,
      );
    });
    return result;
  }

  /// Resolves one manual harvest and its job progression in one transaction.
  /// A full terrain stock commits the action but accepts no resource, which is
  /// explicit in the result and never duplicates an item into the Camp stock.
  Future<LisiereHarvestCommit> harvest({
    required String actionId,
    required String nodeId,
    required String inventoryId,
    required LisiereHarvestActor actor,
    required LisiereJobProgress progress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise pour récolter.');
    final reference = _document(user.uid);
    return _firestore.runTransaction<LisiereHarvestCommit>((transaction) async {
      final data = (await transaction.get(reference)).data();
      if (data == null) throw StateError('Lisière non initialisée.');
      final snapshot = LisiereV2Snapshot.fromMap(data);
      final node = snapshot.nodes[nodeId];
      final inventory = snapshot.inventories[inventoryId];
      if (node == null || inventory == null) {
        throw StateError('Ressource ou stock introuvable.');
      }
      final existingActionIds = List<String>.from(
        data['harvestActionIds'] as List? ?? const <String>[],
      );
      if (existingActionIds.contains(actionId)) {
        return const LisiereHarvestCommit.duplicate();
      }
      final resolution = node.applyAction(actor);
      final accepted =
          inventory.add(resolution.resource, resolution.creditedAmount);
      snapshot.jobProgress['${progress.ptipoteId}:${progress.job.name}'] =
          progress.recordHarvestAction();
      snapshot.updatedAt = DateTime.now();
      transaction.set(
          reference,
          <String, dynamic>{
            ...snapshot.toMap(),
            'ownerId': user.uid,
            // Keep a bounded durable id list, enough for client retry protection.
            'harvestActionIds': <String>[
              ...existingActionIds.take(199),
              actionId
            ],
            'serverUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return LisiereHarvestCommit(
        resolution: resolution,
        acceptedAmount: accepted,
        duplicate: false,
      );
    });
  }
}

class LisiereHarvestCommit {
  const LisiereHarvestCommit({
    required this.resolution,
    required this.acceptedAmount,
    required this.duplicate,
  });

  const LisiereHarvestCommit.duplicate()
      : resolution = null,
        acceptedAmount = 0,
        duplicate = true;

  final HarvestResolution? resolution;
  final int acceptedAmount;
  final bool duplicate;
}

class LisiereEncounterCommit {
  const LisiereEncounterCommit({
    required this.visitId,
    required this.ptipoteId,
    required this.type,
    required this.appliesToxicAffliction,
  });

  final String visitId;
  final String ptipoteId;
  final LisiereEncounterType type;
  final bool appliesToxicAffliction;
}
