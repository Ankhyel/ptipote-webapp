/// Shared V2 foundation for physical and co-bred P'TIPOTES.
///
/// A [PtipoteV2Profile] is deliberately stored separately from the NFC
/// figurine record. NFC remains the durable physical identity while Zone 0
/// owns game progression and future co-breeding state.
library;

enum PtipoteAcquisitionOrigin { physicalScan, coBreeding, legacyMigration }

enum PtipoteGeneration { vestige, protocol }

enum PtipoteOwnershipMode { owned, coBred }

enum PtipoteLifecycleStatus {
  active,
  departurePending,
  departedCoBreeding,
  archived,
}

enum PtipoteTypeId { vegetal, mineral, mycelial }

enum PtipoteEnvelopeCategory { defense, exploration, production, analyst }

/// Shared arrival state for every new P'TIPOTE, regardless of its origin.
///
/// The state is deliberately part of the common V2 profile rather than of an
/// NFC scan or a future co-breeding session: both entry points use the exact
/// same Couveuse ritual.
enum PtipoteArrivalState {
  pendingEgg,
  incubating,
  rhythmReady,
  rhythmInProgress,
  hatched,
  naming,
  completed,
}

class PtipoteCore {
  const PtipoteCore({
    required this.coreId,
    required this.displayName,
    required this.natureId,
    required this.typeId,
    required this.baseImageAsset,
    required this.compatibleEnvelopeIds,
    this.baseBonuses = const <String, double>{},
    this.enabled = true,
    this.devEnabled = true,
    this.createdAt,
    this.updatedAt,
  });

  final String coreId;
  final String displayName;
  final String natureId;
  final PtipoteTypeId typeId;
  final String baseImageAsset;
  final Set<String> compatibleEnvelopeIds;
  final Map<String, double> baseBonuses;
  final bool enabled;
  final bool devEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'coreId': coreId,
        'displayName': displayName,
        'natureId': natureId,
        'typeId': typeId.name,
        'baseImageAsset': baseImageAsset,
        'compatibleEnvelopeIds': compatibleEnvelopeIds.toList(),
        'baseBonuses': baseBonuses,
        'enabled': enabled,
        'devEnabled': devEnabled,
      };

  factory PtipoteCore.fromFirebase(Map<dynamic, dynamic> value) {
    final compatible = value['compatibleEnvelopeIds'];
    final bonuses = value['baseBonuses'];
    return PtipoteCore(
      coreId: '${value['coreId'] ?? ''}',
      displayName: '${value['displayName'] ?? 'Noyau'}',
      natureId: '${value['natureId'] ?? 'unknown'}',
      typeId: _enumByName(
        PtipoteTypeId.values,
        value['typeId'],
        PtipoteTypeId.vegetal,
      ),
      baseImageAsset: '${value['baseImageAsset'] ?? ''}',
      compatibleEnvelopeIds: compatible is List
          ? compatible.map((item) => '$item').toSet()
          : const <String>{},
      baseBonuses: bonuses is Map
          ? bonuses.map(
              (key, item) => MapEntry('$key', (item as num?)?.toDouble() ?? 0),
            )
          : const <String, double>{},
      enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
      devEnabled:
          value['devEnabled'] is bool ? value['devEnabled'] as bool : true,
    );
  }
}

class PtipoteEnvelope {
  const PtipoteEnvelope({
    required this.envelopeId,
    required this.displayName,
    required this.envelopeCategory,
    this.compatibleCoreIds = const <String>{},
    this.compatibilityRule = 'all',
    this.bonuses = const <String, double>{},
    this.combinedAssetSuffix = '',
    this.enabled = true,
    this.devEnabled = true,
    this.createdAt,
    this.updatedAt,
  });

  final String envelopeId;
  final String displayName;
  final PtipoteEnvelopeCategory envelopeCategory;
  final Set<String> compatibleCoreIds;
  final String compatibilityRule;
  final Map<String, double> bonuses;
  final String combinedAssetSuffix;
  final bool enabled;
  final bool devEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'envelopeId': envelopeId,
        'displayName': displayName,
        'envelopeCategory': envelopeCategory.name,
        'compatibleCoreIds': compatibleCoreIds.toList(),
        'compatibilityRule': compatibilityRule,
        'bonuses': bonuses,
        'combinedAssetSuffix': combinedAssetSuffix,
        'enabled': enabled,
        'devEnabled': devEnabled,
      };
}

class PtipoteSkillProgress {
  const PtipoteSkillProgress({
    required this.skillId,
    this.xp = 0,
    this.level = 0,
    this.lastActivityAt,
  });

  final String skillId;
  final int xp;
  final int level;
  final DateTime? lastActivityAt;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'skillId': skillId,
        'xp': xp,
        'level': level,
        'lastActivityAt': lastActivityAt?.toIso8601String(),
      };

  factory PtipoteSkillProgress.fromFirebase(Map<dynamic, dynamic> value) {
    return PtipoteSkillProgress(
      skillId: '${value['skillId'] ?? ''}',
      xp: (value['xp'] as num?)?.round() ?? 0,
      level: (value['level'] as num?)?.round() ?? 0,
      lastActivityAt: _readDate(value['lastActivityAt']),
    );
  }
}

/// Game profile common to a physical figure and to a future co-bred companion.
class PtipoteEnvelopeSymbiosis {
  const PtipoteEnvelopeSymbiosis({
    required this.envelopeId,
    required this.symbiosisLevel,
    required this.symbiosisProgressPercent,
    required this.startedAt,
    required this.lastCalculatedAt,
    this.lastActivityBonusAt,
    this.maxLevelReached = false,
    this.createdAt,
    this.updatedAt,
  });

  final String envelopeId;
  final int symbiosisLevel;
  final double symbiosisProgressPercent;
  final DateTime startedAt;
  final DateTime lastCalculatedAt;
  final DateTime? lastActivityBonusAt;
  final bool maxLevelReached;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PtipoteEnvelopeSymbiosis copyWith({
    int? symbiosisLevel,
    double? symbiosisProgressPercent,
    DateTime? lastCalculatedAt,
    DateTime? lastActivityBonusAt,
    bool? maxLevelReached,
    DateTime? updatedAt,
  }) =>
      PtipoteEnvelopeSymbiosis(
        envelopeId: envelopeId,
        symbiosisLevel: symbiosisLevel ?? this.symbiosisLevel,
        symbiosisProgressPercent:
            symbiosisProgressPercent ?? this.symbiosisProgressPercent,
        startedAt: startedAt,
        lastCalculatedAt: lastCalculatedAt ?? this.lastCalculatedAt,
        lastActivityBonusAt: lastActivityBonusAt ?? this.lastActivityBonusAt,
        maxLevelReached: maxLevelReached ?? this.maxLevelReached,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'envelopeId': envelopeId,
        'symbiosisLevel': symbiosisLevel,
        'symbiosisProgressPercent': symbiosisProgressPercent,
        'startedAt': startedAt.toIso8601String(),
        'lastCalculatedAt': lastCalculatedAt.toIso8601String(),
        'lastActivityBonusAt': lastActivityBonusAt?.toIso8601String(),
        'maxLevelReached': maxLevelReached,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory PtipoteEnvelopeSymbiosis.fromFirebase(Map<dynamic, dynamic> value) {
    final now = DateTime.now();
    return PtipoteEnvelopeSymbiosis(
      envelopeId: '${value['envelopeId'] ?? ''}',
      symbiosisLevel:
          ((value['symbiosisLevel'] as num?)?.toInt() ?? 0).clamp(0, 2),
      symbiosisProgressPercent:
          ((value['symbiosisProgressPercent'] as num?)?.toDouble() ?? 0)
              .clamp(0, 100),
      startedAt: _readDate(value['startedAt']) ?? now,
      lastCalculatedAt: _readDate(value['lastCalculatedAt']) ?? now,
      lastActivityBonusAt: _readDate(value['lastActivityBonusAt']),
      maxLevelReached: value['maxLevelReached'] == true,
      createdAt: _readDate(value['createdAt']),
      updatedAt: _readDate(value['updatedAt']),
    );
  }
}

class PtipoteV2Profile {
  const PtipoteV2Profile({
    required this.ptipoteId,
    required this.acquisitionOrigin,
    required this.ownershipMode,
    required this.ptipoteGeneration,
    required this.typeId,
    required this.natureId,
    this.coreId,
    this.envelopeId,
    this.envelopeAcquisitionMode,
    this.envelopeSymbiosis,
    this.protocolEfficiencyMultiplier,
    this.systemName = '',
    this.displayName = '',
    this.arrivalState = PtipoteArrivalState.completed,
    this.arrivalCreatedAt,
    this.rhythmSeed,
    this.rhythmPattern = const <int>[],
    this.rhythmAttemptCount = 0,
    this.hatchedAt,
    this.namedAt,
    this.moodId,
    this.moodUpdatedAt,
    this.passionId,
    this.skills = const <String, PtipoteSkillProgress>{},
    this.baseCarryCapacity = 20,
    this.externalCarryCapacityBonus = 0,
    this.visualAssetKey = '',
    this.coBreedingSessionId,
    this.coBreedingStartedAt,
    this.coBreedingExpiresAt,
    this.departurePending = false,
    this.departureReason,
    this.lifecycleStatus = PtipoteLifecycleStatus.active,
    this.migrationWarning,
    this.createdAt,
    this.updatedAt,
  });

