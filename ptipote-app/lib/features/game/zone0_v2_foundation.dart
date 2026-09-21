/// Stable, V2-only world foundation.
///
/// This model deliberately does not reuse the V1 island or building-level
/// state. It can therefore be reset independently while NFC identities,
/// friends, chats and transfers keep their existing storage.
library;

enum Zone0V2WorldStage { firstPtipote, naming, questionnaire, camp, ready }

enum RegionPresetId {
  littorauxArchipels,
  hautesTerres,
  plainesSeches,
  bassesEaux,
}

enum RegionQuestionOneAnswer { mer, montagne }

enum RegionQuestionTwoAnswer { neige, soleil }

enum RegionQuestionThreeAnswer { champ, coquillages }

enum RegionBiomePosition { a1, a2, a3, b1, b3 }

enum Zone0V2BuildingType { campCore, house, kernel, securityTower }

const String zone0V2WorldVersion = 'ZONE0_V2_FOUNDATION_1';

/// Designer-owned Region data. The immutable Dart tables below remain the
/// fallback for an incomplete remote payload, so a failed Dashboard publish
/// can never make onboarding impossible.
Map<String, dynamic> _zone0V2FoundationRemote = const <String, dynamic>{};

void applyZone0V2FoundationRemoteConfig(Map<String, dynamic>? raw) {
  _zone0V2FoundationRemote = raw == null
      ? const <String, dynamic>{}
      : Map<String, dynamic>.from(raw);
}

String _id(RegionPresetId value) => switch (value) {
      RegionPresetId.littorauxArchipels => 'LITTORAUX_ARCHIPELS',
      RegionPresetId.hautesTerres => 'HAUTES_TERRES',
      RegionPresetId.plainesSeches => 'PLAINES_SECHES',
      RegionPresetId.bassesEaux => 'BASSES_EAUX',
    };

RegionPresetId _preset(String? value) => RegionPresetId.values.firstWhere(
      (candidate) => _id(candidate) == value,
      orElse: () => RegionPresetId.littorauxArchipels,
    );

class RegionQuestionnaireResult {
  const RegionQuestionnaireResult({
    required this.q1Answer,
    required this.q2Answer,
    required this.q3Answer,
    required this.scoresByRegion,
    required this.selectedRegionPresetId,
    required this.completedAt,
    required this.algorithmVersion,
  });

  final RegionQuestionOneAnswer q1Answer;
  final RegionQuestionTwoAnswer q2Answer;
  final RegionQuestionThreeAnswer q3Answer;
  final Map<RegionPresetId, int> scoresByRegion;
  final RegionPresetId selectedRegionPresetId;
  final DateTime completedAt;
  final String algorithmVersion;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'q1Answer': q1Answer.name,
        'q2Answer': q2Answer.name,
        'q3Answer': q3Answer.name,
        'scoresByRegion': <String, int>{
          for (final entry in scoresByRegion.entries)
            _id(entry.key): entry.value,
        },
        'selectedRegionPresetId': _id(selectedRegionPresetId),
        'completedAt': completedAt.millisecondsSinceEpoch,
        'algorithmVersion': algorithmVersion,
      };

  factory RegionQuestionnaireResult.fromMap(Map<dynamic, dynamic> raw) {
    final scores = raw['scoresByRegion'] as Map? ?? const <dynamic, dynamic>{};
    return RegionQuestionnaireResult(
      q1Answer: RegionQuestionOneAnswer.values.firstWhere(
        (value) => value.name == raw['q1Answer'],
        orElse: () => RegionQuestionOneAnswer.mer,
      ),
      q2Answer: RegionQuestionTwoAnswer.values.firstWhere(
        (value) => value.name == raw['q2Answer'],
        orElse: () => RegionQuestionTwoAnswer.neige,
      ),
      q3Answer: RegionQuestionThreeAnswer.values.firstWhere(
        (value) => value.name == raw['q3Answer'],
        orElse: () => RegionQuestionThreeAnswer.champ,
      ),
      scoresByRegion: <RegionPresetId, int>{
        for (final region in RegionPresetId.values)
          region: (scores[_id(region)] as num?)?.toInt() ?? 0,
      },
      selectedRegionPresetId: _preset(raw['selectedRegionPresetId'] as String?),
      completedAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['completedAt'] as num?)?.toInt() ?? 0,
      ),
      algorithmVersion: '${raw['algorithmVersion'] ?? zone0V2WorldVersion}',
    );
  }
}

