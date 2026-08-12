import 'dart:math' as math;

import 'ptipote_figurine.dart';
import 'ptipote_v2.dart';

enum CoBreedingSelectionMode {
  initialFreeTypeChoice,
  randomFreeOffer,
  paidTypeChoice,
  paidExactPtipote,
  devSelection,
}

enum CoBreedingSessionStatus {
  active,
  departurePending,
  departurePresented,
  rewardsPending,
  completed,
  archived,
  legacy,
}

enum CoBreedingDepartureReason { levelCapReached, timeExpired }

/// Immutable reward summary calculated once from the final P'TIPOTE level.
/// The state layer owns the atomic persistence; this service owns the common
/// rules so UI, completion and future history screens cannot diverge.
class CoBreedingCompletionRewards {
  const CoBreedingCompletionRewards({
    required this.ptipoteXp,
    required this.breederXp,
    required this.kernelTrust,
  });

  final int ptipoteXp;
  final int breederXp;
  final int kernelTrust;
}

/// Central policy for the terminal Co-élevage loop. It deliberately grants
/// exactly three reward categories and never depends on generation,
/// Symbiose, speed, or any quality grade.
class CoBreedingCompletionService {
  const CoBreedingCompletionService._();

  static bool canFinalize(
    CoBreedingSession session,
    PtipoteV2Profile profile,
  ) =>
      session.departurePending &&
      profile.ownershipMode == PtipoteOwnershipMode.coBred &&
      session.status != CoBreedingSessionStatus.completed &&
      session.status != CoBreedingSessionStatus.archived;

  static CoBreedingCompletionRewards rewardsFor({
    required PtipoteV2Config config,
    required int finalLevel,
  }) =>
      CoBreedingCompletionRewards(
        ptipoteXp: config.coBreedingXpRewardBase +
            config.coBreedingXpRewardPerFinalLevel * finalLevel,
        breederXp: config.coBreedingBreederXpRewardBase +
            config.coBreedingBreederXpRewardPerFinalLevel * finalLevel,
        kernelTrust: config.coBreedingKernelTrustRewardBase +
            config.coBreedingKernelTrustRewardPerFinalLevel * finalLevel,
      );
}

class CoBreedingTemplate {
  const CoBreedingTemplate({
    required this.templateId,
    required this.systemName,
    required this.typeId,
    required this.natureId,
    required this.generation,
    this.coreId,
    this.compatibleEnvelopeIds = const <String>[],
    this.publicEnabled = true,
    this.devEnabled = true,
    this.drawWeight = 1,
    this.minBreederLevel = 1,
  });

  final String templateId;
  final String systemName;
  final PtipoteTypeId typeId;
  final String natureId;
  final PtipoteGeneration generation;
  final String? coreId;
  final List<String> compatibleEnvelopeIds;
  final bool publicEnabled;
  final bool devEnabled;
  final int drawWeight;
  final int minBreederLevel;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'templateId': templateId,
        'systemName': systemName,
        'typeId': typeId.name,
        'natureId': natureId,
        'generation': generation.name,
        'coreId': coreId,
        'compatibleEnvelopeIds': compatibleEnvelopeIds,
        'publicEnabled': publicEnabled,
        'devEnabled': devEnabled,
        'drawWeight': drawWeight,
        'minBreederLevel': minBreederLevel,
      };
}

/// The V1 pools are intentionally small and transparent. Their toggles and
/// weights are content data, not rarity tiers. Protocoles remain DEV-only.
const List<CoBreedingTemplate> defaultCoBreedingVestiges = <CoBreedingTemplate>[
  CoBreedingTemplate(
    templateId: 'vestige-liane',
    systemName: 'Liane',
    typeId: PtipoteTypeId.vegetal,
    natureId: 'liane',
    generation: PtipoteGeneration.vestige,
  ),
  CoBreedingTemplate(
    templateId: 'vestige-cristal',
    systemName: 'Cristal',
    typeId: PtipoteTypeId.mineral,
    natureId: 'cristal',
    generation: PtipoteGeneration.vestige,
  ),
  CoBreedingTemplate(
    templateId: 'vestige-mycelle',
    systemName: 'Mycelle',
    typeId: PtipoteTypeId.mycelial,
    natureId: 'mycelle',
    generation: PtipoteGeneration.vestige,
  ),
];