  final String ptipoteId;
  final PtipoteAcquisitionOrigin acquisitionOrigin;
  final PtipoteOwnershipMode ownershipMode;
  final PtipoteGeneration ptipoteGeneration;
  final PtipoteTypeId typeId;
  final String natureId;
  final String? coreId;
  final String? envelopeId;
  final String? envelopeAcquisitionMode;
  final PtipoteEnvelopeSymbiosis? envelopeSymbiosis;
  final double? protocolEfficiencyMultiplier;
  final String systemName;
  final String displayName;
  final PtipoteArrivalState arrivalState;
  final DateTime? arrivalCreatedAt;
  final int? rhythmSeed;
  final List<int> rhythmPattern;
  final int rhythmAttemptCount;
  final DateTime? hatchedAt;
  final DateTime? namedAt;
  final String? moodId;
  final DateTime? moodUpdatedAt;
  final String? passionId;
  final Map<String, PtipoteSkillProgress> skills;
  final int baseCarryCapacity;
  final int externalCarryCapacityBonus;
  final String visualAssetKey;
  final String? coBreedingSessionId;
  final DateTime? coBreedingStartedAt;
  final DateTime? coBreedingExpiresAt;
  final bool departurePending;
  final String? departureReason;
  final PtipoteLifecycleStatus lifecycleStatus;
  final String? migrationWarning;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isProtocol => ptipoteGeneration == PtipoteGeneration.protocol;

  bool get isArrivalComplete => arrivalState == PtipoteArrivalState.completed;

  bool get isAwaitingIncubator => !isArrivalComplete;

  double effectiveProtocolEfficiency(PtipoteV2Config config) {
    if (!isProtocol) return 1;
    if (protocolEfficiencyMultiplier != null) {
      return protocolEfficiencyMultiplier!.clamp(0, 10).toDouble();
    }
    if (envelopeId == null) return config.coreOnlyEfficiency;
    return switch (envelopeSymbiosis?.symbiosisLevel ?? 0) {
      0 => config.newEnvelopeEfficiency,
      1 => config.habituatedEnvelopeEfficiency,
      _ => config.adoptedEnvelopeEfficiency,
    };
  }