RegionQuestionnaireResult calculateRegionQuestionnaire({
  required RegionQuestionOneAnswer q1,
  required RegionQuestionTwoAnswer q2,
  required RegionQuestionThreeAnswer q3,
  required DateTime completedAt,
}) {
  final scores = <RegionPresetId, int>{
    for (final region in RegionPresetId.values) region: 0,
  };
  void addAll(List<RegionPresetId> regions) {
    for (final region in regions) {
      scores[region] = scores[region]! + 1;
    }
  }
  addAll(_questionRegions('q1', q1.name, const <RegionPresetId>[
    RegionPresetId.littorauxArchipels,
    RegionPresetId.bassesEaux,
  ], alternative: q1 == RegionQuestionOneAnswer.montagne
      ? const <RegionPresetId>[
          RegionPresetId.hautesTerres,
          RegionPresetId.plainesSeches,
        ]
      : null));
  addAll(_questionRegions('q2', q2.name, const <RegionPresetId>[
    RegionPresetId.hautesTerres,
    RegionPresetId.bassesEaux,
  ], alternative: q2 == RegionQuestionTwoAnswer.soleil
      ? const <RegionPresetId>[
          RegionPresetId.plainesSeches,
          RegionPresetId.littorauxArchipels,
        ]
      : null));
  addAll(_questionRegions('q3', q3.name, const <RegionPresetId>[
    RegionPresetId.hautesTerres,
    RegionPresetId.plainesSeches,
  ], alternative: q3 == RegionQuestionThreeAnswer.coquillages
      ? const <RegionPresetId>[
          RegionPresetId.bassesEaux,
          RegionPresetId.littorauxArchipels,
        ]
      : null));
  final highest =
      scores.values.reduce((left, right) => left > right ? left : right);
  final tied = scores.entries
      .where((entry) => entry.value == highest)
      .map((entry) => entry.key)
      .toSet();
  final fallbackPriority = q3 == RegionQuestionThreeAnswer.champ
      ? const <RegionPresetId>[
          RegionPresetId.hautesTerres,
          RegionPresetId.plainesSeches
        ]
      : const <RegionPresetId>[
          RegionPresetId.bassesEaux,
          RegionPresetId.littorauxArchipels
        ];
  final priority = _remotePresetList('tiePriorities.${q3.name}') ??
      fallbackPriority;
  final selected = tied.length == 1
      ? tied.single
      : priority.firstWhere((candidate) => tied.contains(candidate));
  return RegionQuestionnaireResult(
    q1Answer: q1,
    q2Answer: q2,
    q3Answer: q3,
    scoresByRegion: Map<RegionPresetId, int>.unmodifiable(scores),
    selectedRegionPresetId: selected,
    completedAt: completedAt,
    algorithmVersion: zone0V2WorldVersion,
  );
}

List<RegionPresetId> _questionRegions(
  String question,
  String answer,
  List<RegionPresetId> fallback, {
  List<RegionPresetId>? alternative,
}) {
  final rawQuestions = _zone0V2FoundationRemote['questionnaireScores'];
  final rawQuestion = rawQuestions is Map ? rawQuestions[question] : null;
  final rawAnswer = rawQuestion is Map ? rawQuestion[answer] : null;
  if (rawAnswer is List) {
    final parsed = rawAnswer
        .map((value) => _preset(value as String?))
        .where((value) => rawAnswer.contains(_id(value)))
        .toList(growable: false);
    if (parsed.isNotEmpty) return parsed;
  }
  return alternative ?? fallback;
}

List<RegionPresetId>? _remotePresetList(String path) {
  Object? value = _zone0V2FoundationRemote;
  for (final part in path.split('.')) {
    if (value is! Map) return null;
    value = value[part];
  }
  if (value is! List) return null;
  final rawList = value;
  final parsed = rawList
      .whereType<String>()
      .map(_preset)
      .where((preset) => rawList.contains(_id(preset)))
      .toList(growable: false);
  return parsed.isEmpty ? null : parsed;
}

class BiomeInstance {
  const BiomeInstance({
    required this.id,
    required this.regionId,
    required this.biomeType,
    required this.mapPosition,
    required this.connectedBiomeIds,
    required this.seed,
    required this.createdAt,
    this.discovered = false,
    this.unlocked = false,
    this.runtimeStateId,
  });