const List<CoBreedingTemplate> defaultCoBreedingProtocols =
    <CoBreedingTemplate>[
  CoBreedingTemplate(
    templateId: 'protocol-liane',
    systemName: 'Noyau Liane',
    typeId: PtipoteTypeId.vegetal,
    natureId: 'liane',
    generation: PtipoteGeneration.protocol,
    coreId: 'core-liane',
    compatibleEnvelopeIds: <String>[
      'defense',
      'exploration',
      'production',
      'analyst',
    ],
    publicEnabled: false,
  ),
  CoBreedingTemplate(
    templateId: 'protocol-cristal',
    systemName: 'Noyau Cristal',
    typeId: PtipoteTypeId.mineral,
    natureId: 'cristal',
    generation: PtipoteGeneration.protocol,
    coreId: 'core-cristal',
    compatibleEnvelopeIds: <String>['defense', 'exploration'],
    publicEnabled: false,
  ),
  CoBreedingTemplate(
    templateId: 'protocol-mycelle',
    systemName: 'Noyau Mycelle',
    typeId: PtipoteTypeId.mycelial,
    natureId: 'mycelle',
    generation: PtipoteGeneration.protocol,
    coreId: 'core-mycelle',
    compatibleEnvelopeIds: <String>['production', 'analyst'],
    publicEnabled: false,
  ),
];

/// Separate from the P'TIPOTE pool so a DEV envelope can be tested without
/// leaking into public Co-élevage offers.
class CoBreedingEnvelopeTemplate {
  const CoBreedingEnvelopeTemplate({
    required this.envelopeId,
    required this.displayName,
    required this.category,
    required this.compatibleEnvelopeIds,
    this.publicEnabled = true,
    this.devEnabled = true,
    this.drawWeight = 1,
    this.minBreederLevel = 3,
  });

  final String envelopeId;
  final String displayName;
  final PtipoteEnvelopeCategory category;
  final List<String> compatibleEnvelopeIds;
  final bool publicEnabled;
  final bool devEnabled;
  final int drawWeight;
  final int minBreederLevel;
}

const List<CoBreedingEnvelopeTemplate> defaultCoBreedingEnvelopeTemplates =
    <CoBreedingEnvelopeTemplate>[
  CoBreedingEnvelopeTemplate(
    envelopeId: 'defense',
    displayName: 'Défense',
    category: PtipoteEnvelopeCategory.defense,
    compatibleEnvelopeIds: <String>['defense'],
  ),
  CoBreedingEnvelopeTemplate(
    envelopeId: 'exploration',
    displayName: 'Exploration',
    category: PtipoteEnvelopeCategory.exploration,
    compatibleEnvelopeIds: <String>['exploration'],
  ),
  CoBreedingEnvelopeTemplate(
    envelopeId: 'production',
    displayName: 'Production',
    category: PtipoteEnvelopeCategory.production,
    compatibleEnvelopeIds: <String>['production'],
  ),
  CoBreedingEnvelopeTemplate(
    envelopeId: 'analyst',
    displayName: 'Analyste',
    category: PtipoteEnvelopeCategory.analyst,
    compatibleEnvelopeIds: <String>['analyst'],
  ),
];

class CoBreedingEnvelopeOffer {
  const CoBreedingEnvelopeOffer({
    required this.offerId,
    required this.ptipoteId,
    required this.envelopeId,
    required this.generatedAt,
    required this.expiresAt,
    required this.randomSeed,
    this.consumed = false,
  });

  final String offerId;
  final String ptipoteId;
  final String envelopeId;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final int randomSeed;
  final bool consumed;

