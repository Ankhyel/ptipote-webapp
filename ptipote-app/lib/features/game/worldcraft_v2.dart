/// Worldcraft 0 is the shared, asynchronous territorial authority for V2.
///
/// It intentionally contains no Walker, presence, PvP or live multiplayer.
/// The detailed Lisière projection remains a client-side layer keyed by these
/// stable world, region, biome and parcel identifiers.
library;

enum WorldcraftRegionProfile { highRefuge, coastal, dry, mixed, transition }

enum WorldcraftRegionOccupancy { free, occupied }

enum WorldcraftCampSimulationMode { active, autonomous }

const String worldcraftV2Version = 'WORLDCRAFT_0_1';
const String worldbuildingV2Version = 'WORLDBUILDING_0_1';
const String worldcraftPrototypeWorldId = 'zone0-shared-world';
const String worldcraftPrototypeMapId = 'zone0-map-5x5';

/// Canonical topological slots of a Region. Their actual types and visual
/// profiles are server-authored Worldbuilding data, never a private reroll.
const List<String> worldcraftBiomeInternalPositions = <String>[
  'b1',
  'a1',
  'a2',
  'a3',
  'b3',
];

String worldcraftCoordinate(int x, int y) =>
    '${String.fromCharCode('A'.codeUnitAt(0) + x)}${y + 1}';

class WorldcraftRegionSeed {
  const WorldcraftRegionSeed({
    required this.id,
    required this.coordinateX,
    required this.coordinateY,
    required this.displayCoordinate,
    required this.profile,
    required this.biomeIds,
    required this.connectionIds,
    required this.seed,
    this.hubId,
  });

  final String id;
  final int coordinateX;
  final int coordinateY;
  final String displayCoordinate;
  final WorldcraftRegionProfile profile;
  final List<String> biomeIds;
  final List<String> connectionIds;
  final int seed;
  final String? hubId;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'coordinateX': coordinateX,
        'coordinateY': coordinateY,
        'displayCoordinate': displayCoordinate,
        'profile': profile.name,
        'biomeIds': biomeIds,
        'connectionIds': connectionIds,
        'seed': seed,
        'hubId': hubId,
        'campId': null,
        'occupancyState': WorldcraftRegionOccupancy.free.name,
        'lastSimulatedAt': 0,
        'simulationVersion': worldcraftV2Version,
      };
}

class WorldcraftConnectionSeed {
  const WorldcraftConnectionSeed({
    required this.id,
    required this.fromRegionId,
    required this.toRegionId,
  });

  final String id;
  final String fromRegionId;
  final String toRegionId;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'fromRegionId': fromRegionId,
        'toRegionId': toRegionId,
        'connectionType': 'orthogonal',
        'traversable': true,
      };
}

class WorldcraftSeed {
  const WorldcraftSeed({
    required this.worldId,
    required this.worldMapId,
    required this.seed,
    required this.regions,
    required this.connections,
  });

  final String worldId;
  final String worldMapId;
  final int seed;
  final List<WorldcraftRegionSeed> regions;
  final List<WorldcraftConnectionSeed> connections;
}

WorldcraftSeed createWorldcraftPrototypeSeed({int seed = 250525}) {
  const profiles = <List<WorldcraftRegionProfile>>[
    <WorldcraftRegionProfile>[
      WorldcraftRegionProfile.highRefuge,
      WorldcraftRegionProfile.highRefuge,
      WorldcraftRegionProfile.highRefuge,
      WorldcraftRegionProfile.highRefuge,
      WorldcraftRegionProfile.dry,
    ],
    <WorldcraftRegionProfile>[
      WorldcraftRegionProfile.highRefuge,
      WorldcraftRegionProfile.transition,
      WorldcraftRegionProfile.highRefuge,
      WorldcraftRegionProfile.transition,
      WorldcraftRegionProfile.dry,
    ],
    <WorldcraftRegionProfile>[
      WorldcraftRegionProfile.coastal,
      WorldcraftRegionProfile.mixed,
      WorldcraftRegionProfile.highRefuge,
      WorldcraftRegionProfile.mixed,
      WorldcraftRegionProfile.dry,
    ],
    <WorldcraftRegionProfile>[
      WorldcraftRegionProfile.coastal,
      WorldcraftRegionProfile.transition,
      WorldcraftRegionProfile.mixed,
      WorldcraftRegionProfile.transition,
      WorldcraftRegionProfile.dry,
    ],
    <WorldcraftRegionProfile>[
      WorldcraftRegionProfile.coastal,
      WorldcraftRegionProfile.coastal,
      WorldcraftRegionProfile.coastal,
      WorldcraftRegionProfile.coastal,
      WorldcraftRegionProfile.dry,
    ],
  ];
  final connectionIds = <String, List<String>>{};
  final connections = <WorldcraftConnectionSeed>[];
  String regionId(int x, int y) =>
      'region-${worldcraftCoordinate(x, y).toLowerCase()}';
  for (var y = 0; y < 5; y++) {
    for (var x = 0; x < 5; x++) {
      connectionIds[regionId(x, y)] = <String>[];
    }
  }
  for (var y = 0; y < 5; y++) {
    for (var x = 0; x < 5; x++) {
      final current = regionId(x, y);
      for (final neighbor in <({int x, int y})>[
        if (x < 4) (x: x + 1, y: y),
        if (y < 4) (x: x, y: y + 1),
      ]) {
        final other = regionId(neighbor.x, neighbor.y);
        final id = 'connection-$current-$other';
        connections.add(WorldcraftConnectionSeed(
          id: id,
          fromRegionId: current,
          toRegionId: other,
        ));
        connectionIds[current]!.add(id);
        connectionIds[other]!.add(id);
      }
    }
  }
  final regions = <WorldcraftRegionSeed>[];
  for (var y = 0; y < 5; y++) {
    for (var x = 0; x < 5; x++) {
      final coordinate = worldcraftCoordinate(x, y);
      final id = regionId(x, y);
      regions.add(WorldcraftRegionSeed(
        id: id,
        coordinateX: x,
        coordinateY: y,
        displayCoordinate: coordinate,
        profile: profiles[y][x],
        biomeIds: List<String>.generate(5, (index) => '$id-biome-${index + 1}'),
        connectionIds: connectionIds[id]!,
        seed: worldcraftStableSeed('$seed:$id'),
        hubId: coordinate == 'C3' ? 'hub-c3' : null,
      ));
    }
  }
  return WorldcraftSeed(
    worldId: worldcraftPrototypeWorldId,
    worldMapId: worldcraftPrototypeMapId,
    seed: seed,
    regions: regions,
    connections: connections,
  );
}