  final String id;
  final String regionId;
  final String biomeType;
  final RegionBiomePosition mapPosition;
  final List<String> connectedBiomeIds;
  final int seed;
  final bool discovered;
  final bool unlocked;
  final String? runtimeStateId;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'regionId': regionId,
        'biomeType': biomeType,
        'mapPosition': mapPosition.name,
        'connectedBiomeIds': connectedBiomeIds,
        'seed': seed,
        'discovered': discovered,
        'unlocked': unlocked,
        'runtimeStateId': runtimeStateId,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory BiomeInstance.fromMap(Map<dynamic, dynamic> raw) => BiomeInstance(
        id: '${raw['id'] ?? ''}',
        regionId: '${raw['regionId'] ?? ''}',
        biomeType: '${raw['biomeType'] ?? ''}',
        mapPosition: RegionBiomePosition.values.firstWhere(
          (value) => value.name == raw['mapPosition'],
          orElse: () => RegionBiomePosition.b1,
        ),
        connectedBiomeIds:
            List<String>.from(raw['connectedBiomeIds'] ?? const []),
        seed: (raw['seed'] as num?)?.toInt() ?? 0,
        discovered: raw['discovered'] == true,
        unlocked: raw['unlocked'] == true,
        runtimeStateId: raw['runtimeStateId'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (raw['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

class RegionBiomePreset {
  const RegionBiomePreset({
    required this.position,
    required this.biomeType,
  });

  final RegionBiomePosition position;
  final String biomeType;
}

const Map<RegionPresetId, List<RegionBiomePreset>> zone0V2RegionPresets =
    <RegionPresetId, List<RegionBiomePreset>>{
  RegionPresetId.littorauxArchipels: <RegionBiomePreset>[
    RegionBiomePreset(position: RegionBiomePosition.b1, biomeType: 'mangrove'),
    RegionBiomePreset(
        position: RegionBiomePosition.a2, biomeType: 'savane_humide'),
    RegionBiomePreset(position: RegionBiomePosition.b3, biomeType: 'marais'),
    RegionBiomePreset(position: RegionBiomePosition.a1, biomeType: 'littoral'),
    RegionBiomePreset(
        position: RegionBiomePosition.a3, biomeType: 'semi_desert'),
  ],
  RegionPresetId.hautesTerres: <RegionBiomePreset>[
    RegionBiomePreset(
        position: RegionBiomePosition.b1, biomeType: 'savane_humide'),
    RegionBiomePreset(position: RegionBiomePosition.a2, biomeType: 'colline'),
    RegionBiomePreset(
        position: RegionBiomePosition.b3, biomeType: 'foret_seche'),
    RegionBiomePreset(
        position: RegionBiomePosition.a1, biomeType: 'haut_refuge'),
    RegionBiomePreset(
        position: RegionBiomePosition.a3, biomeType: 'foret_humide'),
  ],
  RegionPresetId.plainesSeches: <RegionBiomePreset>[
    RegionBiomePreset(position: RegionBiomePosition.b1, biomeType: 'marais'),
    RegionBiomePreset(
        position: RegionBiomePosition.a2, biomeType: 'savane_humide'),
    RegionBiomePreset(
        position: RegionBiomePosition.b3, biomeType: 'savane_seche'),
    RegionBiomePreset(
        position: RegionBiomePosition.a1, biomeType: 'semi_desert'),
    RegionBiomePreset(
        position: RegionBiomePosition.a3, biomeType: 'foret_seche'),
  ],
  RegionPresetId.bassesEaux: <RegionBiomePreset>[
    RegionBiomePreset(
        position: RegionBiomePosition.b1, biomeType: 'foret_humide'),
    RegionBiomePreset(position: RegionBiomePosition.a2, biomeType: 'mangrove'),
    RegionBiomePreset(
        position: RegionBiomePosition.b3, biomeType: 'savane_humide'),
    RegionBiomePreset(position: RegionBiomePosition.a1, biomeType: 'littoral'),
    RegionBiomePreset(position: RegionBiomePosition.a3, biomeType: 'marais'),
  ],
};

const Map<RegionBiomePosition, List<RegionBiomePosition>>
    zone0V2BiomeConnections = <RegionBiomePosition, List<RegionBiomePosition>>{
  RegionBiomePosition.b1: <RegionBiomePosition>[RegionBiomePosition.a1],
  RegionBiomePosition.a1: <RegionBiomePosition>[
    RegionBiomePosition.b1,
    RegionBiomePosition.a2
  ],
  RegionBiomePosition.a2: <RegionBiomePosition>[
    RegionBiomePosition.a1,
    RegionBiomePosition.a3
  ],
  RegionBiomePosition.a3: <RegionBiomePosition>[
    RegionBiomePosition.a2,
    RegionBiomePosition.b3
  ],
  RegionBiomePosition.b3: <RegionBiomePosition>[RegionBiomePosition.a3],
};

List<BiomeInstance> createRegionBiomeInstances({
  required String regionId,
  required RegionPresetId presetId,
  required int seed,
  required DateTime createdAt,
}) {
  final presets = _regionPresetsFor(presetId);
  final ids = <RegionBiomePosition, String>{
    for (final item in presets)
      item.position: '$regionId-${item.position.name}',
  };
  return presets
      .map(
        (item) => BiomeInstance(
          id: ids[item.position]!,
          regionId: regionId,
          biomeType: item.biomeType,
          mapPosition: item.position,
          connectedBiomeIds:
              (_biomeConnectionsFor()[item.position] ?? const [])
                  .map((position) => ids[position]!)
                  .toList(growable: false),
          seed: seed ^ item.position.index,
          discovered: item.position == RegionBiomePosition.b1 ||
              item.position == RegionBiomePosition.a2 ||
              item.position == RegionBiomePosition.b3,
          unlocked: item.position == RegionBiomePosition.b1 ||
              item.position == RegionBiomePosition.a2 ||
              item.position == RegionBiomePosition.b3,
          createdAt: createdAt,
        ),
      )
      .toList(growable: false);
}

List<RegionBiomePreset> _regionPresetsFor(RegionPresetId presetId) {
  final rawPresets = _zone0V2FoundationRemote['presets'];
  final raw = rawPresets is Map ? rawPresets[_id(presetId)] : null;
  if (raw is List) {
    final parsed = raw.whereType<Map>().map((item) {
      final position = RegionBiomePosition.values.firstWhere(
        (value) => value.name == item['position'],
        orElse: () => RegionBiomePosition.b1,
      );
      return RegionBiomePreset(
        position: position,
        biomeType: '${item['biomeType'] ?? ''}',
      );
    }).where((item) => item.biomeType.isNotEmpty).toList(growable: false);
    if (parsed.length == RegionBiomePosition.values.length &&
        parsed.map((item) => item.position).toSet().length == parsed.length) {
      return parsed;
    }
  }
  return zone0V2RegionPresets[presetId]!;
}

Map<RegionBiomePosition, List<RegionBiomePosition>> _biomeConnectionsFor() {
  final raw = _zone0V2FoundationRemote['connections'];
  if (raw is! Map) return zone0V2BiomeConnections;
  final result = <RegionBiomePosition, List<RegionBiomePosition>>{};
  for (final position in RegionBiomePosition.values) {
    final list = raw[position.name];
    if (list is! List) continue;
    result[position] = list.whereType<String>().map((id) {
      return RegionBiomePosition.values.firstWhere(
        (value) => value.name == id,
        orElse: () => position,
      );
    }).where((value) => value != position).toList(growable: false);
  }
  return result.length == RegionBiomePosition.values.length
      ? result
      : zone0V2BiomeConnections;
}

class RegionInstance {
  const RegionInstance({
    required this.id,
    required this.ownerId,
    required this.presetId,
    required this.createdAt,
    required this.seed,
    required this.campId,
    required this.biomeIds,
    required this.questionnaireResultId,
    required this.worldVersion,
  });

  final String id;
  final String ownerId;
  final RegionPresetId presetId;
  final DateTime createdAt;
  final int seed;
  final String campId;
  final List<String> biomeIds;
  final String questionnaireResultId;
  final String worldVersion;
}

class CampInstance {
  const CampInstance({
    required this.id,
    required this.regionId,
    required this.ownerId,
    required this.createdAt,
    required this.coreId,
    required this.buildingIds,
    required this.storageId,
    required this.worldVersion,
    this.progressionState = 'foundation',
  });

  final String id;
  final String regionId;
  final String ownerId;
  final DateTime createdAt;
  final String coreId;
  final List<String> buildingIds;
  final String storageId;
  final String progressionState;
  final String worldVersion;
}

class Zone0V2FoundationState {
  const Zone0V2FoundationState({
    required this.worldVersion,
    required this.ownerId,
    required this.createdAt,
    this.stage = Zone0V2WorldStage.firstPtipote,
    this.firstPtipoteId,
    this.questionnaireResult,
    this.region,
    this.camp,
  });

  final String worldVersion;
  final String ownerId;
  final DateTime createdAt;
  final Zone0V2WorldStage stage;
  final String? firstPtipoteId;
  final RegionQuestionnaireResult? questionnaireResult;
  final RegionInstance? region;
  final CampInstance? camp;

  bool get isReady => stage == Zone0V2WorldStage.ready && camp != null;
}