  CoBreedingEnvelopeOffer copyWith({bool? consumed}) => CoBreedingEnvelopeOffer(
        offerId: offerId,
        ptipoteId: ptipoteId,
        envelopeId: envelopeId,
        generatedAt: generatedAt,
        expiresAt: expiresAt,
        randomSeed: randomSeed,
        consumed: consumed ?? this.consumed,
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'offerId': offerId,
        'ptipoteId': ptipoteId,
        'envelopeId': envelopeId,
        'generatedAt': generatedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'randomSeed': randomSeed,
        'consumed': consumed,
      };

  factory CoBreedingEnvelopeOffer.fromFirebase(Map<dynamic, dynamic> value) =>
      CoBreedingEnvelopeOffer(
        offerId: '${value['offerId'] ?? ''}',
        ptipoteId: '${value['ptipoteId'] ?? ''}',
        envelopeId: '${value['envelopeId'] ?? ''}',
        generatedAt: DateTime.tryParse('${value['generatedAt']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        expiresAt: DateTime.tryParse('${value['expiresAt']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        randomSeed: (value['randomSeed'] as num?)?.toInt() ?? 0,
        consumed: value['consumed'] == true,
      );
}

class CoBreedingOffer {
  const CoBreedingOffer({
    required this.offerId,
    required this.templateId,
    required this.typeId,
    required this.generation,
    required this.generatedAt,
    required this.expiresAt,
    required this.randomSeed,
    this.envelopeId,
    this.consumed = false,
  });

  final String offerId;
  final String templateId;
  final PtipoteTypeId typeId;
  final PtipoteGeneration generation;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final int randomSeed;
  final String? envelopeId;
  final bool consumed;

  CoBreedingOffer copyWith({bool? consumed}) => CoBreedingOffer(
        offerId: offerId,
        templateId: templateId,
        typeId: typeId,
        generation: generation,
        generatedAt: generatedAt,
        expiresAt: expiresAt,
        randomSeed: randomSeed,
        envelopeId: envelopeId,
        consumed: consumed ?? this.consumed,
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'offerId': offerId,
        'templateId': templateId,
        'typeId': typeId.name,
        'generation': generation.name,
        'generatedAt': generatedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'randomSeed': randomSeed,
        'envelopeId': envelopeId,
        'consumed': consumed,
      };

  factory CoBreedingOffer.fromFirebase(Map<dynamic, dynamic> value) =>
      CoBreedingOffer(
        offerId: '${value['offerId'] ?? ''}',
        templateId: '${value['templateId'] ?? ''}',
        typeId: PtipoteTypeId.values.firstWhere(
          (type) => type.name == value['typeId'],
          orElse: () => PtipoteTypeId.vegetal,
        ),
        generation: PtipoteGeneration.values.firstWhere(
          (item) => item.name == value['generation'],
          orElse: () => PtipoteGeneration.vestige,
        ),
        generatedAt: DateTime.tryParse('${value['generatedAt']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        expiresAt: DateTime.tryParse('${value['expiresAt']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        randomSeed: (value['randomSeed'] as num?)?.toInt() ?? 0,
        envelopeId: value['envelopeId'] as String?,
        consumed: value['consumed'] == true,
      );
}

class CoBreedingSession {
  const CoBreedingSession({
    required this.sessionId,
    required this.ptipoteId,
    required this.selectionMode,
    required this.typeId,
    required this.ptipoteTemplateId,
    required this.startedAt,
    required this.expiresAt,
    required this.initialDurationSeconds,
    required this.remainingSeconds,
    required this.lastPlayerActiveAt,
    this.sourceOfferId,
    this.levelSevenReachedAt,
    this.departurePending = false,
    this.departureReason,
    this.status = CoBreedingSessionStatus.active,
    this.finalWindowProtectionConsumed = false,
    this.departurePendingAt,
    this.rewardsGrantedAt,
    this.completionTransactionId,
  });

  final String sessionId;
  final String ptipoteId;
  final String? sourceOfferId;
  final CoBreedingSelectionMode selectionMode;
  final PtipoteTypeId typeId;
  final String ptipoteTemplateId;
  final DateTime startedAt;
  final DateTime expiresAt;
  final int initialDurationSeconds;
  final int remainingSeconds;
  final DateTime lastPlayerActiveAt;
  final DateTime? levelSevenReachedAt;
  final bool departurePending;
  final CoBreedingDepartureReason? departureReason;
  final CoBreedingSessionStatus status;
  final bool finalWindowProtectionConsumed;
  final DateTime? departurePendingAt;
  final DateTime? rewardsGrantedAt;
  final String? completionTransactionId;

  CoBreedingSession copyWith({
    int? remainingSeconds,
    DateTime? lastPlayerActiveAt,
    DateTime? levelSevenReachedAt,
    bool? departurePending,
    CoBreedingDepartureReason? departureReason,
    CoBreedingSessionStatus? status,
    bool? finalWindowProtectionConsumed,
    DateTime? departurePendingAt,
    DateTime? rewardsGrantedAt,
    String? completionTransactionId,
  }) =>
      CoBreedingSession(
        sessionId: sessionId,
        ptipoteId: ptipoteId,
        sourceOfferId: sourceOfferId,
        selectionMode: selectionMode,
        typeId: typeId,
        ptipoteTemplateId: ptipoteTemplateId,
        startedAt: startedAt,
        expiresAt: expiresAt,
        initialDurationSeconds: initialDurationSeconds,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        lastPlayerActiveAt: lastPlayerActiveAt ?? this.lastPlayerActiveAt,
        levelSevenReachedAt: levelSevenReachedAt ?? this.levelSevenReachedAt,
        departurePending: departurePending ?? this.departurePending,
        departureReason: departureReason ?? this.departureReason,
        status: status ?? this.status,
        finalWindowProtectionConsumed:
            finalWindowProtectionConsumed ?? this.finalWindowProtectionConsumed,
        departurePendingAt: departurePendingAt ?? this.departurePendingAt,
        rewardsGrantedAt: rewardsGrantedAt ?? this.rewardsGrantedAt,
        completionTransactionId:
            completionTransactionId ?? this.completionTransactionId,
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'sessionId': sessionId,
        'ptipoteId': ptipoteId,
        'sourceOfferId': sourceOfferId,
        'selectionMode': selectionMode.name,
        'typeId': typeId.name,
        'ptipoteTemplateId': ptipoteTemplateId,
        'startedAt': startedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'initialDurationSeconds': initialDurationSeconds,
        'remainingSeconds': remainingSeconds,
        'lastPlayerActiveAt': lastPlayerActiveAt.toIso8601String(),
        'levelSevenReachedAt': levelSevenReachedAt?.toIso8601String(),
        'departurePending': departurePending,
        'departureReason': departureReason?.name,
        'status': status.name,
        'finalWindowProtectionConsumed': finalWindowProtectionConsumed,
        'departurePendingAt': departurePendingAt?.toIso8601String(),
        'rewardsGrantedAt': rewardsGrantedAt?.toIso8601String(),
        'completionTransactionId': completionTransactionId,
      };

  factory CoBreedingSession.fromFirebase(Map<dynamic, dynamic> value) {
    T byName<T extends Enum>(List<T> values, dynamic raw, T fallback) =>
        values.firstWhere((item) => item.name == raw, orElse: () => fallback);
    final startedAt =
        DateTime.tryParse('${value['startedAt']}') ?? DateTime.now();
    return CoBreedingSession(
      sessionId: '${value['sessionId'] ?? ''}',
      ptipoteId: '${value['ptipoteId'] ?? ''}',
      sourceOfferId: value['sourceOfferId'] as String?,
      selectionMode: byName(
        CoBreedingSelectionMode.values,
        value['selectionMode'],
        CoBreedingSelectionMode.randomFreeOffer,
      ),
      typeId:
          byName(PtipoteTypeId.values, value['typeId'], PtipoteTypeId.vegetal),
      ptipoteTemplateId: '${value['ptipoteTemplateId'] ?? ''}',
      startedAt: startedAt,
      expiresAt: DateTime.tryParse('${value['expiresAt']}') ?? startedAt,
      initialDurationSeconds:
          (value['initialDurationSeconds'] as num?)?.toInt() ?? 0,
      remainingSeconds: (value['remainingSeconds'] as num?)?.toInt() ?? 0,
      lastPlayerActiveAt:
          DateTime.tryParse('${value['lastPlayerActiveAt']}') ?? startedAt,
      levelSevenReachedAt: DateTime.tryParse('${value['levelSevenReachedAt']}'),
      departurePending: value['departurePending'] == true,
      departureReason: value['departureReason'] == null
          ? null
          : byName(
              CoBreedingDepartureReason.values,
              value['departureReason'],
              CoBreedingDepartureReason.timeExpired,
            ),
      status: byName(
        CoBreedingSessionStatus.values,
        value['status'],
        CoBreedingSessionStatus.active,
      ),
      finalWindowProtectionConsumed:
          value['finalWindowProtectionConsumed'] == true,
      departurePendingAt: DateTime.tryParse('${value['departurePendingAt']}'),
      rewardsGrantedAt: DateTime.tryParse('${value['rewardsGrantedAt']}'),
      completionTransactionId: value['completionTransactionId'] as String?,
    );
  }
}

/// A personal, non-tradeable reward. It is kept outside resource stacks so
/// each source session can be consumed exactly once and keeps its Type rule.
class CoBreedingXpReward {
  const CoBreedingXpReward({
    required this.itemId,
    required this.compatibleTypeId,
    required this.xpAmount,
    required this.sourceSessionId,
    required this.sourcePtipoteId,
    required this.createdAt,
    this.consumedAt,
    this.consumedByPtipoteId,
  });

  final String itemId;
  final PtipoteTypeId compatibleTypeId;
  final int xpAmount;
  final String sourceSessionId;
  final String sourcePtipoteId;
  final DateTime createdAt;
  final DateTime? consumedAt;
  final String? consumedByPtipoteId;
  bool get isConsumed => consumedAt != null;

  CoBreedingXpReward consume(String targetId, DateTime at) =>
      CoBreedingXpReward(
        itemId: itemId,
        compatibleTypeId: compatibleTypeId,
        xpAmount: xpAmount,
        sourceSessionId: sourceSessionId,
        sourcePtipoteId: sourcePtipoteId,
        createdAt: createdAt,
        consumedAt: at,
        consumedByPtipoteId: targetId,
      );

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'itemId': itemId,
        'rewardType': 'coBreedingXp',
        'compatibleTypeId': compatibleTypeId.name,
        'xpAmount': xpAmount,
        'sourceSessionId': sourceSessionId,
        'sourcePtipoteId': sourcePtipoteId,
        'createdAt': createdAt.toIso8601String(),
        'consumedAt': consumedAt?.toIso8601String(),
        'consumedByPtipoteId': consumedByPtipoteId,
      };

  factory CoBreedingXpReward.fromFirebase(Map<dynamic, dynamic> data) =>
      CoBreedingXpReward(
        itemId: '${data['itemId'] ?? ''}',
        compatibleTypeId: PtipoteTypeId.values.firstWhere(
          (type) => type.name == data['compatibleTypeId'],
          orElse: () => PtipoteTypeId.vegetal,
        ),
        xpAmount: (data['xpAmount'] as num?)?.round() ?? 0,
        sourceSessionId: '${data['sourceSessionId'] ?? ''}',
        sourcePtipoteId: '${data['sourcePtipoteId'] ?? ''}',
        createdAt: DateTime.tryParse('${data['createdAt']}') ?? DateTime.now(),
        consumedAt: DateTime.tryParse('${data['consumedAt']}'),
        consumedByPtipoteId: data['consumedByPtipoteId'] as String?,
      );
}

class CoBreedingArchive {
  const CoBreedingArchive({
    required this.sessionId,
    required this.ptipoteId,
    required this.displayName,
    required this.systemName,
    required this.typeId,
    required this.natureId,
    required this.generation,
    required this.finalLevel,
    required this.finalXp,
    required this.arrivedAt,
    required this.departedAt,
    required this.departureReason,
    this.coreId,
    this.envelopeId,
    this.symbiosisLevel,
    this.symbiosisProgressPercent,
    this.protocolEfficiency,
  });

  final String sessionId;
  final String ptipoteId;
  final String displayName;
  final String systemName;
  final PtipoteTypeId typeId;
  final String natureId;
  final PtipoteGeneration generation;
  final String? coreId;
  final String? envelopeId;
  final int finalLevel;
  final int finalXp;
  final int? symbiosisLevel;
  final double? symbiosisProgressPercent;
  final double? protocolEfficiency;
  final DateTime arrivedAt;
  final DateTime departedAt;
  final CoBreedingDepartureReason? departureReason;

  Map<String, dynamic> toFirebase() => <String, dynamic>{
        'sessionId': sessionId,
        'ptipoteId': ptipoteId,
        'displayName': displayName,
        'systemName': systemName,
        'typeId': typeId.name,
        'natureId': natureId,
        'generation': generation.name,
        'coreId': coreId,
        'envelopeId': envelopeId,
        'finalLevel': finalLevel,
        'finalXp': finalXp,
        'symbiosisLevel': symbiosisLevel,
        'symbiosisProgressPercent': symbiosisProgressPercent,
        'protocolEfficiency': protocolEfficiency,
        'arrivedAt': arrivedAt.toIso8601String(),
        'departedAt': departedAt.toIso8601String(),
        'departureReason': departureReason?.name,
      };

  factory CoBreedingArchive.fromFirebase(Map<dynamic, dynamic> data) =>
      CoBreedingArchive(
        sessionId: '${data['sessionId'] ?? ''}',
        ptipoteId: '${data['ptipoteId'] ?? ''}',
        displayName: '${data['displayName'] ?? ''}',
        systemName: '${data['systemName'] ?? ''}',
        typeId: PtipoteTypeId.values.firstWhere(
          (type) => type.name == data['typeId'],
          orElse: () => PtipoteTypeId.vegetal,
        ),
        natureId: '${data['natureId'] ?? 'unknown'}',
        generation: PtipoteGeneration.values.firstWhere(
          (item) => item.name == data['generation'],
          orElse: () => PtipoteGeneration.vestige,
        ),
        coreId: data['coreId'] as String?,
        envelopeId: data['envelopeId'] as String?,
        finalLevel: (data['finalLevel'] as num?)?.round() ?? 1,
        finalXp: (data['finalXp'] as num?)?.round() ?? 0,
        symbiosisLevel: (data['symbiosisLevel'] as num?)?.round(),
        symbiosisProgressPercent:
            (data['symbiosisProgressPercent'] as num?)?.toDouble(),
        protocolEfficiency: (data['protocolEfficiency'] as num?)?.toDouble(),
        arrivedAt: DateTime.tryParse('${data['arrivedAt']}') ?? DateTime.now(),
        departedAt:
            DateTime.tryParse('${data['departedAt']}') ?? DateTime.now(),
        departureReason: data['departureReason'] == null
            ? null
            : CoBreedingDepartureReason.values.firstWhere(
                (item) => item.name == data['departureReason'],
                orElse: () => CoBreedingDepartureReason.timeExpired,
              ),
      );
}

class CoBreedingCompletionResult {
  const CoBreedingCompletionResult({
    required this.sessionId,
    required this.displayName,
    required this.typeId,
    required this.ptipoteXpAmount,
    required this.breederXpAmount,
    required this.kernelTrustAmount,
    required this.alreadyCompleted,
  });

  final String sessionId;
  final String displayName;
  final PtipoteTypeId typeId;
  final int ptipoteXpAmount;
  final int breederXpAmount;
  final int kernelTrustAmount;
  final bool alreadyCompleted;
}

class CoBreedingConfig {
  const CoBreedingConfig({
    this.enabled = true,
    this.kernelUnlockLevel = 2,
    this.maxDurationHours = 168,
    this.finalProtectionWindowHours = 48,
    this.offlineGuaranteedRemainingHours = 24,
    this.capacityPerBreederLevel = 1,
    this.levelEarlyDeparture = 7,
    this.offerRotationHours = 24,
    this.chooseTypeCost = 5,
    this.chooseExactPtipoteCost = 8,
    this.chooseExactEnvelopeCost = 6,
    this.initialFreeCoBreedingEnabled = true,
    this.devPoolMode = CoBreedingPoolMode.publicOnly,
  });

  final bool enabled;
  final int kernelUnlockLevel;
  final int maxDurationHours;
  final int finalProtectionWindowHours;
  final int offlineGuaranteedRemainingHours;
  final int capacityPerBreederLevel;
  final int levelEarlyDeparture;
  final int offerRotationHours;
  final int chooseTypeCost;
  final int chooseExactPtipoteCost;
  final int chooseExactEnvelopeCost;
  final bool initialFreeCoBreedingEnabled;
  final CoBreedingPoolMode devPoolMode;
}

enum CoBreedingPoolMode { publicOnly, devOnly, publicAndDev }

const CoBreedingConfig defaultCoBreedingConfig = CoBreedingConfig();

class CoBreedingTimeService {
  static CoBreedingSession resolve(
    CoBreedingSession session, {
    required CoBreedingConfig config,
    required DateTime now,
  }) {
    if (session.departurePending ||
        session.status != CoBreedingSessionStatus.active) {
      return session;
    }
    final elapsed =
        math.max(0, now.difference(session.lastPlayerActiveAt).inSeconds);
    var remaining = math.max(0, session.remainingSeconds - elapsed);
    var protected = session.finalWindowProtectionConsumed;
    final guaranteed = config.offlineGuaranteedRemainingHours * 3600;
    if (!protected && remaining < guaranteed) {
      remaining = guaranteed;
      protected = true;
    }
    if (remaining <= 0) {
      return session.copyWith(
        remainingSeconds: 0,
        lastPlayerActiveAt: now,
        departurePending: true,
        departureReason: CoBreedingDepartureReason.timeExpired,
        status: CoBreedingSessionStatus.departurePending,
        departurePendingAt: now,
        finalWindowProtectionConsumed: protected,
      );
    }
    return session.copyWith(
      remainingSeconds: remaining,
      lastPlayerActiveAt: now,
      finalWindowProtectionConsumed: protected,
    );
  }

  static CoBreedingSession markLevelCap(
    CoBreedingSession session, {
    required DateTime now,
  }) =>
      session.departurePending
          ? session
          : session.copyWith(
              departurePending: true,
              departureReason: CoBreedingDepartureReason.levelCapReached,
              levelSevenReachedAt: now,
              status: CoBreedingSessionStatus.departurePending,
              departurePendingAt: now,
            );
}

int getCoBreedingCapacity(int breederLevel, CoBreedingConfig config) =>
    math.max(1, breederLevel) * math.max(1, config.capacityPerBreederLevel);

PtipoteFigurine coBredFigurineFromProfile(PtipoteV2Profile profile) =>
    PtipoteFigurine(
      id: profile.ptipoteId,
      tagUid: 'co-breeding-${profile.ptipoteId}',
      nickname: profile.displayName.isEmpty
          ? profile.systemName
          : profile.displayName,
      publicKey: profile.ptipoteId,
      rawSource: 'coBreeding',
      sortOrder: 999,
      transferStatus: 'coBreeding',
      transferFromName: '',
      transferLockedUntil: null,
      renameLockedUntil: null,
      fields: <String, String>{
        's': profile.displayName.isEmpty
            ? profile.systemName
            : profile.displayName,
        'e': profile.natureId,
        't': switch (profile.typeId) {
          PtipoteTypeId.vegetal => 'Végétal',
          PtipoteTypeId.mineral => 'Minéral',
          PtipoteTypeId.mycelial => 'Mycélien',
        },
        'l': '1',
        'x': '0',
      },
      createdAt: profile.createdAt ?? DateTime.now(),
      updatedAt: profile.updatedAt ?? DateTime.now(),
    );
