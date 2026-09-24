import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'worldcraft_v2.dart';

/// Client gateway for shared Worldcraft state.
///
/// Reads are ordinary Firestore projections. Every shared mutation goes
/// through a callable Cloud Function; Firestore rules reject direct writes.
class WorldcraftV2Service {
  WorldcraftV2Service({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'europe-west9');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> ensureWorld() async {
    final result =
        await _call('ensureWorldcraftWorld', const <String, dynamic>{});
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> loadRegions() async {
    final snapshot = await _firestore
        .collection('regions')
        .where('worldId', isEqualTo: worldcraftPrototypeWorldId)
        .get();
    final regions = snapshot.docs.map((document) => document.data()).toList();
    regions.sort((left, right) => '${left['displayCoordinate']}'
        .compareTo('${right['displayCoordinate']}'));
    return regions;
  }

  /// Small DEV-map projection. Its `biomeSummaries` are embedded in each
  /// Region at generation time, so opening the 5×5 map never loads 125
  /// detailed Biome documents.
  Future<List<Map<String, dynamic>>> loadWorldMapSummary() async {
    final regions = await loadRegions();
    final byConnection = <String, List<Map<String, dynamic>>>{};
    for (final region in regions) {
      for (final connectionId
          in List<String>.from(region['connectionIds'] as List? ?? const [])) {
        final connectedRegions = byConnection.putIfAbsent(
            connectionId, () => <Map<String, dynamic>>[]);
        connectedRegions.add(region);
      }
    }
    return regions.map((region) {
      final neighbors = <Map<String, dynamic>>[];
      for (final connectionId
          in List<String>.from(region['connectionIds'] as List? ?? const [])) {
        neighbors.addAll(byConnection[connectionId] ?? const []);
      }
      neighbors.removeWhere((neighbor) => neighbor['id'] == region['id']);
      final neighborCoordinates = neighbors
          .map((neighbor) => '${neighbor['displayCoordinate']}')
          .toSet()
          .toList()
        ..sort();
      return <String, dynamic>{
        ...region,
        'biomes': (region['biomeSummaries'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map((biome) => Map<String, dynamic>.from(biome))
            .toList(growable: false),
        'neighborCoordinates': neighborCoordinates,
      };
    }).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getWorldMapSummary() =>
      loadWorldMapSummary();

  Future<Map<String, dynamic>?> getRegionSummary(String regionId) async {
    final region = await loadRegion(regionId);
    if (region == null) return null;
    return <String, dynamic>{
      ...region,
      'biomes': (region['biomeSummaries'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((biome) => Map<String, dynamic>.from(biome))
          .toList(growable: false),
    };
  }

  Future<Map<String, dynamic>?> getBiomeSummary(
    String regionId,
    String biomeId,
  ) async {
    final region = await getRegionSummary(regionId);
    if (region == null) return null;
    return (region['biomes'] as List)
        .whereType<Map>()
        .map((biome) => Map<String, dynamic>.from(biome))
        .where((biome) => biome['id'] == biomeId)
        .firstOrNull;
  }

  Future<Map<String, dynamic>?> loadRegion(String regionId) async =>
      (await _firestore.collection('regions').doc(regionId).get()).data();

  Future<List<Map<String, dynamic>>> loadBiomes(String regionId) async {
    final region = await loadRegion(regionId);
    final ids = List<String>.from(region?['biomeIds'] as List? ?? const []);
    if (ids.isEmpty) return const <Map<String, dynamic>>[];
    final values = await Future.wait(ids.map((id) async =>
        (await _firestore.collection('biomeSharedStates').doc(id).get())
            .data()));
    return values.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<Map<String, dynamic>?> loadCamp(String campId) async =>
      (await _firestore.collection('camps').doc(campId).get()).data();

  Future<Map<String, dynamic>?> loadCampMacroState(String campId) async =>
      (await _firestore.collection('campMacroStates').doc(campId).get()).data();

  Future<Map<String, dynamic>?> loadCampStorage(String campId) async =>
      (await _firestore.collection('campStorages').doc('$campId-storage').get())
          .data();

  Future<Map<String, dynamic>> flushCampStorage(String campId) async =>
      Map<String, dynamic>.from(await _call(
        'flushWorldcraftCampStorage',
        <String, dynamic>{
          'operationId':
              'flush-$campId-${DateTime.now().microsecondsSinceEpoch}',
          'campId': campId,
        },
      ));

  Future<Map<String, dynamic>> createCampInRegion({
    required String operationId,
    required String regionId,
  }) async =>
      Map<String, dynamic>.from(
          await _call('createCampInRegion', <String, dynamic>{
        'operationId': operationId,
        'regionId': regionId,
      }));

  Future<Map<String, dynamic>> upgradeWorldbuilding({
    required String operationId,
  }) async =>
      Map<String, dynamic>.from(await _call(
        'upgradeWorldcraftWorldbuilding',
        <String, dynamic>{'operationId': operationId},
      ));

  Future<Map<String, dynamic>> resolveRegionUntil(String regionId) async =>
      Map<String, dynamic>.from(await _call('resolveWorldcraftRegionUntil',
          <String, dynamic>{'regionId': regionId}));

  Future<Map<String, dynamic>> setCampMode({
    required String campId,
    required WorldcraftCampSimulationMode mode,
  }) async =>
      Map<String, dynamic>.from(
          await _call('setWorldcraftCampMode', <String, dynamic>{
        'campId': campId,
        'mode': mode.name,
      }));

  Future<Map<String, dynamic>> resolveCampUntil(String campId) async =>
      Map<String, dynamic>.from(await _call(
          'resolveWorldcraftCampUntil', <String, dynamic>{'campId': campId}));

  Future<String> helpCampConstruction({
    required String campId,
    required String buildingId,
  }) async {
    final result =
        await _call('helpWorldcraftCampConstruction', <String, dynamic>{
      'operationId':
          'help-$campId-$buildingId-${DateTime.now().microsecondsSinceEpoch}',
      'campId': campId,
      'buildingId': buildingId,
    });
    return '${result['message'] ?? ''}';
  }

  Future<String> contributeCampConstruction({
    required String campId,
    required String buildingId,
    required String resourceType,
  }) async {
    final result =
        await _call('contributeWorldcraftCampConstruction', <String, dynamic>{
      'operationId':
          'contribution-$campId-$buildingId-${DateTime.now().microsecondsSinceEpoch}',
      'campId': campId,
      'buildingId': buildingId,
      'resourceType': resourceType,
    });
    return '${result['message'] ?? ''}';
  }

  Future<int> extractSharedMineral({
    required String operationId,
    required String biomeId,
    required int requestedAmount,
  }) async {
    final result = Map<String, dynamic>.from(await _call(
      'extractSharedResource',
      <String, dynamic>{
        'operationId': operationId,
        'biomeId': biomeId,
        'requestedAmount': requestedAmount,
      },
    ));
    return (result['actualExtracted'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>> harvestSharedOrganic({
    required String operationId,
    required String biomeId,
    required String nodeId,
    required int requestedAmount,
  }) async =>
      Map<String, dynamic>.from(await _call(
        'harvestWorldcraftOrganic',
        <String, dynamic>{
          'operationId': operationId,
          'biomeId': biomeId,
          'nodeId': nodeId,
          'requestedAmount': requestedAmount,
        },
      ));

  Future<Map<String, dynamic>> cleanSharedWaste({
    required String operationId,
    required String biomeId,
    required String depositId,
    required int requestedAmount,
  }) async =>
      Map<String, dynamic>.from(await _call(
        'cleanWorldcraftWaste',
        <String, dynamic>{
          'operationId': operationId,
          'biomeId': biomeId,
          'depositId': depositId,
          'requestedAmount': requestedAmount,
        },
      ));

  Future<Map<String, dynamic>> resolvePTibugCleaner({
    required String operationId,
    required String biomeId,
    required String ptibugId,
    required DateTime activeSince,
  }) async =>
      Map<String, dynamic>.from(await _call(
        'resolveWorldcraftPTibugCleaner',
        <String, dynamic>{
          'operationId': operationId,
          'biomeId': biomeId,
          'ptibugId': ptibugId,
          'activeSinceMs': activeSince.millisecondsSinceEpoch,
        },
      ));

  Future<Map<String, dynamic>> extractDeepMineral({
    required String operationId,
    required String biomeId,
    required int requestedAmount,
    String cadence = 'normal',
    bool automated = false,
    String actorType = 'manual',
  }) async =>
      Map<String, dynamic>.from(await _call(
        'extractWorldcraftDeepMineral',
        <String, dynamic>{
          'operationId': operationId,
          'biomeId': biomeId,
          'requestedAmount': requestedAmount,
          'cadence': cadence,
          'automated': automated,
          'actorType': actorType,
        },
      ));

  Future<int> adjustBiomeDanger({
    required String operationId,
    required String biomeId,
    required int delta,
  }) async {
    final result = await _call('adjustWorldcraftBiomeDanger', <String, dynamic>{
      'operationId': operationId,
      'biomeId': biomeId,
      'delta': delta,
    });
    return (result['danger'] as num?)?.toInt() ?? 0;
  }

  Future<String> recordTrace({
    required String operationId,
    required String regionId,
    String? biomeId,
    String traceType = 'visit',
  }) async {
    final result = Map<String, dynamic>.from(await _call(
      'recordWorldcraftTrace',
      <String, dynamic>{
        'operationId': operationId,
        'regionId': regionId,
        'biomeId': biomeId,
        'traceType': traceType,
      },
    ));
    return '${result['traceId'] ?? ''}';
  }

  Future<int> claimPassageReserve({
    required String operationId,
    required String campId,
    required String resourceType,
    required int requestedAmount,
  }) async {
    final result = Map<String, dynamic>.from(await _call(
      'claimWorldcraftPassageReserve',
      <String, dynamic>{
        'operationId': operationId,
        'campId': campId,
        'resourceType': resourceType,
        'requestedAmount': requestedAmount,
      },
    ));
    return (result['claimedAmount'] as num?)?.toInt() ?? 0;
  }

  Future<void> seedDebugScenario(String scenario) async {
    await _call('seedWorldcraftDebug', <String, dynamic>{'scenario': scenario});
  }

  Future<List<Map<String, dynamic>>> visibleTracesForRegion(
    String regionId,
  ) async {
    final now = Timestamp.now();
    final snapshot = await _firestore
        .collection('playerTraces')
        .where('regionId', isEqualTo: regionId)
        .where('expiresAt', isGreaterThan: now)
        .get();
    return snapshot.docs.map((document) => document.data()).toList();
  }

  Future<List<Map<String, dynamic>>> activeWeatherForRegion(
    String regionId,
  ) async {
    final snapshot = await _firestore
        .collection('weatherCells')
        .where('coveredRegionIds', arrayContains: regionId)
        .where('endsAt', isGreaterThan: Timestamp.now())
        .get();
    return snapshot.docs.map((document) => document.data()).toList();
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call(data);
      if (result.data is! Map) {
        throw StateError('Réponse mondiale invalide.');
      }
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'Opération mondiale indisponible.');
    }
  }
}
