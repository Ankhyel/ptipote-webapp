import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'zone0_v2_foundation.dart';
import '../figurines/ptipote_v2.dart';
import 'lisiere_v2.dart';
import 'worldcraft_v2_service.dart';

/// Persists only the V2 world foundation. V1 gameplay remains untouched in
/// `users/{uid}/game/zone0`; identities and social documents are never reset.
class Zone0V2FoundationService {
  Zone0V2FoundationService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _document(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('game')
      .doc('zone0V2Foundation');

  DocumentReference<Map<String, dynamic>> _lisiereDocument(String uid) =>
      _firestore.collection('users').doc(uid).collection('game').doc(
            'zone0V2Lisiere',
          );

  Future<Map<String, dynamic>?> load() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return (await _document(user.uid).get()).data();
  }

  /// Stores the common P'TIPOTE profile while onboarding is unfinished. This
  /// is a V2-only draft: NFC identity documents and V1 progress are untouched.
  Future<void> saveOnboardingPtipote({
    required PtipoteV2Profile profile,
    required Zone0V2WorldStage stage,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour enregistrer la Couveuse.');
    }
    await _document(user.uid).set(<String, dynamic>{
      'worldVersion': zone0V2WorldVersion,
      'ownerId': user.uid,
      'stage': stage.name,
      'firstPtipoteId': profile.ptipoteId,
      'onboardingPtipote': profile.toFirebase(),
      'ptipotes': <String, dynamic>{profile.ptipoteId: profile.toFirebase()},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stores only the player's personal relationship to a Worldcraft Camp.
  /// Region, Camp and Biomes themselves are global documents created by the
  /// server. This is safe to retry after the DEV region selector closes.
  Future<void> saveWorldcraftCampSelection({
    required RegionQuestionnaireResult questionnaire,
    required PtipoteV2Profile firstPtipote,
    required String worldId,
    required String regionId,
    required String campId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise pour choisir le Camp.');
    await _document(user.uid).set(<String, dynamic>{
      'worldVersion': zone0V2WorldVersion,
      'stage': Zone0V2WorldStage.ready.name,
      'ownerId': user.uid,
      'firstPtipoteId': firstPtipote.ptipoteId,
      'onboardingPtipote': firstPtipote.toFirebase(),
      'ptipotes': <String, dynamic>{
        firstPtipote.ptipoteId: firstPtipote.toFirebase(),
      },
      'questionnaire': questionnaire.toMap(),
      'worldcraft': <String, dynamic>{
        'worldId': worldId,
        'regionId': regionId,
        'campId': campId,
        'selectedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveWorldcraftQuestionnaire({
    required PtipoteV2Profile profile,
    required RegionQuestionnaireResult questionnaire,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise pour enregistrer le questionnaire.');
    await _document(user.uid).set(<String, dynamic>{
      'worldVersion': zone0V2WorldVersion,
      'stage': Zone0V2WorldStage.questionnaire.name,
      'ownerId': user.uid,
      'firstPtipoteId': profile.ptipoteId,
      'onboardingPtipote': profile.toFirebase(),
      'ptipotes': <String, dynamic>{profile.ptipoteId: profile.toFirebase()},
      'questionnaire': questionnaire.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Creates a Region, Camp, Core, Maison, Kernel and Camp storage exactly
  /// once. Retrying after an app interruption returns the existing document.
  Future<Map<String, dynamic>> ensureZone0V2Foundation({
    required RegionQuestionnaireResult questionnaire,
    PtipoteV2Profile? firstPtipote,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise pour créer le Camp.');
    final reference = _document(user.uid);
    return _firestore.runTransaction<Map<String, dynamic>>((transaction) async {
      final snapshot = await transaction.get(reference);
      final existing = snapshot.data();
      if (existing != null &&
          existing['camp'] is Map &&
          existing['region'] is Map) {
        if (existing['residents'] is! List) {
          final now = DateTime.now();
          transaction.set(
              reference,
              <String, dynamic>{
                'residents': <Map<String, dynamic>>[
                  _resident('resident-v2-1', 'camp-v2', now,
                      _stableSeed('${user.uid}:residents')),
                  _resident('resident-v2-2', 'camp-v2', now,
                      _stableSeed('${user.uid}:residents')),
                  _resident('resident-v2-3', 'camp-v2', now,
                      _stableSeed('${user.uid}:residents')),
                ],
                'firstResidentHook': <String, dynamic>{
                  'status': 'arrived',
                  'campId': 'camp-v2',
                  'createdAt': now.millisecondsSinceEpoch,
                },
              },
              SetOptions(merge: true));
        }
        if (firstPtipote != null) {
          transaction.set(
              reference,
              <String, dynamic>{
                'stage': Zone0V2WorldStage.ready.name,
                'firstPtipoteId': firstPtipote.ptipoteId,
                'onboardingPtipote': firstPtipote.toFirebase(),
                'ptipotes': <String, dynamic>{
                  firstPtipote.ptipoteId: firstPtipote.toFirebase(),
                },
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        }
        return existing;
      }
      final createdAt = questionnaire.completedAt;
      final seed = _stableSeed(
          '${user.uid}:${questionnaire.selectedRegionPresetId.name}');
      const regionId = 'region-v2';
      const campId = 'camp-v2';
      final biomes = createRegionBiomeInstances(
        regionId: regionId,
        presetId: questionnaire.selectedRegionPresetId,
        seed: seed,
        createdAt: createdAt,
      );
      final created = <String, dynamic>{
        'worldVersion': zone0V2WorldVersion,
        'stage': Zone0V2WorldStage.ready.name,
        'ownerId': user.uid,
        'firstPtipoteId': firstPtipote?.ptipoteId,
        'onboardingPtipote': firstPtipote?.toFirebase(),
        'ptipotes': firstPtipote == null
            ? <String, dynamic>{}
            : <String, dynamic>{
                firstPtipote.ptipoteId: firstPtipote.toFirebase(),
              },
        'createdAt': createdAt.millisecondsSinceEpoch,
        'questionnaire': questionnaire.toMap(),
        'region': <String, dynamic>{
          'id': regionId,
          'ownerId': user.uid,
          'presetId': questionnaire.selectedRegionPresetId.name,
          'createdAt': createdAt.millisecondsSinceEpoch,
          'seed': seed,
          'campId': campId,
          'biomeIds': biomes.map((biome) => biome.id).toList(),
          'questionnaireResultId': 'region-questionnaire-v1',
          'worldVersion': zone0V2WorldVersion,
        },
        'biomes': biomes.map((biome) => biome.toMap()).toList(),
        'camp': <String, dynamic>{
          'id': campId,
          'regionId': regionId,
          'ownerId': user.uid,
          'createdAt': createdAt.millisecondsSinceEpoch,
          'coreId': 'camp-core-v2',
          'buildingIds': <String>['house-v2', 'kernel-v2'],
          'storageId': 'camp-storage-v2',
          'progressionState': 'foundation',
          'worldVersion': zone0V2WorldVersion,
        },
        'core': <String, dynamic>{
          'id': 'camp-core-v2',
          'campId': campId,
          'state': 'active',
          'progressionTier': 0,
          'createdAt': createdAt.millisecondsSinceEpoch,
        },
        'buildings': <String, dynamic>{
          'house-v2': _building(
              'house-v2', campId, Zone0V2BuildingType.house, createdAt),
          'kernel-v2': _building(
              'kernel-v2', campId, Zone0V2BuildingType.kernel, createdAt),
        },
        'residents': <Map<String, dynamic>>[
          _resident('resident-v2-1', campId, createdAt, seed),
          _resident('resident-v2-2', campId, createdAt, seed),
          _resident('resident-v2-3', campId, createdAt, seed),
        ],
        'campStorage': <String, dynamic>{
          'id': 'camp-storage-v2',
          'campId': campId,
          // The actual stacks live in the physical Lisière inventory with
          // this id. Keeping only the reference prevents a duplicate Camp
          // stock from becoming a second source of truth.
          'physicalInventoryId': 'camp-storage-v2',
          'createdAt': createdAt.millisecondsSinceEpoch,
        },
        'firstResidentHook': <String, dynamic>{
          'status': 'arrived',
          'campId': campId,
          'createdAt': createdAt.millisecondsSinceEpoch,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.set(reference, created);
      return created;
    });
  }

  /// Dev-only reset scope: gameplay foundation only. NFC figurines and all
  /// social data intentionally remain outside this document.
  Future<void> resetZone0V2Dev() async {
    final user = _auth.currentUser;
    if (user == null) return;
    // Only V2 gameplay documents are reset. Figurine identity, NFC and social
    // data live elsewhere and are intentionally never touched.
    final batch = _firestore.batch();
    batch.delete(_document(user.uid));
    batch.delete(_lisiereDocument(user.uid));
    await batch.commit();
  }

  /// One-way development migration to Worldcraft 0. It removes only the old
  /// player-owned V2 territory projection and its detailed Lisière snapshot;
  /// accounts, NFC identity, P'TIPOTES and social documents are preserved.
  Future<void> resetLegacyV2TerritoryForWorldcraft() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final batch = _firestore.batch();
    batch.delete(_lisiereDocument(user.uid));
    batch.set(_document(user.uid), <String, dynamic>{
      'stage': Zone0V2WorldStage.questionnaire.name,
      'region': FieldValue.delete(),
      'biomes': FieldValue.delete(),
      'camp': FieldValue.delete(),
      'core': FieldValue.delete(),
      'buildings': FieldValue.delete(),
      'residents': FieldValue.delete(),
      'campStorage': FieldValue.delete(),
      'firstResidentHook': FieldValue.delete(),
      'worldcraft': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<String> helpConstruction(String buildingId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour aider le chantier.');
    }
    final reference = _document(user.uid);
    final personal = (await reference.get()).data();
    final worldcraft = personal?['worldcraft'];
    if (worldcraft is Map && worldcraft['campId'] is String) {
      return WorldcraftV2Service().helpCampConstruction(
        campId: worldcraft['campId'] as String,
        buildingId: buildingId,
      );
    }
    return _firestore.runTransaction<String>((transaction) async {
      final data = (await transaction.get(reference)).data();
      final buildings = data?['buildings'] as Map?;
      final rawBuilding = buildings?[buildingId];
      if (rawBuilding is! Map) throw StateError('Chantier introuvable.');
      final building = Map<String, dynamic>.from(rawBuilding);
      final construction = Map<String, dynamic>.from(
        building['construction'] as Map? ?? const <String, dynamic>{},
      );
      final now = DateTime.now();
      final events = List<dynamic>.from(
        construction['assistanceEvents'] as List? ?? const <dynamic>[],
      );
      final last = events.isEmpty ? null : events.last as num?;
      final cooldown =
          (construction['assistanceCooldownSeconds'] as num?)?.toInt() ??
              const Duration(hours: 3).inSeconds;
      if (last != null &&
          now
                  .difference(DateTime.fromMillisecondsSinceEpoch(last.toInt()))
                  .inSeconds <
              cooldown) {
        throw StateError(
            'Les bâtisseurs auront de nouveau besoin de toi dans 3 h.');
      }
      events.add(now.millisecondsSinceEpoch);
      construction['assistanceEvents'] = events;
      building['construction'] = construction;
      _completeBuildingIfReady(building, now);
      final allBuildings = Map<String, dynamic>.from(buildings!);
      allBuildings[buildingId] = building;
      transaction.set(
          reference,
          <String, dynamic>{
            'buildings': allBuildings,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return 'Ton aide fait gagner 3 h au chantier.';
    });
  }

  /// Removes one physical resource from the V2 Camp stock and applies its
  /// three-hour reduction in the same Firestore transaction as the chantier.
  Future<String> contributeConstructionResource({
    required String buildingId,
    required LisiereResourceKind resource,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour contribuer au chantier.');
    }
    final foundationReference = _document(user.uid);
    final personal = (await foundationReference.get()).data();
    final worldcraft = personal?['worldcraft'];
    if (worldcraft is Map && worldcraft['campId'] is String) {
      return WorldcraftV2Service().contributeCampConstruction(
        campId: worldcraft['campId'] as String,
        buildingId: buildingId,
        resourceType: resource.name,
      );
    }
    final lisiereReference = _lisiereDocument(user.uid);
    return _firestore.runTransaction<String>((transaction) async {
      final foundationData =
          (await transaction.get(foundationReference)).data();
      final lisiereData = (await transaction.get(lisiereReference)).data();
      if (foundationData == null || lisiereData == null) {
        throw StateError('Le Camp ou son stock V2 est introuvable.');
      }
      final buildings = foundationData['buildings'] as Map?;
      final rawBuilding = buildings?[buildingId];
      if (rawBuilding is! Map) {
        throw StateError('Chantier introuvable.');
      }
      final lisiere = LisiereV2Snapshot.fromMap(lisiereData);
      final campStock = lisiere.inventories['camp-storage-v2'];
      if (campStock == null || campStock.remove(resource, 1) != 1) {
        throw StateError(
          'Il manque ${_resourceName(resource)} dans le stock du Camp.',
        );
      }
      final building = Map<String, dynamic>.from(rawBuilding);
      final construction = Map<String, dynamic>.from(
        building['construction'] as Map? ?? const <String, dynamic>{},
      );
      final contributions = List<dynamic>.from(
        construction['resourceContributions'] as List? ?? const <dynamic>[],
      );
      final now = DateTime.now();
      contributions.add(<String, dynamic>{
        'resource': resource.name,
        'at': now.millisecondsSinceEpoch,
      });
      construction['resourceContributions'] = contributions;
      building['construction'] = construction;
      _completeBuildingIfReady(building, now);
      final allBuildings = Map<String, dynamic>.from(buildings!);
      allBuildings[buildingId] = building;
      lisiere.updatedAt = now;
      transaction.set(
        lisiereReference,
        <String, dynamic>{
          ...lisiere.toMap(),
          'ownerId': user.uid,
          'serverUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      transaction.set(
        foundationReference,
        <String, dynamic>{
          'buildings': allBuildings,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return '${_resourceName(resource)} livré : le chantier gagne 3 h.';
    });
  }

  static void _completeBuildingIfReady(
    Map<String, dynamic> building,
    DateTime now,
  ) {
    final construction = Map<String, dynamic>.from(
      building['construction'] as Map? ?? const <String, dynamic>{},
    );
    final startedAt = construction['startedAt'] as num?;
    if (startedAt == null) return;
    final base = (construction['baseDurationSeconds'] as num?)?.toInt() ??
        const Duration(hours: 24).inSeconds;
    final assistance =
        construction['assistanceEvents'] as List? ?? const <dynamic>[];
    final resources =
        construction['resourceContributions'] as List? ?? const <dynamic>[];
    final reduction =
        (construction['assistanceReductionSeconds'] as num?)?.toInt() ??
            const Duration(hours: 3).inSeconds;
    final resourceReduction =
        (construction['resourceReductionSeconds'] as num?)?.toInt() ??
            const Duration(hours: 3).inSeconds;
    final requiredSeconds = base -
        assistance.length * reduction -
        resources.length * resourceReduction;
    final elapsed = now
        .difference(DateTime.fromMillisecondsSinceEpoch(startedAt.toInt()))
        .inSeconds;
    if (elapsed >= requiredSeconds) {
      building['state'] = 'active';
    }
  }

  static String _resourceName(LisiereResourceKind resource) =>
      switch (resource) {
        LisiereResourceKind.organic => 'Organique',
        LisiereResourceKind.mineral => 'Minéral',
        LisiereResourceKind.waste => 'Déchet',
      };

  static Map<String, dynamic> _building(
    String id,
    String campId,
    Zone0V2BuildingType type,
    DateTime createdAt,
  ) =>
      <String, dynamic>{
        'id': id,
        'campId': campId,
        'buildingType': type.name,
        'structureIds': <String>[],
        'state': 'constructing',
        'residentCapacity': 3,
        'construction': <String, dynamic>{
          'startedAt': createdAt.millisecondsSinceEpoch,
          'baseDurationSeconds': const Duration(hours: 24).inSeconds,
          'assistanceCooldownSeconds': const Duration(hours: 3).inSeconds,
          'assistanceReductionSeconds': const Duration(hours: 3).inSeconds,
          'resourceReductionSeconds': const Duration(hours: 3).inSeconds,
          'residentIds': <String>[
            'resident-v2-1',
            'resident-v2-2',
            'resident-v2-3',
          ],
          'assistanceEvents': <dynamic>[],
          'resourceContributions': <dynamic>[],
        },
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static Map<String, dynamic> _resident(
    String id,
    String campId,
    DateTime createdAt,
    int seed,
  ) {
    const names = <String>[
      'Avel',
      'Nomi',
      'Sélène',
      'Timo',
      'Mila',
      'Orin',
      'Pia',
      'Lumo',
      'Yuna',
    ];
    const wishes = <String>[
      'Récolteur',
      'Patrouilleur',
      'Constructeur',
      'Soigneur',
      'Cuisinier',
      'Artisan',
    ];
    final roll = _stableSeed('$seed:$id');
    return <String, dynamic>{
      'id': id,
      'campId': campId,
      'displayName': names[roll % names.length],
      'desiredJob': wishes[(roll ~/ names.length) % wishes.length],
      'role': 'builder',
      'status': 'building',
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  static int _stableSeed(String value) {
    var hash = 17;
    for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }
}