  PtipoteV2Profile copyWith({
    PtipoteAcquisitionOrigin? acquisitionOrigin,
    PtipoteOwnershipMode? ownershipMode,
    PtipoteGeneration? ptipoteGeneration,
    PtipoteTypeId? typeId,
    String? natureId,
    String? coreId,
    bool clearCoreId = false,
    String? envelopeId,
    bool clearEnvelopeId = false,
    String? envelopeAcquisitionMode,
    bool clearEnvelopeAcquisitionMode = false,
    PtipoteEnvelopeSymbiosis? envelopeSymbiosis,
    bool clearEnvelopeSymbiosis = false,
    double? protocolEfficiencyMultiplier,
    bool clearProtocolEfficiencyMultiplier = false,
    String? systemName,
    String? displayName,
    PtipoteArrivalState? arrivalState,
    DateTime? arrivalCreatedAt,
    int? rhythmSeed,
    List<int>? rhythmPattern,
    int? rhythmAttemptCount,
    DateTime? hatchedAt,
    DateTime? namedAt,
    String? moodId,
    bool clearMoodId = false,
    DateTime? moodUpdatedAt,
    String? passionId,
    bool clearPassionId = false,
    Map<String, PtipoteSkillProgress>? skills,
    int? baseCarryCapacity,
    int? externalCarryCapacityBonus,
    String? visualAssetKey,
    String? coBreedingSessionId,
    bool clearCoBreedingSessionId = false,
    DateTime? coBreedingStartedAt,
    DateTime? coBreedingExpiresAt,
    bool? departurePending,
    String? departureReason,
    bool clearDepartureReason = false,
    PtipoteLifecycleStatus? lifecycleStatus,
    String? migrationWarning,
    bool clearMigrationWarning = false,
    DateTime? updatedAt,
  }) {
    return PtipoteV2Profile(
      ptipoteId: ptipoteId,
      acquisitionOrigin: acquisitionOrigin ?? this.acquisitionOrigin,
      ownershipMode: ownershipMode ?? this.ownershipMode,
      ptipoteGeneration: ptipoteGeneration ?? this.ptipoteGeneration,
      typeId: typeId ?? this.typeId,
      natureId: natureId ?? this.natureId,
      coreId: clearCoreId ? null : coreId ?? this.coreId,
      envelopeId: clearEnvelopeId ? null : envelopeId ?? this.envelopeId,
      envelopeAcquisitionMode: clearEnvelopeAcquisitionMode
          ? null
          : envelopeAcquisitionMode ?? this.envelopeAcquisitionMode,
      envelopeSymbiosis: clearEnvelopeSymbiosis
          ? null
          : envelopeSymbiosis ?? this.envelopeSymbiosis,
      protocolEfficiencyMultiplier: clearProtocolEfficiencyMultiplier
          ? null
          : protocolEfficiencyMultiplier ?? this.protocolEfficiencyMultiplier,
      systemName: systemName ?? this.systemName,
      displayName: displayName ?? this.displayName,
      arrivalState: arrivalState ?? this.arrivalState,
      arrivalCreatedAt: arrivalCreatedAt ?? this.arrivalCreatedAt,
      rhythmSeed: rhythmSeed ?? this.rhythmSeed,
      rhythmPattern: rhythmPattern ?? this.rhythmPattern,
      rhythmAttemptCount: rhythmAttemptCount ?? this.rhythmAttemptCount,
      hatchedAt: hatchedAt ?? this.hatchedAt,
      namedAt: namedAt ?? this.namedAt,
      moodId: clearMoodId ? null : moodId ?? this.moodId,
      moodUpdatedAt: moodUpdatedAt ?? this.moodUpdatedAt,
      passionId: clearPassionId ? null : passionId ?? this.passionId,
      skills: skills ?? this.skills,
      baseCarryCapacity: baseCarryCapacity ?? this.baseCarryCapacity,
      externalCarryCapacityBonus:
          externalCarryCapacityBonus ?? this.externalCarryCapacityBonus,
      visualAssetKey: visualAssetKey ?? this.visualAssetKey,
      coBreedingSessionId: clearCoBreedingSessionId
          ? null
          : coBreedingSessionId ?? this.coBreedingSessionId,
      coBreedingStartedAt: coBreedingStartedAt ?? this.coBreedingStartedAt,
      coBreedingExpiresAt: coBreedingExpiresAt ?? this.coBreedingExpiresAt,
      departurePending: departurePending ?? this.departurePending,
      departureReason:
          clearDepartureReason ? null : departureReason ?? this.departureReason,
      lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
      migrationWarning: clearMigrationWarning
          ? null
          : migrationWarning ?? this.migrationWarning,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'ptipoteId': ptipoteId,
        'acquisitionOrigin': acquisitionOrigin.name,
        'ownershipMode': ownershipMode.name,
        'ptipoteGeneration': ptipoteGeneration.name,
        'typeId': typeId.name,
        'natureId': natureId,
        'coreId': coreId,
        'envelopeId': envelopeId,
        'envelopeAcquisitionMode': envelopeAcquisitionMode,
        'envelopeSymbiosis': envelopeSymbiosis?.toFirebase(),
        'protocolEfficiencyMultiplier': protocolEfficiencyMultiplier,
        'systemName': systemName,
        'displayName': displayName,
        'arrivalState': arrivalState.name,
        'arrivalCreatedAt': arrivalCreatedAt?.toIso8601String(),
        'rhythmSeed': rhythmSeed,
        'rhythmPattern': rhythmPattern,
        'rhythmAttemptCount': rhythmAttemptCount,
        'hatchedAt': hatchedAt?.toIso8601String(),
        'namedAt': namedAt?.toIso8601String(),
        'moodId': moodId,
        'moodUpdatedAt': moodUpdatedAt?.toIso8601String(),
        'passionId': passionId,
        'skills': skills.map((key, value) => MapEntry(key, value.toFirebase())),
        'baseCarryCapacity': baseCarryCapacity,
        'externalCarryCapacityBonus': externalCarryCapacityBonus,
        'visualAssetKey': visualAssetKey,
        'coBreedingSessionId': coBreedingSessionId,
        'coBreedingStartedAt': coBreedingStartedAt?.toIso8601String(),
        'coBreedingExpiresAt': coBreedingExpiresAt?.toIso8601String(),
        'departurePending': departurePending,
        'departureReason': departureReason,
        'lifecycleStatus': lifecycleStatus.name,
        'migrationWarning': migrationWarning,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory PtipoteV2Profile.fromFirebase(
    String fallbackId,
    Map<dynamic, dynamic> value,
  ) {
    final timestamp = DateTime.now();
    final envelopeId = _canonicalEnvelopeId(
      _nullableText(value['envelopeId']),
    );
    final storedSymbiosis = value['envelopeSymbiosis'] is Map
        ? PtipoteEnvelopeSymbiosis.fromFirebase(
            value['envelopeSymbiosis'] as Map)
        : null;
    final rawSkills = value['skills'];
    final skills = <String, PtipoteSkillProgress>{};
    if (rawSkills is Map) {
      for (final entry in rawSkills.entries) {
        if (entry.value is Map) {
          final parsed = PtipoteSkillProgress.fromFirebase(entry.value as Map);
          if (parsed.skillId.isNotEmpty) skills['${entry.key}'] = parsed;
        }
      }
    }
    return PtipoteV2Profile(
      ptipoteId: '${value['ptipoteId'] ?? fallbackId}',
      acquisitionOrigin: _enumByName(
        PtipoteAcquisitionOrigin.values,
        value['acquisitionOrigin'],
        PtipoteAcquisitionOrigin.legacyMigration,
      ),
      ownershipMode: _enumByName(
        PtipoteOwnershipMode.values,
        value['ownershipMode'],
        PtipoteOwnershipMode.owned,
      ),
      ptipoteGeneration: _enumByName(
        PtipoteGeneration.values,
        value['ptipoteGeneration'],
        PtipoteGeneration.vestige,
      ),
      typeId: _enumByName(
        PtipoteTypeId.values,
        value['typeId'],
        PtipoteTypeId.vegetal,
      ),
      natureId: '${value['natureId'] ?? 'unknown'}',
      coreId: _nullableText(value['coreId']),
      envelopeId: envelopeId,
      envelopeAcquisitionMode: _nullableText(value['envelopeAcquisitionMode']),
      // Existing equipped Protocols become a coherent "new envelope" state
      // rather than losing their equipment or receiving a silent bonus.
      envelopeSymbiosis: storedSymbiosis ??
          (envelopeId == null
              ? null
              : PtipoteEnvelopeSymbiosis(
                  envelopeId: envelopeId,
                  symbiosisLevel: 0,
                  symbiosisProgressPercent: 0,
                  startedAt: timestamp,
                  lastCalculatedAt: timestamp,
                  createdAt: timestamp,
                  updatedAt: timestamp,
                )),
      protocolEfficiencyMultiplier:
          (value['protocolEfficiencyMultiplier'] as num?)?.toDouble(),
      systemName: '${value['systemName'] ?? ''}',
      displayName: '${value['displayName'] ?? ''}',
      arrivalState: _enumByName(
        PtipoteArrivalState.values,
        value['arrivalState'],
        PtipoteArrivalState.completed,
      ),
      arrivalCreatedAt: _readDate(value['arrivalCreatedAt']),
      rhythmSeed: (value['rhythmSeed'] as num?)?.round(),
      rhythmPattern: value['rhythmPattern'] is List
          ? (value['rhythmPattern'] as List)
              .map((entry) => (entry as num?)?.round() ?? 0)
              .where((entry) => entry >= 0)
              .toList()
          : const <int>[],
      rhythmAttemptCount:
          (value['rhythmAttemptCount'] as num?)?.round().clamp(0, 9999) ?? 0,
      hatchedAt: _readDate(value['hatchedAt']),
      namedAt: _readDate(value['namedAt']),
      moodId: _nullableText(value['moodId']),
      moodUpdatedAt: _readDate(value['moodUpdatedAt']),
      passionId: _nullableText(value['passionId']),
      skills: skills,
      baseCarryCapacity:
          ((value['baseCarryCapacity'] as num?)?.round() ?? 20).clamp(1, 9999),
      externalCarryCapacityBonus:
          ((value['externalCarryCapacityBonus'] as num?)?.round() ?? 0)
              .clamp(0, 9999),
      visualAssetKey: '${value['visualAssetKey'] ?? ''}',
      coBreedingSessionId: _nullableText(value['coBreedingSessionId']),
      coBreedingStartedAt: _readDate(value['coBreedingStartedAt']),
      coBreedingExpiresAt: _readDate(value['coBreedingExpiresAt']),
      departurePending: value['departurePending'] is bool
          ? value['departurePending'] as bool
          : false,
      departureReason: _nullableText(value['departureReason']),
      lifecycleStatus: _enumByName(
        PtipoteLifecycleStatus.values,
        value['lifecycleStatus'],
        PtipoteLifecycleStatus.active,
      ),
      migrationWarning: _nullableText(value['migrationWarning']),
      createdAt: _readDate(value['createdAt']),
      updatedAt: _readDate(value['updatedAt']),
    );
  }
}

class GatherBonusSet {
  const GatherBonusSet({
    this.organic = 0,
    this.mineral = 0,
    this.waste = 0,
    this.mycelium = 0,
    this.genericGather = 0,
  });

  final double organic;
  final double mineral;
  final double waste;
  final double mycelium;
  final double genericGather;

  double forResource(String resource) => switch (resource) {
        'Organique' => organic + genericGather,
        'Minéral' => mineral + genericGather,
        'Déchets' => waste + genericGather,
        'Mycélium' => mycelium + genericGather,
        _ => genericGather,
      };

  GatherBonusSet add(GatherBonusSet other) => GatherBonusSet(
        organic: organic + other.organic,
        mineral: mineral + other.mineral,
        waste: waste + other.waste,
        mycelium: mycelium + other.mycelium,
        genericGather: genericGather + other.genericGather,
      );

  GatherBonusSet scale(double value) => GatherBonusSet(
        organic: organic * value,
        mineral: mineral * value,
        waste: waste * value,
        mycelium: mycelium * value,
        genericGather: genericGather * value,
      );
}

class WeatherMitigationSet {
  const WeatherMitigationSet({this.heat = 0, this.rain = 0, this.toxic = 0});

  final double heat;
  final double rain;
  final double toxic;

  WeatherMitigationSet add(WeatherMitigationSet other) => WeatherMitigationSet(
        heat: heat + other.heat,
        rain: rain + other.rain,
        toxic: toxic + other.toxic,
      );

  WeatherMitigationSet scale(double value) => WeatherMitigationSet(
        heat: heat * value,
        rain: rain * value,
        toxic: toxic * value,
      );
}

class PtipoteEffectiveModifiers {
  const PtipoteEffectiveModifiers({
    required this.gather,
    required this.weather,
    this.craftBonus = 0,
    this.commerceBonus = 0,
    this.securityBonus = 0,
    this.towerDefenseBonus = 0,
    this.missionSecurityBonus = 0,
    this.droneDefenseBonus = 0,
    this.carryCapacityBonus = 0,
    this.ownCoreExplorationBonus = 0,
    this.analystOwnCoreExplorationBonus = 0,
  });

  final GatherBonusSet gather;
  final WeatherMitigationSet weather;
  final double craftBonus;
  final double commerceBonus;
  final double securityBonus;
  final double towerDefenseBonus;
  final double missionSecurityBonus;
  final double droneDefenseBonus;
  final double carryCapacityBonus;
  final double ownCoreExplorationBonus;
  final double analystOwnCoreExplorationBonus;
}

/// All scalar V2 tuning lives here so the Dashboard and the game share one
/// configuration document. Values are fractions: 0.10 = +10%.
class PtipoteV2Config {
  const PtipoteV2Config({
    required this.defaultBaseCarryCapacity,
    required this.coreOnlyEfficiency,
    required this.newEnvelopeEfficiency,
    required this.habituatedEnvelopeEfficiency,
    required this.adoptedEnvelopeEfficiency,
    required this.mineralTowerDefenseBonus,
    required this.mineralMissionSecurityBonus,
    required this.mineralGatherBonus,
    required this.vegetalCraftBonus,
    required this.vegetalHeatMitigation,
    required this.vegetalOrganicGatherBonus,
    required this.mycelialCraftBonus,
    required this.mycelialCommerceBonus,
    required this.mycelialToxicMitigation,
    required this.mycelialOrganicGatherBonus,
    required this.mycelialWasteGatherBonus,
    required this.defenseSecurityBonus,
    required this.defenseDroneDefenseBonus,
    required this.defenseCarryCapacityBonus,
    required this.explorationGatherBonus,
    required this.explorationSecurityBonus,
    required this.explorationAllWeatherMitigation,
    required this.productionGatherBonus,
    required this.productionCraftBonus,
    required this.analystCraftBonus,
    required this.analystSaleBonus,
    required this.analystOwnCoreExplorationBonus,
    required this.analystGroupCountCap,
    required this.enableIncubator,
    required this.enableRhythmHatching,
    required this.eggVegetalColor,
    required this.eggMineralColor,
    required this.eggMycelialColor,
    required this.arrivalInitialLevel,
    required this.arrivalInitialXp,
    required this.rhythmSequenceLength,
    required this.rhythmTimingToleranceMs,
    required this.rhythmMinIntervalMs,
    required this.rhythmMaxIntervalMs,
    required this.rhythmRetryPolicy,
    required this.rhythmVisualCueEnabled,
    required this.rhythmHapticEnabled,
    required this.rhythmSoundEnabled,
    required this.coBreedingEnabled,
    required this.coBreedingKernelUnlockLevel,
    required this.coBreedingMaxDurationHours,
    required this.coBreedingFinalProtectionWindowHours,
    required this.coBreedingOfflineGuaranteedRemainingHours,
    required this.coBreedingCapacityPerBreederLevel,
    required this.coBreedingLevelEarlyDeparture,
    required this.coBreedingOfferRotationHours,
    required this.coBreedingChooseTypeCost,
    required this.coBreedingChooseExactPtipoteCost,
    required this.coBreedingChooseExactEnvelopeCost,
    required this.coBreedingInitialFreeEnabled,
    required this.envelopeUnlockPtipoteLevel,
    required this.symbiosisPercentPerHour,
    required this.symbiosisPercentPerActivity,
    required this.symbiosisMaxLevel,
    required this.symbiosisProgressRequiredPerLevel,
    required this.coBreedingCompletionRequireHouse,
    required this.coBreedingCompletionBlockNewActivity,
    required this.coBreedingCompletionArchive,
    required this.coBreedingXpRewardBase,
    required this.coBreedingXpRewardPerFinalLevel,
    required this.coBreedingBreederXpRewardBase,
    required this.coBreedingBreederXpRewardPerFinalLevel,
    required this.coBreedingKernelTrustRewardBase,
    required this.coBreedingKernelTrustRewardPerFinalLevel,
  });

  final int defaultBaseCarryCapacity;
  final double coreOnlyEfficiency;
  final double newEnvelopeEfficiency;
  final double habituatedEnvelopeEfficiency;
  final double adoptedEnvelopeEfficiency;
  final double mineralTowerDefenseBonus;
  final double mineralMissionSecurityBonus;
  final double mineralGatherBonus;
  final double vegetalCraftBonus;
  final double vegetalHeatMitigation;
  final double vegetalOrganicGatherBonus;
  final double mycelialCraftBonus;
  final double mycelialCommerceBonus;
  final double mycelialToxicMitigation;
  final double mycelialOrganicGatherBonus;
  final double mycelialWasteGatherBonus;
  final double defenseSecurityBonus;
  final double defenseDroneDefenseBonus;
  final double defenseCarryCapacityBonus;
  final double explorationGatherBonus;
  final double explorationSecurityBonus;
  final double explorationAllWeatherMitigation;
  final double productionGatherBonus;
  final double productionCraftBonus;
  final double analystCraftBonus;
  final double analystSaleBonus;
  final double analystOwnCoreExplorationBonus;
  final int analystGroupCountCap;
  final bool enableIncubator;
  final bool enableRhythmHatching;
  final String eggVegetalColor;
  final String eggMineralColor;
  final String eggMycelialColor;
  final int arrivalInitialLevel;
  final int arrivalInitialXp;
  final int rhythmSequenceLength;
  final int rhythmTimingToleranceMs;
  final int rhythmMinIntervalMs;
  final int rhythmMaxIntervalMs;
  final String rhythmRetryPolicy;
  final bool rhythmVisualCueEnabled;
  final bool rhythmHapticEnabled;
  final bool rhythmSoundEnabled;
  final bool coBreedingEnabled;
  final int coBreedingKernelUnlockLevel;
  final int coBreedingMaxDurationHours;
  final int coBreedingFinalProtectionWindowHours;
  final int coBreedingOfflineGuaranteedRemainingHours;
  final int coBreedingCapacityPerBreederLevel;
  final int coBreedingLevelEarlyDeparture;
  final int coBreedingOfferRotationHours;
  final int coBreedingChooseTypeCost;
  final int coBreedingChooseExactPtipoteCost;
  final int coBreedingChooseExactEnvelopeCost;
  final bool coBreedingInitialFreeEnabled;
  final int envelopeUnlockPtipoteLevel;
  final double symbiosisPercentPerHour;
  final double symbiosisPercentPerActivity;
  final int symbiosisMaxLevel;
  final double symbiosisProgressRequiredPerLevel;
  final bool coBreedingCompletionRequireHouse;
  final bool coBreedingCompletionBlockNewActivity;
  final bool coBreedingCompletionArchive;
  final int coBreedingXpRewardBase;
  final int coBreedingXpRewardPerFinalLevel;
  final int coBreedingBreederXpRewardBase;
  final int coBreedingBreederXpRewardPerFinalLevel;
  final int coBreedingKernelTrustRewardBase;
  final int coBreedingKernelTrustRewardPerFinalLevel;

  Map<String, dynamic> toDashboardMap() => <String, dynamic>{
        'v2DefaultBaseCarryCapacity': defaultBaseCarryCapacity,
        'v2CoreOnlyEfficiency': coreOnlyEfficiency,
        'v2NewEnvelopeEfficiency': newEnvelopeEfficiency,
        'v2HabituatedEnvelopeEfficiency': habituatedEnvelopeEfficiency,
        'v2AdoptedEnvelopeEfficiency': adoptedEnvelopeEfficiency,
        'v2MineralTowerDefenseBonus': mineralTowerDefenseBonus,
        'v2MineralMissionSecurityBonus': mineralMissionSecurityBonus,
        'v2MineralGatherBonus': mineralGatherBonus,
        'v2VegetalCraftBonus': vegetalCraftBonus,
        'v2VegetalHeatMitigation': vegetalHeatMitigation,
        'v2VegetalOrganicGatherBonus': vegetalOrganicGatherBonus,
        'v2MycelialCraftBonus': mycelialCraftBonus,
        'v2MycelialCommerceBonus': mycelialCommerceBonus,
        'v2MycelialToxicMitigation': mycelialToxicMitigation,
        'v2MycelialOrganicGatherBonus': mycelialOrganicGatherBonus,
        'v2MycelialWasteGatherBonus': mycelialWasteGatherBonus,
        'v2DefenseSecurityBonus': defenseSecurityBonus,
        'v2DefenseDroneDefenseBonus': defenseDroneDefenseBonus,
        'v2DefenseCarryCapacityBonus': defenseCarryCapacityBonus,
        'v2ExplorationGatherBonus': explorationGatherBonus,
        'v2ExplorationSecurityBonus': explorationSecurityBonus,
        'v2ExplorationAllWeatherMitigation': explorationAllWeatherMitigation,
        'v2ProductionGatherBonus': productionGatherBonus,
        'v2ProductionCraftBonus': productionCraftBonus,
        'v2AnalystCraftBonus': analystCraftBonus,
        'v2AnalystSaleBonus': analystSaleBonus,
        'v2AnalystOwnCoreExplorationBonus': analystOwnCoreExplorationBonus,
        'v2AnalystGroupCountCap': analystGroupCountCap,
        'v2EnableIncubator': enableIncubator ? 1 : 0,
        'v2EnableRhythmHatching': enableRhythmHatching ? 1 : 0,
        'v2EggVegetalColor': eggVegetalColor,
        'v2EggMineralColor': eggMineralColor,
        'v2EggMycelialColor': eggMycelialColor,
        'v2ArrivalInitialLevel': arrivalInitialLevel,
        'v2ArrivalInitialXp': arrivalInitialXp,
        'v2RhythmSequenceLength': rhythmSequenceLength,
        'v2RhythmTimingToleranceMs': rhythmTimingToleranceMs,
        'v2RhythmMinIntervalMs': rhythmMinIntervalMs,
        'v2RhythmMaxIntervalMs': rhythmMaxIntervalMs,
        'v2RhythmRetryPolicy': rhythmRetryPolicy,
        'v2RhythmVisualCueEnabled': rhythmVisualCueEnabled ? 1 : 0,
        'v2RhythmHapticEnabled': rhythmHapticEnabled ? 1 : 0,
        'v2RhythmSoundEnabled': rhythmSoundEnabled ? 1 : 0,
        'v2CoBreedingEnabled': coBreedingEnabled ? 1 : 0,
        'v2CoBreedingKernelUnlockLevel': coBreedingKernelUnlockLevel,
        'v2CoBreedingMaxDurationHours': coBreedingMaxDurationHours,
        'v2CoBreedingFinalProtectionWindowHours':
            coBreedingFinalProtectionWindowHours,
        'v2CoBreedingOfflineGuaranteedRemainingHours':
            coBreedingOfflineGuaranteedRemainingHours,
        'v2CoBreedingCapacityPerBreederLevel':
            coBreedingCapacityPerBreederLevel,
        'v2CoBreedingLevelEarlyDeparture': coBreedingLevelEarlyDeparture,
        'v2CoBreedingOfferRotationHours': coBreedingOfferRotationHours,
        'v2CoBreedingChooseTypeCost': coBreedingChooseTypeCost,
        'v2CoBreedingChooseExactPtipoteCost': coBreedingChooseExactPtipoteCost,
        'v2CoBreedingChooseExactEnvelopeCost':
            coBreedingChooseExactEnvelopeCost,
        'v2CoBreedingInitialFreeEnabled': coBreedingInitialFreeEnabled ? 1 : 0,
        'v2EnvelopeUnlockPtipoteLevel': envelopeUnlockPtipoteLevel,
        'v2SymbiosisPercentPerHour': symbiosisPercentPerHour,
        'v2SymbiosisPercentPerActivity': symbiosisPercentPerActivity,
        'v2SymbiosisMaxLevel': symbiosisMaxLevel,
        'v2SymbiosisProgressRequiredPerLevel':
            symbiosisProgressRequiredPerLevel,
        'v2CoBreedingCompletionRequireHouse':
            coBreedingCompletionRequireHouse ? 1 : 0,
        'v2CoBreedingCompletionBlockNewActivity':
            coBreedingCompletionBlockNewActivity ? 1 : 0,
        'v2CoBreedingCompletionArchive': coBreedingCompletionArchive ? 1 : 0,
        'v2CoBreedingXpRewardBase': coBreedingXpRewardBase,
        'v2CoBreedingXpRewardPerFinalLevel': coBreedingXpRewardPerFinalLevel,
        'v2CoBreedingBreederXpRewardBase': coBreedingBreederXpRewardBase,
        'v2CoBreedingBreederXpRewardPerFinalLevel':
            coBreedingBreederXpRewardPerFinalLevel,
        'v2CoBreedingKernelTrustRewardBase': coBreedingKernelTrustRewardBase,
        'v2CoBreedingKernelTrustRewardPerFinalLevel':
            coBreedingKernelTrustRewardPerFinalLevel,
      };
}

const defaultPtipoteV2Config = PtipoteV2Config(
  defaultBaseCarryCapacity: 20,
  coreOnlyEfficiency: 0.50,
  newEnvelopeEfficiency: 0.75,
  habituatedEnvelopeEfficiency: 1.00,
  adoptedEnvelopeEfficiency: 1.25,
  mineralTowerDefenseBonus: 0.10,
  mineralMissionSecurityBonus: 0.10,
  mineralGatherBonus: 0.10,
  vegetalCraftBonus: 0.05,
  vegetalHeatMitigation: 0.05,
  vegetalOrganicGatherBonus: 0.20,
  mycelialCraftBonus: 0.05,
  mycelialCommerceBonus: 0.10,
  mycelialToxicMitigation: 0.05,
  mycelialOrganicGatherBonus: 0.10,
  mycelialWasteGatherBonus: 0.10,
  defenseSecurityBonus: 0.25,
  defenseDroneDefenseBonus: 0.25,
  defenseCarryCapacityBonus: 0.30,
  explorationGatherBonus: 0.15,
  explorationSecurityBonus: 0.10,
  explorationAllWeatherMitigation: 0.05,
  productionGatherBonus: 0.25,
  productionCraftBonus: 0.20,
  analystCraftBonus: 0.10,
  analystSaleBonus: 0.25,
  analystOwnCoreExplorationBonus: 0.10,
  analystGroupCountCap: 12,
  enableIncubator: true,
  enableRhythmHatching: true,
  eggVegetalColor: '#7DAA5A',
  eggMineralColor: '#7C8DA8',
  eggMycelialColor: '#9A74AA',
  arrivalInitialLevel: 1,
  arrivalInitialXp: 0,
  rhythmSequenceLength: 4,
  rhythmTimingToleranceMs: 600,
  rhythmMinIntervalMs: 420,
  rhythmMaxIntervalMs: 820,
  rhythmRetryPolicy: 'samePatternUntilSuccess',
  rhythmVisualCueEnabled: true,
  rhythmHapticEnabled: true,
  rhythmSoundEnabled: false,
  coBreedingEnabled: true,
  coBreedingKernelUnlockLevel: 2,
  coBreedingMaxDurationHours: 168,
  coBreedingFinalProtectionWindowHours: 48,
  coBreedingOfflineGuaranteedRemainingHours: 24,
  coBreedingCapacityPerBreederLevel: 1,
  coBreedingLevelEarlyDeparture: 7,
  coBreedingOfferRotationHours: 24,
  coBreedingChooseTypeCost: 5,
  coBreedingChooseExactPtipoteCost: 8,
  coBreedingChooseExactEnvelopeCost: 6,
  coBreedingInitialFreeEnabled: true,
  envelopeUnlockPtipoteLevel: 3,
  symbiosisPercentPerHour: 1,
  symbiosisPercentPerActivity: 1,
  symbiosisMaxLevel: 2,
  symbiosisProgressRequiredPerLevel: 100,
  coBreedingCompletionRequireHouse: true,
  coBreedingCompletionBlockNewActivity: true,
  coBreedingCompletionArchive: true,
  // Provisional V1 rewards: a base plus final-level scaling, all Dashboard
  // controlled and deliberately identical for Vestiges and Protocoles.
  coBreedingXpRewardBase: 10,
  coBreedingXpRewardPerFinalLevel: 5,
  coBreedingBreederXpRewardBase: 5,
  coBreedingBreederXpRewardPerFinalLevel: 3,
  coBreedingKernelTrustRewardBase: 1,
  coBreedingKernelTrustRewardPerFinalLevel: 1,
);

/// Resolves the envelope relationship from persisted timestamps. The service
/// deliberately stores the fractional percentage so reconnecting never loses
/// the half-hour (or smaller) remainder.
class EnvelopeSymbiosisService {
  const EnvelopeSymbiosisService._();

  static PtipoteEnvelopeSymbiosis resolveTime(
    PtipoteEnvelopeSymbiosis symbiosis, {
    required PtipoteV2Config config,
    required DateTime now,
  }) {
    if (symbiosis.maxLevelReached ||
        symbiosis.symbiosisLevel >= config.symbiosisMaxLevel) {
      return symbiosis;
    }
    final elapsedMs = now.difference(symbiosis.lastCalculatedAt).inMilliseconds;
    if (elapsedMs <= 0) return symbiosis;
    final increase = elapsedMs /
        Duration.millisecondsPerHour *
        config.symbiosisPercentPerHour;
    return _apply(
      symbiosis,
      increase: increase,
      config: config,
      calculatedAt: now,
    );
  }

  static PtipoteEnvelopeSymbiosis addActivity(
    PtipoteEnvelopeSymbiosis symbiosis, {
    required PtipoteV2Config config,
    required DateTime now,
  }) {
    final timed = resolveTime(symbiosis, config: config, now: now);
    if (timed.maxLevelReached ||
        timed.symbiosisLevel >= config.symbiosisMaxLevel) {
      return timed;
    }
    return _apply(
      timed,
      increase: config.symbiosisPercentPerActivity,
      config: config,
      calculatedAt: now,
      activityAt: now,
    );
  }

  static PtipoteEnvelopeSymbiosis _apply(
    PtipoteEnvelopeSymbiosis current, {
    required double increase,
    required PtipoteV2Config config,
    required DateTime calculatedAt,
    DateTime? activityAt,
  }) {
    var level = current.symbiosisLevel.clamp(0, config.symbiosisMaxLevel);
    var progress = current.symbiosisProgressPercent + increase;
    final required = config.symbiosisProgressRequiredPerLevel;
    while (level < config.symbiosisMaxLevel && progress >= required) {
      progress -= required;
      level += 1;
    }
    final isMax = level >= config.symbiosisMaxLevel;
    return current.copyWith(
      symbiosisLevel: level,
      symbiosisProgressPercent: isMax ? 0 : progress,
      lastCalculatedAt: calculatedAt,
      lastActivityBonusAt: activityAt ?? current.lastActivityBonusAt,
      maxLevelReached: isMax,
      updatedAt: calculatedAt,
    );
  }
}

/// The single business state machine for the Maison Couveuse.
///
/// Widgets only render the state and collect taps. They never decide whether
/// a P'TIPOTE is active, hatch an egg twice, or regenerate a rhythm pattern.
class PtipoteArrivalService {
  const PtipoteArrivalService._();

  static PtipoteV2Profile sendPtipoteToIncubator({
    required PtipoteV2Profile profile,
    required PtipoteV2Config config,
    required String systemName,
    DateTime? now,
  }) {
    if (profile.isArrivalComplete ||
        (profile.isAwaitingIncubator && profile.rhythmPattern.isNotEmpty)) {
      return profile;
    }
    final timestamp = now ?? DateTime.now();
    final stableSystemName = systemName.trim().isEmpty
        ? (profile.systemName.trim().isEmpty ? 'P’TIPOTE' : profile.systemName)
        : systemName.trim();
    final seed = profile.rhythmSeed ?? _stableSeed(profile.ptipoteId);
    final pattern = profile.rhythmPattern.isEmpty
        ? generateRhythmPattern(seed: seed, config: config)
        : profile.rhythmPattern;
    return profile.copyWith(
      systemName: stableSystemName,
      displayName: '',
      arrivalState: PtipoteArrivalState.pendingEgg,
      arrivalCreatedAt: timestamp,
      rhythmSeed: seed,
      rhythmPattern: pattern,
      rhythmAttemptCount: 0,
      updatedAt: timestamp,
    );
  }

  static PtipoteV2Profile prepareRhythm(
    PtipoteV2Profile profile, {
    required PtipoteV2Config config,
    DateTime? now,
  }) {
    if (profile.isArrivalComplete ||
        profile.arrivalState == PtipoteArrivalState.hatched ||
        profile.arrivalState == PtipoteArrivalState.naming) {
      return profile;
    }
    final seed = profile.rhythmSeed ?? _stableSeed(profile.ptipoteId);
    return profile.copyWith(
      arrivalState: PtipoteArrivalState.rhythmReady,
      rhythmSeed: seed,
      rhythmPattern: profile.rhythmPattern.isEmpty
          ? generateRhythmPattern(seed: seed, config: config)
          : profile.rhythmPattern,
      updatedAt: now ?? DateTime.now(),
    );
  }

  static PtipoteV2Profile beginRhythm(
    PtipoteV2Profile profile, {
    DateTime? now,
  }) {
    if (profile.arrivalState != PtipoteArrivalState.rhythmReady) {
      return profile;
    }
    return profile.copyWith(
      arrivalState: PtipoteArrivalState.rhythmInProgress,
      updatedAt: now ?? DateTime.now(),
    );
  }

  static PtipoteV2Profile failRhythm(
    PtipoteV2Profile profile, {
    DateTime? now,
  }) {
    if (profile.isArrivalComplete) return profile;
    return profile.copyWith(
      arrivalState: PtipoteArrivalState.rhythmReady,
      rhythmAttemptCount: profile.rhythmAttemptCount + 1,
      updatedAt: now ?? DateTime.now(),
    );
  }

  static PtipoteV2Profile hatch(
    PtipoteV2Profile profile, {
    DateTime? now,
  }) {
    if (profile.isArrivalComplete ||
        profile.arrivalState == PtipoteArrivalState.hatched ||
        profile.arrivalState == PtipoteArrivalState.naming) {
      return profile;
    }
    final timestamp = now ?? DateTime.now();
    return profile.copyWith(
      arrivalState: PtipoteArrivalState.hatched,
      hatchedAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static PtipoteV2Profile startNaming(
    PtipoteV2Profile profile, {
    DateTime? now,
  }) {
    if (profile.arrivalState != PtipoteArrivalState.hatched) return profile;
    return profile.copyWith(
      arrivalState: PtipoteArrivalState.naming,
      updatedAt: now ?? DateTime.now(),
    );
  }

  static PtipoteV2Profile finalizeNaming(
    PtipoteV2Profile profile, {
    required String displayName,
    DateTime? now,
  }) {
    if (profile.isArrivalComplete) return profile;
    final timestamp = now ?? DateTime.now();
    final fallback = profile.systemName.trim().isEmpty
        ? 'P’TIPOTE'
        : profile.systemName.trim();
    final selectedName =
        displayName.trim().isEmpty ? fallback : displayName.trim();
    return profile.copyWith(
      displayName: selectedName,
      arrivalState: PtipoteArrivalState.completed,
      namedAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// An interrupted app never leaves an egg locked in a modal state.
  static PtipoteV2Profile resumeAfterInterruption(
    PtipoteV2Profile profile, {
    DateTime? now,
  }) {
    if (profile.arrivalState != PtipoteArrivalState.rhythmInProgress) {
      return profile;
    }
    return profile.copyWith(
      arrivalState: PtipoteArrivalState.rhythmReady,
      updatedAt: now ?? DateTime.now(),
    );
  }

  static List<int> generateRhythmPattern({
    required int seed,
    required PtipoteV2Config config,
  }) {
    final length = config.rhythmSequenceLength.clamp(3, 5);
    final minGap = config.rhythmMinIntervalMs.clamp(100, 5000);
    final maxGap = config.rhythmMaxIntervalMs.clamp(minGap, 5000);
    var state = seed == 0 ? 1 : seed.abs();
    final pattern = <int>[0];
    for (var index = 1; index < length; index += 1) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      final gap = minGap + (state % (maxGap - minGap + 1));
      pattern.add(pattern.last + gap);
    }
    return pattern;
  }

  static String eggColorHex(PtipoteTypeId type, PtipoteV2Config config) =>
      switch (type) {
        PtipoteTypeId.vegetal => config.eggVegetalColor,
        PtipoteTypeId.mineral => config.eggMineralColor,
        PtipoteTypeId.mycelial => config.eggMycelialColor,
      };

  static int _stableSeed(String value) {
    var hash = 17;
    for (final codeUnit in value.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}

/// Versioned V2 envelope catalogue. Compatibility stays permissive until the
/// Protocol content pack supplies explicit core/envelope pairings.
const ptipoteV2EnvelopeDefinitions = <PtipoteEnvelopeCategory, PtipoteEnvelope>{
  PtipoteEnvelopeCategory.defense: PtipoteEnvelope(
    envelopeId: 'defense',
    displayName: 'Défense',
    envelopeCategory: PtipoteEnvelopeCategory.defense,
    combinedAssetSuffix: 'defense',
  ),
  PtipoteEnvelopeCategory.exploration: PtipoteEnvelope(
    envelopeId: 'exploration',
    displayName: 'Exploration',
    envelopeCategory: PtipoteEnvelopeCategory.exploration,
    combinedAssetSuffix: 'exploration',
  ),
  PtipoteEnvelopeCategory.production: PtipoteEnvelope(
    envelopeId: 'production',
    displayName: 'Production',
    envelopeCategory: PtipoteEnvelopeCategory.production,
    combinedAssetSuffix: 'production',
  ),
  PtipoteEnvelopeCategory.analyst: PtipoteEnvelope(
    envelopeId: 'analyst',
    displayName: 'Analyste',
    envelopeCategory: PtipoteEnvelopeCategory.analyst,
    combinedAssetSuffix: 'analyst',
  ),
};

PtipoteCore protocolCoreFor({
  required String natureId,
  required PtipoteTypeId typeId,
  String baseImageAsset = '',
}) {
  final normalizedNature = normalizePtipoteAssetKey(natureId);
  return PtipoteCore(
    coreId: 'core_$normalizedNature',
    displayName:
        normalizedNature.isEmpty ? 'Noyau Protocole' : normalizedNature,
    natureId: normalizedNature.isEmpty ? 'unknown' : normalizedNature,
    typeId: typeId,
    baseImageAsset: baseImageAsset,
    compatibleEnvelopeIds: ptipoteV2EnvelopeDefinitions.values
        .map((envelope) => envelope.envelopeId)
        .toSet(),
  );
}

class PtipoteModifierService {
  const PtipoteModifierService._();

  static PtipoteEffectiveModifiers resolve({
    required PtipoteV2Profile profile,
    required PtipoteV2Config config,
    required double mycelialGatherBonus,
    PtipoteCore? core,
    int eligibleGroupPtipoteCount = 1,
  }) {
    final efficiency = profile.effectiveProtocolEfficiency(config);
    var gather = _typeGather(profile.typeId, config, mycelialGatherBonus);
    var weather = _typeWeather(profile.typeId, config);
    var craft = _typeCraft(profile.typeId, config);
    var commerce = _typeCommerce(profile.typeId, config);
    var security = profile.typeId == PtipoteTypeId.mineral
        ? config.mineralMissionSecurityBonus
        : 0.0;
    var towerDefense = profile.typeId == PtipoteTypeId.mineral
        ? config.mineralTowerDefenseBonus
        : 0.0;
    var droneDefense = 0.0;
    var carryBonus = 0.0;
    var ownCoreExploration = 0.0;
    var analystCoreExploration = 0.0;

    if (profile.envelopeId != null) {
      switch (_envelopeCategory(profile.envelopeId!)) {
        case PtipoteEnvelopeCategory.defense:
          security += config.defenseSecurityBonus;
          droneDefense += config.defenseDroneDefenseBonus;
          carryBonus += config.defenseCarryCapacityBonus;
        case PtipoteEnvelopeCategory.exploration:
          gather = gather.add(
            GatherBonusSet(genericGather: config.explorationGatherBonus),
          );
          security += config.explorationSecurityBonus;
          weather = weather.add(
            WeatherMitigationSet(
              heat: config.explorationAllWeatherMitigation,
              rain: config.explorationAllWeatherMitigation,
              toxic: config.explorationAllWeatherMitigation,
            ),
          );
        case PtipoteEnvelopeCategory.production:
          gather = gather.add(
            GatherBonusSet(genericGather: config.productionGatherBonus),
          );
          craft += config.productionCraftBonus;
        case PtipoteEnvelopeCategory.analyst:
          craft += config.analystCraftBonus;
          commerce += config.analystSaleBonus;
          ownCoreExploration = core?.baseBonuses['exploration'] ??
              config.analystOwnCoreExplorationBonus;
      }
    }

    // A Protocol's functional core/type bonuses are scaled as a single set.
    // Vestiges use 100% of their functional modifiers.
    if (profile.isProtocol) {
      gather = gather.scale(efficiency);
      weather = weather.scale(efficiency);
      craft *= efficiency;
      commerce *= efficiency;
      security *= efficiency;
      towerDefense *= efficiency;
      droneDefense *= efficiency;
      carryBonus *= efficiency;
      ownCoreExploration *= efficiency;
    }
    final safeGroup =
        eligibleGroupPtipoteCount.clamp(1, config.analystGroupCountCap);
    analystCoreExploration = profile.envelopeId != null &&
            _envelopeCategory(profile.envelopeId!) ==
                PtipoteEnvelopeCategory.analyst
        ? ownCoreExploration * safeGroup
        : 0;
    return PtipoteEffectiveModifiers(
      gather: gather,
      weather: weather,
      craftBonus: craft,
      commerceBonus: commerce,
      securityBonus: security,
      towerDefenseBonus: towerDefense,
      missionSecurityBonus: security,
      droneDefenseBonus: droneDefense,
      carryCapacityBonus: carryBonus,
      ownCoreExplorationBonus: ownCoreExploration,
      analystOwnCoreExplorationBonus: analystCoreExploration,
    );
  }

  static int effectiveCarryCapacity({
    required PtipoteV2Profile profile,
    required PtipoteEffectiveModifiers modifiers,
  }) {
    final total =
        (profile.baseCarryCapacity + profile.externalCarryCapacityBonus) *
            (1 + modifiers.carryCapacityBonus);
    return total.ceil().clamp(1, 999999);
  }

  static bool isEnvelopeCompatible({
    required PtipoteCore core,
    required PtipoteEnvelope envelope,
  }) {
    if (!core.enabled || !envelope.enabled) return false;
    if (envelope.compatibilityRule == 'all') return true;
    if (envelope.compatibleCoreIds.contains(core.coreId)) return true;
    return core.compatibleEnvelopeIds.contains(envelope.envelopeId);
  }

  static PtipoteVisualAssetResolution resolveProtocolVisualAsset({
    required String natureId,
    required String coreAssetKey,
    String? envelopeId,
    required Set<String> availableAssetKeys,
  }) {
    final normalizedNature = normalizePtipoteAssetKey(natureId);
    final normalizedEnvelope = normalizePtipoteAssetKey(envelopeId ?? '');
    final combined = normalizedEnvelope.isEmpty
        ? coreAssetKey
        : '${normalizedNature}_$normalizedEnvelope';
    if (availableAssetKeys.contains(combined)) {
      return PtipoteVisualAssetResolution(assetKey: combined);
    }
    return PtipoteVisualAssetResolution(
      assetKey: coreAssetKey,
      warning: normalizedEnvelope.isEmpty
          ? null
          : 'Missing protocol combined asset: $normalizedNature + $normalizedEnvelope',
    );
  }

  static GatherBonusSet _typeGather(
    PtipoteTypeId type,
    PtipoteV2Config config,
    double mycelialGatherBonus,
  ) =>
      switch (type) {
        PtipoteTypeId.vegetal =>
          GatherBonusSet(organic: config.vegetalOrganicGatherBonus),
        PtipoteTypeId.mineral =>
          GatherBonusSet(mineral: config.mineralGatherBonus),
        PtipoteTypeId.mycelial => GatherBonusSet(
            organic: config.mycelialOrganicGatherBonus,
            waste: config.mycelialWasteGatherBonus,
            mycelium: mycelialGatherBonus,
          ),
      };

  static WeatherMitigationSet _typeWeather(
    PtipoteTypeId type,
    PtipoteV2Config config,
  ) =>
      switch (type) {
        PtipoteTypeId.vegetal =>
          WeatherMitigationSet(heat: config.vegetalHeatMitigation),
        PtipoteTypeId.mycelial =>
          WeatherMitigationSet(toxic: config.mycelialToxicMitigation),
        PtipoteTypeId.mineral => const WeatherMitigationSet(),
      };

  static double _typeCraft(PtipoteTypeId type, PtipoteV2Config config) =>
      switch (type) {
        PtipoteTypeId.vegetal => config.vegetalCraftBonus,
        PtipoteTypeId.mycelial => config.mycelialCraftBonus,
        PtipoteTypeId.mineral => 0,
      };

  static double _typeCommerce(PtipoteTypeId type, PtipoteV2Config config) =>
      type == PtipoteTypeId.mycelial ? config.mycelialCommerceBonus : 0;

  static PtipoteEnvelopeCategory _envelopeCategory(String id) {
    final normalized = normalizePtipoteAssetKey(id);
    if (normalized.contains('defense') || normalized.contains('protect')) {
      return PtipoteEnvelopeCategory.defense;
    }
    if (normalized.contains('explor'))
      return PtipoteEnvelopeCategory.exploration;
    if (normalized.contains('product'))
      return PtipoteEnvelopeCategory.production;
    return PtipoteEnvelopeCategory.analyst;
  }
}

class PtipoteVisualAssetResolution {
  const PtipoteVisualAssetResolution({required this.assetKey, this.warning});

  final String assetKey;
  final String? warning;
}

String normalizePtipoteAssetKey(String value) {
  const accents = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
  };
  var normalized = value.trim().toLowerCase();
  for (final entry in accents.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  normalized = normalized.replaceAll(RegExp(r'\s+'), '_');
  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9_]+'), '');
  return normalized
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

PtipoteV2Profile migrateLegacyPtipoteProfile({
  required String ptipoteId,
  required Map<String, String> legacyFields,
  required int defaultBaseCarryCapacity,
  DateTime? now,
}) {
  final elementRaw = legacyFields['elementType'] ??
      legacyFields['element'] ??
      legacyFields['ptipoteType'] ??
      legacyFields['type'] ??
      legacyFields['t'];
  final typeId = _legacyType(elementRaw);
  final typeWasInferred = !_hasKnownLegacyType(elementRaw);
  final species = legacyFields['natureId'] ??
      legacyFields['nature'] ??
      legacyFields['species'] ??
      legacyFields['e'] ??
      legacyFields['t'] ??
      'unknown';
  final natureId = normalizePtipoteAssetKey(species).isEmpty
      ? 'unknown'
      : normalizePtipoteAssetKey(species);
  final rawGeneration =
      '${legacyFields['ptipoteGeneration'] ?? ''}'.toLowerCase();
  final isProtocol = rawGeneration == 'protocol' ||
      legacyFields['coreId']?.trim().isNotEmpty == true;
  final rawTemporary =
      '${legacyFields['isLoaned'] ?? legacyFields['coTraining'] ?? legacyFields['temporary'] ?? ''}'
          .toLowerCase();
  final isTemporary = rawTemporary == '1' || rawTemporary == 'true';
  final timestamp = now ?? DateTime.now();
  final envelopeId = isProtocol
      ? _canonicalEnvelopeId(
          _nullableText(legacyFields['envelopeId'] ?? legacyFields['envelope']),
        )
      : null;
  return PtipoteV2Profile(
    ptipoteId: ptipoteId,
    acquisitionOrigin: PtipoteAcquisitionOrigin.legacyMigration,
    ownershipMode:
        isTemporary ? PtipoteOwnershipMode.coBred : PtipoteOwnershipMode.owned,
    ptipoteGeneration:
        isProtocol ? PtipoteGeneration.protocol : PtipoteGeneration.vestige,
    typeId: typeId,
    natureId: natureId,
    coreId: isProtocol ? legacyFields['coreId'] ?? 'core_$natureId' : null,
    envelopeId: envelopeId,
    envelopeAcquisitionMode: isProtocol
        ? _nullableText(legacyFields['envelopeAcquisitionMode']) ?? 'legacy'
        : null,
    envelopeSymbiosis: envelopeId == null
        ? null
        : PtipoteEnvelopeSymbiosis(
            envelopeId: envelopeId,
            symbiosisLevel: 0,
            symbiosisProgressPercent: 0,
            startedAt: timestamp,
            lastCalculatedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
    baseCarryCapacity: defaultBaseCarryCapacity,
    visualAssetKey: legacyFields['imagePath'] ?? legacyFields['img'] ?? '',
    migrationWarning: typeWasInferred
        ? 'Type legacy non reconnu : Végétal appliqué explicitement en fallback DEV.'
        : null,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

PtipoteTypeId _legacyType(String? value) {
  final normalized = normalizePtipoteAssetKey(value ?? '');
  if (normalized.contains('miner')) return PtipoteTypeId.mineral;
  if (normalized.contains('mycel') ||
      normalized.contains('fung') ||
      normalized.contains('fong')) {
    return PtipoteTypeId.mycelial;
  }
  return PtipoteTypeId.vegetal;
}

bool _hasKnownLegacyType(String? value) {
  final normalized = normalizePtipoteAssetKey(value ?? '');
  return normalized.contains('miner') ||
      normalized.contains('mycel') ||
      normalized.contains('fung') ||
      normalized.contains('fong') ||
      normalized.contains('veget') ||
      normalized.contains('plant');
}

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  final raw = '$value'.trim();
  return values.firstWhere(
    (item) => item.name == raw,
    orElse: () => fallback,
  );
}

String? _nullableText(Object? value) {
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}

String? _canonicalEnvelopeId(String? value) {
  final raw = _nullableText(value);
  if (raw == null) return null;
  final normalized = normalizePtipoteAssetKey(raw);
  if (normalized == 'scientifique' || normalized == 'scientific') {
    return 'analyst';
  }
  return normalized;
}

DateTime? _readDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
