import 'package:flutter_test/flutter_test.dart';
import 'package:ptipote_app/features/game/worldcraft_v2.dart';

void main() {
  test('Worldcraft prototype creates a stable 5×5 map with 25 regions', () {
    final first = createWorldcraftPrototypeSeed();
    final second = createWorldcraftPrototypeSeed();
    expect(first.regions, hasLength(25));
    expect(first.regions.map((region) => region.displayCoordinate).toSet(),
        hasLength(25));
    expect(first.regions.map((region) => region.id),
        second.regions.map((region) => region.id));
    expect(
        first.regions.every((region) => region.biomeIds.length == 5), isTrue);
    expect(
        first.regions.every((region) => !region.toMap().containsKey('ownerId')),
        isTrue);
  });

  test('C3 is the unique High Refuge Hub', () {
    final regions = createWorldcraftPrototypeSeed().regions;
    final hubs = regions.where((region) => region.hubId != null).toList();
    expect(hubs, hasLength(1));
    expect(hubs.single.displayCoordinate, 'C3');
    expect(hubs.single.profile, WorldcraftRegionProfile.highRefuge);
  });

  test('orthogonal connections are stable and do not create diagonal links',
      () {
    final seed = createWorldcraftPrototypeSeed();
    expect(seed.connections, hasLength(40));
    final ids = seed.connections.map((connection) => connection.id).toSet();
    expect(ids, hasLength(40));
    final c3 =
        seed.regions.singleWhere((region) => region.displayCoordinate == 'C3');
    expect(c3.connectionIds, hasLength(4));
  });

  test('profile composition always has exactly five shared Biomes', () {
    for (final profile in WorldcraftRegionProfile.values) {
      expect(worldcraftBiomeComposition(profile), hasLength(5));
    }
  });

  test('Worldbuilding keeps the five canonical internal Biome positions', () {
    expect(worldbuildingV2Version, 'WORLDBUILDING_0_1');
    expect(worldcraftBiomeInternalPositions, <String>[
      'b1',
      'a1',
      'a2',
      'a3',
      'b3',
    ]);
  });

  test('the macro resolver is lazy, timestamp based and deterministic', () {
    final initial = <String, dynamic>{
      'danger': 12,
      'mineralReserveSummary': 90,
      'lastSimulatedAt': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
    };
    final target = DateTime.utc(2026, 1, 2);
    final first = resolveWorldcraftMacroState(initial, target);
    final second = resolveWorldcraftMacroState(initial, target);
    expect(first, second);
    expect(first['danger'], 12);
    expect(first['lastSimulatedAt'], target.millisecondsSinceEpoch);
  });

  test('expired traces are never visible', () {
    final now = DateTime.utc(2026, 1, 2);
    expect(
        isWorldcraftTraceVisible(<String, dynamic>{
          'expiresAt': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        }, now),
        isTrue);
    expect(
        isWorldcraftTraceVisible(<String, dynamic>{
          'expiresAt':
              now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
        }, now),
        isFalse);
  });

  test('one shared weather cell has geographic local projections', () {
    expect(
        worldcraftWeatherProjection(weatherType: 'rain', biomeType: 'mangrove'),
        'forte_pluie');
    expect(
        worldcraftWeatherProjection(
            weatherType: 'rain', biomeType: 'semi_desert'),
        'pluie_faible');
  });
}