List<String> worldcraftBiomeComposition(WorldcraftRegionProfile profile) =>
    switch (profile) {
      WorldcraftRegionProfile.highRefuge => const <String>[
          'haut_refuge',
          'colline',
          'foret_humide',
          'savane_humide',
          'foret_seche',
        ],
      WorldcraftRegionProfile.coastal => const <String>[
          'littoral',
          'mangrove',
          'marais',
          'savane_humide',
          'foret_humide',
        ],
      WorldcraftRegionProfile.dry => const <String>[
          'semi_desert',
          'savane_seche',
          'foret_seche',
          'colline',
          'marais',
        ],
      WorldcraftRegionProfile.mixed => const <String>[
          'savane_humide',
          'marais',
          'colline',
          'foret_seche',
          'littoral',
        ],
      WorldcraftRegionProfile.transition => const <String>[
          'savane_humide',
          'colline',
          'savane_seche',
          'foret_seche',
          'marais',
        ],
    };

/// Minimal lazy resolver. It deliberately only advances timestamps: ecology,
/// contamination and weather formulas will be introduced by later prompts.
Map<String, dynamic> resolveWorldcraftMacroState(
  Map<String, dynamic> state,
  DateTime target,
) {
  final previous = state['lastSimulatedAt'] is num
      ? DateTime.fromMillisecondsSinceEpoch(
          (state['lastSimulatedAt'] as num).toInt())
      : target;
  if (!target.isAfter(previous)) return Map<String, dynamic>.from(state);
  return <String, dynamic>{
    ...state,
    'lastSimulatedAt': target.millisecondsSinceEpoch,
    'simulationVersion': worldcraftV2Version,
  };
}

bool isWorldcraftTraceVisible(Map<String, dynamic> trace, DateTime now) =>
    trace['expiresAt'] is num &&
    DateTime.fromMillisecondsSinceEpoch((trace['expiresAt'] as num).toInt())
        .isAfter(now);

/// Indicative onboarding helper only. It never changes the shared World and
/// will later be consumed by Walker destination UI rather than direct travel.
List<Map<String, dynamic>> recommendWorldcraftRegionsForQuestionnaire({
  required Iterable<Map<String, dynamic>> regions,
  required String questionnaireProfile,
}) {
  final priorities = switch (questionnaireProfile) {
    'LITTORAUX_ARCHIPELS' => const <String>['coastal', 'mixed'],
    'HAUTES_TERRES' => const <String>['highRefuge', 'transition'],
    'PLAINES_SECHES' => const <String>['dry', 'mixed'],
    'BASSES_EAUX' => const <String>['coastal', 'transition'],
    _ => const <String>['mixed', 'transition', 'coastal', 'highRefuge', 'dry'],
  };
  final ordered = regions.toList(growable: false)
    ..sort((left, right) {
      final leftRank = priorities.indexOf('${left['profile']}');
      final rightRank = priorities.indexOf('${right['profile']}');
      final normalizedLeft = leftRank < 0 ? priorities.length : leftRank;
      final normalizedRight = rightRank < 0 ? priorities.length : rightRank;
      return normalizedLeft != normalizedRight
          ? normalizedLeft.compareTo(normalizedRight)
          : '${left['displayCoordinate']}'
              .compareTo('${right['displayCoordinate']}');
    });
  return ordered;
}

/// A regional WeatherCell stays shared; this only gives the local Biome its
/// geographic presentation. It intentionally does not apply ecology formulas.
String worldcraftWeatherProjection({
  required String weatherType,
  required String biomeType,
}) {
  if (weatherType != 'rain') return weatherType;
  return switch (biomeType) {
    'mangrove' || 'marais' => 'forte_pluie',
    'savane_humide' || 'foret_humide' => 'pluie',
    'savane_seche' || 'foret_seche' => 'pluie_moderee',
    'semi_desert' => 'pluie_faible',
    _ => 'pluie',
  };
}

int worldcraftStableSeed(String value) {
  var hash = 17;
  for (final codeUnit in value.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash;
}
