/// Deterministic V2 Lisière domain engine.
///
/// It intentionally owns neither widgets nor Firebase. Persisted world state
/// is supplied by the V2 foundation service; this file makes identical graph
/// generation possible on an open or closed application.
library;

enum LisiereTravelDifficulty { easy, medium, hard }

enum LisiereResourceKind { organic, mineral, waste }

extension LisiereResourceKindLabel on LisiereResourceKind {
  String get label => switch (this) {
        LisiereResourceKind.organic => 'Organique',
        LisiereResourceKind.mineral => 'Minéral',
        LisiereResourceKind.waste => 'Déchets',
      };

  String get icon => switch (this) {
        LisiereResourceKind.organic => '🌿',
        LisiereResourceKind.mineral => '🪨',
        LisiereResourceKind.waste => '♻️',
      };
}

enum LisiereHarvestRegime { doux, normal, intensif }

enum LisierePtipoteJob { recolteur, patrouilleur }

/// The level is deliberately scoped to the Lisière jobs. It does not reuse
/// the legacy Protecteur métier: an Enveloppe Protecteur remains an equipment
/// choice while Patrouilleur is an exploration role.
enum LisiereJobLevel { n0, n1 }

class LisiereJobProgress {
  const LisiereJobProgress({
    required this.ptipoteId,
    required this.job,
    this.harvestLearningActions = 0,
    this.patrolExperience = 0,
  });

  static const int harvestActionsForN1 = 100;
  static const int patrolExperienceForN1 = 50;
  static const int patrolEncounterExperience = 5;
  static const int patrolQteExperience = 15;

  final String ptipoteId;
  final LisierePtipoteJob job;
  final int harvestLearningActions;
  final int patrolExperience;

  LisiereJobLevel levelFor([LisiereV2Config? config]) {
    final active = config ?? lisiereV2Config;
    return switch (job) {
      LisierePtipoteJob.recolteur =>
        harvestLearningActions >= active.recolteurActionsForN1
            ? LisiereJobLevel.n1
            : LisiereJobLevel.n0,
      LisierePtipoteJob.patrouilleur =>
        patrolExperience >= active.patrouilleurExperienceForN1
            ? LisiereJobLevel.n1
            : LisiereJobLevel.n0,
    };
  }

  LisiereJobLevel get level => levelFor();

  int get currentProgress => switch (job) {
        LisierePtipoteJob.recolteur => harvestLearningActions,
        LisierePtipoteJob.patrouilleur => patrolExperience,
      };

  int requiredProgressFor([LisiereV2Config? config]) => switch (job) {
        LisierePtipoteJob.recolteur =>
          (config ?? lisiereV2Config).recolteurActionsForN1,
        LisierePtipoteJob.patrouilleur =>
          (config ?? lisiereV2Config).patrouilleurExperienceForN1,
      };

  int get requiredProgress => requiredProgressFor();

  LisiereJobProgress recordHarvestAction() {
    if (job != LisierePtipoteJob.recolteur) return this;
    return copyWith(harvestLearningActions: harvestLearningActions + 1);
  }

  LisiereJobProgress recordPatrolEncounter([LisiereV2Config? config]) {
    if (job != LisierePtipoteJob.patrouilleur) return this;
    return copyWith(
      patrolExperience: patrolExperience +
          (config ?? lisiereV2Config).patrouilleurEncounterExperience,
    );
  }

  LisiereJobProgress recordPatrolQte([LisiereV2Config? config]) {
    if (job != LisierePtipoteJob.patrouilleur) return this;
    return copyWith(
      patrolExperience: patrolExperience +
          (config ?? lisiereV2Config).patrouilleurQteExperience,
    );
  }

  LisiereJobProgress copyWith({
    int? harvestLearningActions,
    int? patrolExperience,
  }) =>
      LisiereJobProgress(
        ptipoteId: ptipoteId,
        job: job,
        harvestLearningActions:
            harvestLearningActions ?? this.harvestLearningActions,
        patrolExperience: patrolExperience ?? this.patrolExperience,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'ptipoteId': ptipoteId,
        'job': job.name,
        'harvestLearningActions': harvestLearningActions,
        'patrolExperience': patrolExperience,
      };

  factory LisiereJobProgress.fromMap(Map<String, dynamic> map) =>
      LisiereJobProgress(
        ptipoteId: map['ptipoteId'] as String,
        job: LisierePtipoteJob.values.byName(map['job'] as String),
        harvestLearningActions:
            (map['harvestLearningActions'] as num?)?.toInt() ?? 0,
        patrolExperience: (map['patrolExperience'] as num?)?.toInt() ?? 0,
      );
}

class LisiereV2Config {
  const LisiereV2Config({
    this.minimumParcels = 6,
    this.maximumParcels = 9,
    this.easyTravelSeconds = 60,
    this.mediumTravelSeconds = 120,
    this.hardTravelSeconds = 180,
    this.baseTeamCapacity = 2,
    this.teamManagementBonus = 1,
    this.logisticsOptimizationMaximum = 2,
    this.returnSafetyReserve = 5,
    this.recolteurActionsForN1 = 100,
    this.patrouilleurExperienceForN1 = 50,
    this.patrouilleurEncounterExperience = 5,
    this.patrouilleurQteExperience = 15,
  })  : assert(minimumParcels >= 1),
        assert(maximumParcels >= minimumParcels);

  final int minimumParcels;
  final int maximumParcels;
  final int easyTravelSeconds;
  final int mediumTravelSeconds;
  final int hardTravelSeconds;
  final int baseTeamCapacity;
  final int teamManagementBonus;
  final int logisticsOptimizationMaximum;
  final int returnSafetyReserve;
  final int recolteurActionsForN1;
  final int patrouilleurExperienceForN1;
  final int patrouilleurEncounterExperience;
  final int patrouilleurQteExperience;

  int travelSeconds(LisiereTravelDifficulty difficulty) => switch (difficulty) {
        LisiereTravelDifficulty.easy => easyTravelSeconds,
        LisiereTravelDifficulty.medium => mediumTravelSeconds,
        LisiereTravelDifficulty.hard => hardTravelSeconds,
      };

  factory LisiereV2Config.fromMap(
    Map<String, dynamic>? map, {
    LisiereV2Config base = defaultLisiereV2Config,
  }) {
    int value(String key, int fallback) {
      final raw = map?[key];
      return raw is num && raw.isFinite ? raw.round() : fallback;
    }

    return LisiereV2Config(
      minimumParcels: value('minimumParcels', base.minimumParcels),
      maximumParcels: value('maximumParcels', base.maximumParcels),
      easyTravelSeconds: value('easyTravelSeconds', base.easyTravelSeconds),
      mediumTravelSeconds:
          value('mediumTravelSeconds', base.mediumTravelSeconds),
      hardTravelSeconds: value('hardTravelSeconds', base.hardTravelSeconds),
      baseTeamCapacity: value('baseTeamCapacity', base.baseTeamCapacity),
      teamManagementBonus:
          value('teamManagementBonus', base.teamManagementBonus),
      logisticsOptimizationMaximum: value(
        'logisticsOptimizationMaximum',
        base.logisticsOptimizationMaximum,
      ),
      returnSafetyReserve:
          value('returnSafetyReserve', base.returnSafetyReserve),
      recolteurActionsForN1: value(
        'recolteurActionsForN1',
        base.recolteurActionsForN1,
      ),
      patrouilleurExperienceForN1: value(
        'patrouilleurExperienceForN1',
        base.patrouilleurExperienceForN1,
      ),
      patrouilleurEncounterExperience: value(
        'patrouilleurEncounterExperience',
        base.patrouilleurEncounterExperience,
      ),
      patrouilleurQteExperience: value(
        'patrouilleurQteExperience',
        base.patrouilleurQteExperience,
      ),
    );
  }
}

const LisiereV2Config defaultLisiereV2Config = LisiereV2Config();

LisiereV2Config lisiereV2Config = defaultLisiereV2Config;

class TravelEdge {
  const TravelEdge({
    required this.id,
    required this.fromParcelId,
    required this.toParcelId,
    required this.difficulty,
  });

  final String id;
  final String fromParcelId;
  final String toParcelId;
  final LisiereTravelDifficulty difficulty;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'fromParcelId': fromParcelId,
        'toParcelId': toParcelId,
        'difficulty': difficulty.name,
      };

  factory TravelEdge.fromMap(Map<String, dynamic> map) => TravelEdge(
        id: map['id'] as String,
        fromParcelId: map['fromParcelId'] as String,
        toParcelId: map['toParcelId'] as String,
        difficulty: LisiereTravelDifficulty.values.byName(
          map['difficulty'] as String,
        ),
      );
}

class ParcelInstance {
  const ParcelInstance({
    required this.id,
    required this.biomeId,
    required this.ordinal,
    required this.seed,
    required this.connectedParcelIds,
    this.infrastructureIds = const <String>[],
    this.compatibleInfrastructureSlots = 0,
  });

  final String id;
  final String biomeId;
  final int ordinal;
  final int seed;
  final List<String> connectedParcelIds;
  final List<String> infrastructureIds;
  final int compatibleInfrastructureSlots;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'biomeId': biomeId,
        'ordinal': ordinal,
        'seed': seed,
        'connectedParcelIds': connectedParcelIds,
        'infrastructureIds': infrastructureIds,
        'compatibleInfrastructureSlots': compatibleInfrastructureSlots,
      };

  factory ParcelInstance.fromMap(Map<String, dynamic> map) => ParcelInstance(
        id: map['id'] as String,
        biomeId: map['biomeId'] as String,
        ordinal: (map['ordinal'] as num).toInt(),
        seed: (map['seed'] as num).toInt(),
        connectedParcelIds:
            List<String>.from(map['connectedParcelIds'] as List),
        infrastructureIds: List<String>.from(
            map['infrastructureIds'] as List? ?? const <String>[]),
        compatibleInfrastructureSlots:
            (map['compatibleInfrastructureSlots'] as num?)?.toInt() ?? 0,
      );
}

class BiomeParcelGraph {
  const BiomeParcelGraph({
    required this.biomeId,
    required this.seed,
    required this.parcels,
    required this.edges,
  });

  final String biomeId;
  final int seed;
  final List<ParcelInstance> parcels;
  final List<TravelEdge> edges;

  TravelEdge? edgeBetween(String first, String second) {
    for (final edge in edges) {
      if ((edge.fromParcelId == first && edge.toParcelId == second) ||
          (edge.fromParcelId == second && edge.toParcelId == first)) {
        return edge;
      }
    }
    return null;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'biomeId': biomeId,
        'seed': seed,
        'parcels': parcels.map((parcel) => parcel.toMap()).toList(),
        'edges': edges.map((edge) => edge.toMap()).toList(),
      };

  factory BiomeParcelGraph.fromMap(Map<String, dynamic> map) =>
      BiomeParcelGraph(
        biomeId: map['biomeId'] as String,
        seed: (map['seed'] as num).toInt(),
        parcels: (map['parcels'] as List)
            .map((value) =>
                ParcelInstance.fromMap(Map<String, dynamic>.from(value as Map)))
            .toList(),
        edges: (map['edges'] as List)
            .map((value) =>
                TravelEdge.fromMap(Map<String, dynamic>.from(value as Map)))
            .toList(),
      );
}

enum LisiereResourceNodeState { available, temporarilyDepleted, exhausted }

class LisiereHarvestActor {
  const LisiereHarvestActor({
    required this.id,
    required this.harvestPower,
    required this.actionFrequency,
    required this.yieldModifier,
    required this.maxVitality,
    required this.currentVitality,
  });

  final String id;

  /// Resistance damage per action, not a yield bonus.
  final double harvestPower;

  /// Actions per second, kept independent from power and yield.
  final double actionFrequency;

  /// Material recovery multiplier, applied only after a productive unit.
  final double yieldModifier;
  final int maxVitality;
  final int currentVitality;
}

class LisiereResourceNode {
  LisiereResourceNode.organic({
    required this.id,
    required this.parcelId,
    required this.maxResistance,
    required this.standardYield,
    required this.visualVariant,
    this.regenerationReference,
    this.isDestroyed = false,
  })  : kind = LisiereResourceKind.organic,
        resistance = maxResistance,
        remainingLayers = 1,
        yieldRemainder = 0;

  LisiereResourceNode.mineral({
    required this.id,
    required this.parcelId,
    required this.maxResistance,
    required this.standardYield,
    required this.remainingLayers,
    required this.visualVariant,
  })  : kind = LisiereResourceKind.mineral,
        resistance = maxResistance,
        regenerationReference = null,
        isDestroyed = false,
        yieldRemainder = 0;

  LisiereResourceNode.waste({
    required this.id,
    required this.parcelId,
    required this.maxResistance,
    required this.standardYield,
    required this.remainingLayers,
    required this.visualVariant,
  })  : kind = LisiereResourceKind.waste,
        resistance = maxResistance,
        regenerationReference = null,
        isDestroyed = false,
        yieldRemainder = 0;

  final String id;
  final String parcelId;
  final LisiereResourceKind kind;
  final double maxResistance;
  double resistance;
  final int standardYield;
  int remainingLayers;
  final String visualVariant;
  final DateTime? regenerationReference;
  double yieldRemainder;
  bool isDestroyed;

  LisiereResourceNodeState get state {
    if (isDestroyed) return LisiereResourceNodeState.exhausted;
    if (kind != LisiereResourceKind.organic && remainingLayers <= 0) {
      return LisiereResourceNodeState.exhausted;
    }
    if (resistance <= 0) return LisiereResourceNodeState.temporarilyDepleted;
    return LisiereResourceNodeState.available;
  }

  /// Resolves one real action. Organic nodes stop at their future Biomass hook;
  /// mineral nodes start their next persisted layer until no layer remains.
  HarvestResolution applyAction(LisiereHarvestActor actor) {
    if (state != LisiereResourceNodeState.available ||
        actor.harvestPower <= 0) {
      return HarvestResolution.empty(this);
    }
    final inflicted = actor.harvestPower.clamp(0, resistance);
    resistance = (resistance - inflicted).clamp(0, maxResistance);
    if (kind == LisiereResourceKind.organic ||
        kind == LisiereResourceKind.waste) {
      final rawYield = inflicted * actor.yieldModifier + yieldRemainder;
      final credited = rawYield.floor().clamp(0, 1 << 31).toInt();
      yieldRemainder = rawYield - credited;
      if (kind == LisiereResourceKind.waste && resistance <= 0) {
        remainingLayers = 0;
      }
      return HarvestResolution(
        nodeId: id,
        resource: kind,
        creditedAmount: credited,
        remainder: yieldRemainder,
        productiveUnitCompleted: credited > 0,
        nodeState: state,
      );
    }
    if (resistance > 0) return HarvestResolution.empty(this);
    final rawYield = standardYield * actor.yieldModifier + yieldRemainder;
    final credited = rawYield.floor().clamp(0, 1 << 31).toInt();
    yieldRemainder = rawYield - credited;
    if (kind != LisiereResourceKind.organic) {
      remainingLayers -= 1;
      if (remainingLayers > 0) resistance = maxResistance;
    }
    return HarvestResolution(
      nodeId: id,
      resource: kind,
      creditedAmount: credited,
      remainder: yieldRemainder,
      productiveUnitCompleted: true,
      nodeState: state,
    );
  }

  /// Called only by the future Biomass resolver; surface mineral never respawns.
  void restoreOrganicFromBiomass() {
    if (kind == LisiereResourceKind.organic) {
      isDestroyed = false;
      resistance = maxResistance;
    }
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'parcelId': parcelId,
        'kind': kind.name,
        'maxResistance': maxResistance,
        'resistance': resistance,
        'standardYield': standardYield,
        'remainingLayers': remainingLayers,
        'visualVariant': visualVariant,
        'regenerationReference': regenerationReference?.millisecondsSinceEpoch,
        'yieldRemainder': yieldRemainder,
        'isDestroyed': isDestroyed,
      };

  factory LisiereResourceNode.fromMap(Map<String, dynamic> map) {
    final kind = LisiereResourceKind.values.byName(map['kind'] as String);
    final node = kind == LisiereResourceKind.organic
        ? LisiereResourceNode.organic(
            id: map['id'] as String,
            parcelId: map['parcelId'] as String,
            maxResistance: (map['maxResistance'] as num).toDouble(),
            standardYield: (map['standardYield'] as num).toInt(),
            visualVariant: map['visualVariant'] as String,
            regenerationReference: map['regenerationReference'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (map['regenerationReference'] as num).toInt(),
                  )
                : null,
          )
        : kind == LisiereResourceKind.mineral
            ? LisiereResourceNode.mineral(
                id: map['id'] as String,
                parcelId: map['parcelId'] as String,
                maxResistance: (map['maxResistance'] as num).toDouble(),
                standardYield: (map['standardYield'] as num).toInt(),
                remainingLayers: (map['remainingLayers'] as num).toInt(),
                visualVariant: map['visualVariant'] as String,
              )
            : LisiereResourceNode.waste(
                id: map['id'] as String,
                parcelId: map['parcelId'] as String,
                maxResistance: (map['maxResistance'] as num).toDouble(),
                standardYield: (map['standardYield'] as num).toInt(),
                remainingLayers: (map['remainingLayers'] as num?)?.toInt() ?? 1,
                visualVariant: map['visualVariant'] as String,
              );
    node.resistance =
        (map['resistance'] as num?)?.toDouble() ?? node.maxResistance;
    node.yieldRemainder = (map['yieldRemainder'] as num?)?.toDouble() ?? 0;
    node.isDestroyed = map['isDestroyed'] == true;
    return node;
  }
}

class HarvestResolution {
  const HarvestResolution({
    required this.nodeId,
    required this.resource,
    required this.creditedAmount,
    required this.remainder,
    required this.productiveUnitCompleted,
    required this.nodeState,
  });

  factory HarvestResolution.empty(LisiereResourceNode node) =>
      HarvestResolution(
        nodeId: node.id,
        resource: node.kind,
        creditedAmount: 0,
        remainder: node.yieldRemainder,
        productiveUnitCompleted: false,
        nodeState: node.state,
      );

  final String nodeId;
  final LisiereResourceKind resource;
  final int creditedAmount;
  final double remainder;
  final bool productiveUnitCompleted;
  final LisiereResourceNodeState nodeState;
}

class LisiereFieldInventory {
  LisiereFieldInventory({
    required this.id,
    required this.capacity,
    this.maxStacks,
  })  : assert(capacity >= 0),
        assert(maxStacks == null || maxStacks >= 1);

  final String id;
  final int capacity;
  final int? maxStacks;
  final Map<LisiereResourceKind, int> amounts = <LisiereResourceKind, int>{};

  int get used => amounts.values.fold(0, (sum, amount) => sum + amount);
  int get remainingCapacity => capacity - used;

  bool canAccept(LisiereResourceKind resource) =>
      remainingCapacity > 0 &&
      (amounts.containsKey(resource) ||
          maxStacks == null ||
          amounts.length < maxStacks!);

  int add(LisiereResourceKind resource, int amount) {
    if (!canAccept(resource)) return 0;
    final accepted = amount.clamp(0, remainingCapacity).toInt();
    if (accepted > 0) {
      amounts.update(resource, (value) => value + accepted,
          ifAbsent: () => accepted);
    }
    return accepted;
  }

  int remove(LisiereResourceKind resource, int amount) {
    final available = amounts[resource] ?? 0;
    final removed = amount.clamp(0, available).toInt();
    final next = available - removed;
    if (next == 0) {
      amounts.remove(resource);
    } else {
      amounts[resource] = next;
    }
    return removed;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'capacity': capacity,
        'maxStacks': maxStacks,
        'amounts': <String, int>{
          for (final entry in amounts.entries) entry.key.name: entry.value,
        },
      };

  factory LisiereFieldInventory.fromMap(Map<String, dynamic> map) {
    final inventory = LisiereFieldInventory(
      id: map['id'] as String,
      capacity: (map['capacity'] as num?)?.toInt() ?? 0,
      maxStacks: (map['maxStacks'] as num?)?.toInt(),
    );
    final rawAmounts = map['amounts'];
    if (rawAmounts is Map) {
      for (final entry in rawAmounts.entries) {
        LisiereResourceKind? resource;
        for (final candidate in LisiereResourceKind.values) {
          if (candidate.name == entry.key) {
            resource = candidate;
            break;
          }
        }
        if (resource != null && entry.value is num) {
          inventory.add(resource, (entry.value as num).toInt());
        }
      }
    }
    return inventory;
  }
}

enum LisiereCarrierKind { ptibug, ptipote }

class LisiereCarrier {
  const LisiereCarrier({
    required this.id,
    required this.kind,
    required this.capacity,
  });

  final String id;
  final LisiereCarrierKind kind;
  final int capacity;
}

/// P'TIBUGs are considered before P'TIPOTES, then larger capacities are used
/// first. The caller keeps its own inventories: this only chooses a carrier
/// and never teleports a resource between locations.
LisiereCarrier? selectCarrier(List<LisiereCarrier> available) {
  if (available.isEmpty) return null;
  final ranked = List<LisiereCarrier>.from(available)
    ..sort((first, second) {
      final kindComparison = first.kind.index.compareTo(second.kind.index);
      return kindComparison != 0
          ? kindComparison
          : second.capacity.compareTo(first.capacity);
    });
  return ranked.first;
}

enum LisiereCargoRotationState {
  collecting,
  travelingToOutpost,
  depositing,
  returning,
  blocked,
  completed
}

class LisiereCargoRotation {
  LisiereCargoRotation({
    required this.id,
    required this.carrierId,
    required this.originInventoryId,
    required this.destinationInventoryId,
    required this.startedAt,
    this.teamId,
    this.travelDuration = Duration.zero,
    this.state = LisiereCargoRotationState.collecting,
  });

  final String id;
  final String carrierId;
  final String originInventoryId;
  final String destinationInventoryId;
  final DateTime startedAt;
  final String? teamId;
  final Duration travelDuration;
  LisiereCargoRotationState state;

  void advance() {
    state = switch (state) {
      LisiereCargoRotationState.collecting =>
        LisiereCargoRotationState.travelingToOutpost,
      LisiereCargoRotationState.travelingToOutpost =>
        LisiereCargoRotationState.depositing,
      LisiereCargoRotationState.depositing =>
        LisiereCargoRotationState.returning,
      LisiereCargoRotationState.returning =>
        LisiereCargoRotationState.completed,
      LisiereCargoRotationState.blocked ||
      LisiereCargoRotationState.completed =>
        state,
    };
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'carrierId': carrierId,
        'originInventoryId': originInventoryId,
        'destinationInventoryId': destinationInventoryId,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'teamId': teamId,
        'travelSeconds': travelDuration.inSeconds,
        'state': state.name,
      };

  factory LisiereCargoRotation.fromMap(Map<String, dynamic> map) =>
      LisiereCargoRotation(
        id: map['id'] as String,
        carrierId: map['carrierId'] as String,
        originInventoryId: map['originInventoryId'] as String,
        destinationInventoryId: map['destinationInventoryId'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['startedAt'] as num).toInt(),
        ),
        teamId: map['teamId'] as String?,
        travelDuration:
            Duration(seconds: (map['travelSeconds'] as num?)?.toInt() ?? 0),
        state: LisiereCargoRotationState.values.byName(
          map['state'] as String? ?? LisiereCargoRotationState.collecting.name,
        ),
      );
}

int teamCapacity({
  required bool hasTeamManagementStructure,
  required int logisticsOptimizationModules,
  LisiereV2Config? config,
}) {
  final active = config ?? lisiereV2Config;
  return active.baseTeamCapacity +
      (hasTeamManagementStructure ? active.teamManagementBonus : 0) +
      logisticsOptimizationModules
          .clamp(0, active.logisticsOptimizationMaximum)
          .toInt();
}

bool canSpendVitality({
  required int currentVitality,
  required int actionCost,
  required int returnCostFromDestination,
  int? safetyReserve,
  LisiereV2Config? config,
}) =>
    currentVitality >=
    actionCost +
        returnCostFromDestination +
        (safetyReserve ?? (config ?? lisiereV2Config).returnSafetyReserve);

enum LisiereMissionStatus {
  planned,
  traveling,
  working,
  depositing,
  returning,
  completed,
  blocked,
  cancelled,
}

enum LisiereMissionDuration { minutes30, hour1, hours2, hours4, hours8 }

extension LisiereMissionDurationX on LisiereMissionDuration {
  Duration get duration => switch (this) {
        LisiereMissionDuration.minutes30 => const Duration(minutes: 30),
        LisiereMissionDuration.hour1 => const Duration(hours: 1),
        LisiereMissionDuration.hours2 => const Duration(hours: 2),
        LisiereMissionDuration.hours4 => const Duration(hours: 4),
        LisiereMissionDuration.hours8 => const Duration(hours: 8),
      };
}

/// N0 is deliberately player-led only. An autonomous itinerary starts only
/// after the assigned Récolteur reaches N1.
bool canStartAutonomousHarvest({
  required LisiereJobProgress recolteur,
  required List<String> targetParcelIds,
}) =>
    recolteur.job == LisierePtipoteJob.recolteur &&
    recolteur.level == LisiereJobLevel.n1 &&
    targetParcelIds.isNotEmpty;

/// Travel is part of the selected duration, never added as a hidden cost after
/// the player has chosen 30 min / 1 h / 2 h / 4 h / 8 h.
Duration autonomousTravelDuration({
  required Iterable<TravelEdge> outboundEdges,
  LisiereV2Config? config,
}) {
  final active = config ?? lisiereV2Config;
  return Duration(
    seconds: outboundEdges.fold<int>(
          0,
          (total, edge) => total + active.travelSeconds(edge.difficulty),
        ) *
        2,
  );
}

class LisiereAutonomousWorkResult {
  const LisiereAutonomousWorkResult({
    required this.actionsResolved,
    required this.creditedAmount,
    required this.finalVitality,
    required this.stoppedForReturnReserve,
    required this.stoppedForCapacity,
  });

  final int actionsResolved;
  final int creditedAmount;
  final int finalVitality;
  final bool stoppedForReturnReserve;
  final bool stoppedForCapacity;
}

/// Applies elapsed autonomous work independently of any Flutter timer. Target
/// parcels are read round-robin and the persisted remainder on each node is
/// retained exactly as with accompanied harvesting.
LisiereAutonomousWorkResult resolveAutonomousHarvest({
  required Duration elapsedWork,
  required List<LisiereResourceNode> targetNodes,
  required LisiereFieldInventory inventory,
  required LisiereHarvestActor actor,
  required LisiereHarvestRegime regime,
  required int baseActionVitalityCost,
  required int returnVitalityCost,
  List<LisiereFieldInventory>? inventories,
  Map<LisiereHarvestRegime, LisiereRegimeRules> rules = defaultLisiereRegimes,
  LisiereV2Config? config,
}) {
  final cargoInventories = inventories ?? <LisiereFieldInventory>[inventory];
  if (targetNodes.isEmpty || elapsedWork <= Duration.zero) {
    return LisiereAutonomousWorkResult(
      actionsResolved: 0,
      creditedAmount: 0,
      finalVitality: actor.currentVitality,
      stoppedForReturnReserve: false,
      stoppedForCapacity: false,
    );
  }
  final maximumActions = (elapsedWork.inMilliseconds /
          1000 *
          effectiveActionFrequency(
              baseFrequency: actor.actionFrequency,
              regime: regime,
              rules: rules))
      .floor();
  final actionCost = missionActionVitalityCost(
    baseActionCost: baseActionVitalityCost,
    regime: regime,
    rules: rules,
  );
  var vitality = actor.currentVitality;
  var actions = 0;
  var credited = 0;
  var stoppedForReturn = false;
  var stoppedForCapacity = false;
  for (var index = 0; index < maximumActions; index += 1) {
    if (!canSpendVitality(
      currentVitality: vitality,
      actionCost: actionCost,
      returnCostFromDestination: returnVitalityCost,
      config: config,
    )) {
      stoppedForReturn = true;
      break;
    }
    final node = targetNodes[index % targetNodes.length];
    final cargo = cargoInventories
        .where((candidate) => candidate.canAccept(node.kind))
        .firstOrNull;
    if (cargo == null) {
      stoppedForCapacity = true;
      break;
    }
    final resolution = node.applyAction(actor);
    vitality -= actionCost;
    actions += 1;
    credited += cargo.add(resolution.resource, resolution.creditedAmount);
  }
  return LisiereAutonomousWorkResult(
    actionsResolved: actions,
    creditedAmount: credited,
    finalVitality: vitality,
    stoppedForReturnReserve: stoppedForReturn,
    stoppedForCapacity: stoppedForCapacity,
  );
}

class LisierePTibugMaintenance {
  LisierePTibugMaintenance({
    required this.ptibugId,
    required this.dailyRation,
    required this.lastResolvedAt,
    this.rationReserve = 0,
    this.sleepUntil,
  });

  final String ptibugId;
  final double dailyRation;
  double rationReserve;
  DateTime lastResolvedAt;
  DateTime? sleepUntil;

  bool get isSleeping => sleepUntil?.isAfter(DateTime.now()) ?? false;

  /// [rationReserve] is the persisted fraction of one daily V1 ration. The
  /// service buys the V1 recipe atomically when a P'TIBUG is refuelled; this
  /// counter then survives a close/reopen without requiring a running timer.
  double resolveMaintenanceUntil(DateTime target) {
    if (!target.isAfter(lastResolvedAt)) return 0;
    final consumed = dailyRation *
        target.difference(lastResolvedAt).inMilliseconds /
        const Duration(days: 1).inMilliseconds;
    final paid = consumed.clamp(0, rationReserve).toDouble();
    rationReserve = (rationReserve - paid).clamp(0, double.infinity);
    lastResolvedAt = target;
    return paid;
  }

  void feed(double amount) {
    if (amount > 0) rationReserve += amount;
  }

  void startSleep({required DateTime now, required Duration duration}) {
    sleepUntil = now.add(duration);
  }
}

class LisiereRegimeRules {
  const LisiereRegimeRules({
    required this.actionFrequencyMultiplier,
    required this.vitalityCostMultiplier,
  });

  final double actionFrequencyMultiplier;
  final double vitalityCostMultiplier;
}

const Map<LisiereHarvestRegime, LisiereRegimeRules> defaultLisiereRegimes =
    <LisiereHarvestRegime, LisiereRegimeRules>{
  LisiereHarvestRegime.doux: LisiereRegimeRules(
    actionFrequencyMultiplier: .75,
    vitalityCostMultiplier: .75,
  ),
  LisiereHarvestRegime.normal: LisiereRegimeRules(
    actionFrequencyMultiplier: 1,
    vitalityCostMultiplier: 1,
  ),
  LisiereHarvestRegime.intensif: LisiereRegimeRules(
    actionFrequencyMultiplier: 1.25,
    vitalityCostMultiplier: 1.25,
  ),
};

/// Action costs are absolute gameplay values. Higher max Vitality creates
/// longer autonomy because the base action does not scale with the maximum.
int missionActionVitalityCost({
  required int baseActionCost,
  required LisiereHarvestRegime regime,
  Map<LisiereHarvestRegime, LisiereRegimeRules> rules = defaultLisiereRegimes,
}) =>
    (baseActionCost * rules[regime]!.vitalityCostMultiplier).ceil();

double effectiveActionFrequency({
  required double baseFrequency,
  required LisiereHarvestRegime regime,
  Map<LisiereHarvestRegime, LisiereRegimeRules> rules = defaultLisiereRegimes,
}) =>
    baseFrequency * rules[regime]!.actionFrequencyMultiplier;

class OutpostInstance {
  const OutpostInstance({
    required this.id,
    required this.biomeId,
    required this.storageId,
    required this.state,
    this.parcelId,
    this.buildingIds = const <String>[],
  });

  final String id;
  final String biomeId;
  final String? parcelId;
  final String storageId;
  final String state;
  final List<String> buildingIds;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'biomeId': biomeId,
        'parcelId': parcelId,
        'storageId': storageId,
        'state': state,
        'buildingIds': buildingIds,
      };

  factory OutpostInstance.fromMap(Map<String, dynamic> map) => OutpostInstance(
        id: map['id'] as String,
        biomeId: map['biomeId'] as String,
        parcelId: map['parcelId'] as String?,
        storageId: map['storageId'] as String,
        state: map['state'] as String? ?? 'active',
        buildingIds:
            List<String>.from(map['buildingIds'] as List? ?? const <String>[]),
      );
}

/// Runtime statistics are copied from the actual figurine only when it is
/// linked. Afterwards the Lisière owns the current vitalité, so a V1 refresh
/// can never overwrite an expedition already in progress.
class LisierePtipoteState {
  LisierePtipoteState({
    required this.id,
    required this.displayName,
    required this.currentVitality,
    required this.maxVitality,
    this.carryCapacity = 20,
    this.harvestPower = 1,
    this.actionFrequency = 1,
    this.yieldModifier = 1,
    this.organicYieldModifier = 1,
    this.mineralYieldModifier = 1,
    this.wasteYieldModifier = 1,
    this.security = 0,
  });

  final String id;
  final String displayName;
  int currentVitality;
  final int maxVitality;
  final int carryCapacity;
  final double harvestPower;
  final double actionFrequency;
  final double yieldModifier;
  final double organicYieldModifier;
  final double mineralYieldModifier;
  final double wasteYieldModifier;
  double security;

  double yieldModifierFor(LisiereResourceKind kind) => switch (kind) {
        LisiereResourceKind.organic => organicYieldModifier,
        LisiereResourceKind.mineral => mineralYieldModifier,
        LisiereResourceKind.waste => wasteYieldModifier,
      };

  LisiereHarvestActor get harvestActor => LisiereHarvestActor(
        id: id,
        harvestPower: harvestPower,
        actionFrequency: actionFrequency,
        yieldModifier: yieldModifier,
        maxVitality: maxVitality,
        currentVitality: currentVitality,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'currentVitality': currentVitality,
        'maxVitality': maxVitality,
        'carryCapacity': carryCapacity,
        'harvestPower': harvestPower,
        'actionFrequency': actionFrequency,
        'yieldModifier': yieldModifier,
        'organicYieldModifier': organicYieldModifier,
        'mineralYieldModifier': mineralYieldModifier,
        'wasteYieldModifier': wasteYieldModifier,
        'security': security,
      };

  factory LisierePtipoteState.fromMap(Map<String, dynamic> map) =>
      LisierePtipoteState(
        id: map['id'] as String,
        displayName: map['displayName'] as String? ?? 'P’TIPOTE',
        currentVitality: (map['currentVitality'] as num?)?.toInt() ?? 100,
        maxVitality: (map['maxVitality'] as num?)?.toInt() ?? 100,
        carryCapacity: (map['carryCapacity'] as num?)?.toInt() ?? 20,
        harvestPower: (map['harvestPower'] as num?)?.toDouble() ?? 1,
        actionFrequency: (map['actionFrequency'] as num?)?.toDouble() ?? 1,
        yieldModifier: (map['yieldModifier'] as num?)?.toDouble() ?? 1,
        organicYieldModifier:
            (map['organicYieldModifier'] as num?)?.toDouble() ??
                (map['yieldModifier'] as num?)?.toDouble() ??
                1,
        mineralYieldModifier:
            (map['mineralYieldModifier'] as num?)?.toDouble() ??
                (map['yieldModifier'] as num?)?.toDouble() ??
                1,
        wasteYieldModifier: (map['wasteYieldModifier'] as num?)?.toDouble() ??
            (map['yieldModifier'] as num?)?.toDouble() ??
            1,
        security: (map['security'] as num?)?.toDouble() ?? 0,
      );
}

class LisiereTeam {
  LisiereTeam({
    required this.id,
    required this.ptipoteIds,
    required this.fieldInventoryId,
    this.ptibugIds = const <String>[],
    this.hasTeamManagementStructure = false,
    this.logisticsOptimizationModules = 0,
    this.currentParcelId,
    Set<String>? unavailableCarrierIds,
  }) : unavailableCarrierIds = unavailableCarrierIds ?? <String>{};

  final String id;
  final List<String> ptipoteIds;
  final List<String> ptibugIds;
  final String fieldInventoryId;
  final bool hasTeamManagementStructure;
  final int logisticsOptimizationModules;
  String? currentParcelId;
  final Set<String> unavailableCarrierIds;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'ptipoteIds': ptipoteIds,
        'ptibugIds': ptibugIds,
        'fieldInventoryId': fieldInventoryId,
        'hasTeamManagementStructure': hasTeamManagementStructure,
        'logisticsOptimizationModules': logisticsOptimizationModules,
        'currentParcelId': currentParcelId,
        'unavailableCarrierIds': unavailableCarrierIds.toList(),
      };

  factory LisiereTeam.fromMap(Map<String, dynamic> map) => LisiereTeam(
        id: map['id'] as String,
        ptipoteIds:
            List<String>.from(map['ptipoteIds'] as List? ?? const <String>[]),
        ptibugIds:
            List<String>.from(map['ptibugIds'] as List? ?? const <String>[]),
        fieldInventoryId: map['fieldInventoryId'] as String,
        hasTeamManagementStructure:
            map['hasTeamManagementStructure'] as bool? ?? false,
        logisticsOptimizationModules:
            (map['logisticsOptimizationModules'] as num?)?.toInt() ?? 0,
        currentParcelId: map['currentParcelId'] as String?,
        unavailableCarrierIds: Set<String>.from(
          map['unavailableCarrierIds'] as List? ?? const <String>[],
        ),
      );
}

class LisierePTibugState {
  LisierePTibugState({
    required this.id,
    required this.displayName,
    required this.capacity,
    required this.maintenance,
    this.speciesId = 'scarabe',
    this.traitDefinitionIds = const <String>[],
    this.currentVitality = 100,
    this.maxVitality = 100,
  });

  final String id;
  final String displayName;
  final int capacity;
  final LisierePTibugMaintenance maintenance;
  final String speciesId;
  final List<String> traitDefinitionIds;
  int currentVitality;
  final int maxVitality;

  List<LisiereResourceKind> get preferredResources => switch (speciesId) {
        'scarabe' => const <LisiereResourceKind>[LisiereResourceKind.mineral],
        'hyme' => const <LisiereResourceKind>[LisiereResourceKind.organic],
        'arac' => const <LisiereResourceKind>[
            LisiereResourceKind.waste,
            LisiereResourceKind.organic,
          ],
        _ => const <LisiereResourceKind>[],
      };

  /// Arac is the native territorial cleaner. The existing Récupérateur trait
  /// grants the same ecology-cleaner role without changing cargo rules.
  bool get isEcologyCleaner =>
      speciesId == 'arac' || traitDefinitionIds.contains('recuperateur');

  double yieldModifierFor(LisiereResourceKind kind) {
    final hasMatchingTrait = (kind == LisiereResourceKind.mineral &&
            traitDefinitionIds.contains('mineur')) ||
        (kind == LisiereResourceKind.organic &&
            traitDefinitionIds.contains('pollinisateur')) ||
        (kind == LisiereResourceKind.waste &&
            traitDefinitionIds.contains('recuperateur'));
    return hasMatchingTrait ? 1.1 : 1;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'capacity': capacity,
        'speciesId': speciesId,
        'traitDefinitionIds': traitDefinitionIds,
        'currentVitality': currentVitality,
        'maxVitality': maxVitality,
        'maintenance': <String, dynamic>{
          'dailyRation': maintenance.dailyRation,
          'rationReserve': maintenance.rationReserve,
          'lastResolvedAt': maintenance.lastResolvedAt.millisecondsSinceEpoch,
          'sleepUntil': maintenance.sleepUntil?.millisecondsSinceEpoch,
        },
      };

  factory LisierePTibugState.fromMap(Map<String, dynamic> map) {
    final raw = map['maintenance'] as Map? ?? const <String, dynamic>{};
    return LisierePTibugState(
      id: map['id'] as String,
      displayName: map['displayName'] as String? ?? 'P’TIBUG',
      capacity: (map['capacity'] as num?)?.toInt() ?? 20,
      speciesId: map['speciesId'] as String? ?? 'scarabe',
      traitDefinitionIds: List<String>.from(
        map['traitDefinitionIds'] as List? ?? const <String>[],
      ),
      currentVitality: (map['currentVitality'] as num?)?.toInt() ?? 100,
      maxVitality: (map['maxVitality'] as num?)?.toInt() ?? 100,
      maintenance: LisierePTibugMaintenance(
        ptibugId: map['id'] as String,
        dailyRation: (raw['dailyRation'] as num?)?.toDouble() ?? 1,
        rationReserve: (raw['rationReserve'] as num?)?.toDouble() ?? 0,
        lastResolvedAt: raw['lastResolvedAt'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (raw['lastResolvedAt'] as num).toInt())
            : DateTime.now(),
        sleepUntil: raw['sleepUntil'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (raw['sleepUntil'] as num).toInt())
            : null,
      ),
    );
  }
}

class LisiereMissionInstance {
  LisiereMissionInstance({
    required this.id,
    required this.teamId,
    required this.originId,
    required this.plannedDuration,
    required this.startedAt,
    required this.routeParcelIds,
    required this.targetParcelIds,
    required this.randomSeed,
    this.travelDuration = Duration.zero,
    List<String>? routeBiomeIds,
    this.regime = LisiereHarvestRegime.normal,
    this.status = LisiereMissionStatus.planned,
    DateTime? lastResolvedAt,
  })  : routeBiomeIds = routeBiomeIds ?? <String>[],
        plannedEndAt = startedAt.add(plannedDuration),
        lastResolvedAt = lastResolvedAt ?? startedAt;

  final String id;
  final String teamId;
  final String originId;
  final Duration plannedDuration;
  final DateTime startedAt;
  final DateTime plannedEndAt;
  final List<String> routeParcelIds;
  final List<String> targetParcelIds;
  final int randomSeed;
  final Duration travelDuration;
  final List<String> routeBiomeIds;
  final LisiereHarvestRegime regime;
  LisiereMissionStatus status;
  DateTime lastResolvedAt;
  final Set<String> appliedResolutionIds = <String>{};
  final Set<String> workedBiomeIds = <String>{};
  final Set<String> resolvedBiomeEntryIds = <String>{};

  Duration get outboundTravelDuration =>
      Duration(seconds: travelDuration.inSeconds ~/ 2);
  Duration get returnTravelDuration => Duration(
        seconds: travelDuration.inSeconds - outboundTravelDuration.inSeconds,
      );
  DateTime get workStartsAt => startedAt.add(outboundTravelDuration);
  DateTime get returnStartsAt => plannedEndAt.subtract(returnTravelDuration);
  Duration workDurationAt(DateTime target) {
    final bounded = target.isAfter(returnStartsAt) ? returnStartsAt : target;
    if (!bounded.isAfter(workStartsAt)) return Duration.zero;
    return bounded.difference(workStartsAt);
  }

  LisiereMissionStatus stageAt(DateTime target) {
    if (!target.isAfter(workStartsAt)) return LisiereMissionStatus.traveling;
    if (!target.isAfter(returnStartsAt)) return LisiereMissionStatus.working;
    return target.isBefore(plannedEndAt)
        ? LisiereMissionStatus.returning
        : LisiereMissionStatus.completed;
  }

  /// Resolving the same time window twice has no effect: the resolver keeps a
  /// stable interval id, rather than relying on an active Flutter timer.
  bool resolveUntil(DateTime target) {
    if (status == LisiereMissionStatus.completed ||
        status == LisiereMissionStatus.cancelled) {
      return false;
    }
    final bounded = target.isAfter(plannedEndAt) ? plannedEndAt : target;
    if (!bounded.isAfter(lastResolvedAt)) return false;
    final eventId =
        '$id:${lastResolvedAt.microsecondsSinceEpoch}:${bounded.microsecondsSinceEpoch}';
    if (!appliedResolutionIds.add(eventId)) return false;
    lastResolvedAt = bounded;
    status = bounded == plannedEndAt
        ? LisiereMissionStatus.completed
        : LisiereMissionStatus.working;
    return true;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'teamId': teamId,
        'originId': originId,
        'plannedDurationSeconds': plannedDuration.inSeconds,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'routeParcelIds': routeParcelIds,
        'targetParcelIds': targetParcelIds,
        'randomSeed': randomSeed,
        'travelSeconds': travelDuration.inSeconds,
        'routeBiomeIds': routeBiomeIds,
        'regime': regime.name,
        'status': status.name,
        'lastResolvedAt': lastResolvedAt.millisecondsSinceEpoch,
        'appliedResolutionIds': appliedResolutionIds.toList(),
        'workedBiomeIds': workedBiomeIds.toList(),
        'resolvedBiomeEntryIds': resolvedBiomeEntryIds.toList(),
      };

  factory LisiereMissionInstance.fromMap(Map<String, dynamic> map) {
    final mission = LisiereMissionInstance(
      id: map['id'] as String,
      teamId: map['teamId'] as String,
      originId: map['originId'] as String,
      plannedDuration:
          Duration(seconds: (map['plannedDurationSeconds'] as num).toInt()),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['startedAt'] as num).toInt()),
      routeParcelIds: List<String>.from(map['routeParcelIds'] as List),
      targetParcelIds: List<String>.from(map['targetParcelIds'] as List),
      randomSeed: (map['randomSeed'] as num).toInt(),
      travelDuration:
          Duration(seconds: (map['travelSeconds'] as num?)?.toInt() ?? 0),
      routeBiomeIds: List<String>.from(
        map['routeBiomeIds'] as List? ?? const <String>[],
      ),
      regime: map['regime'] is String
          ? LisiereHarvestRegime.values.byName(map['regime'] as String)
          : LisiereHarvestRegime.normal,
      status: LisiereMissionStatus.values.byName(map['status'] as String),
      lastResolvedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['lastResolvedAt'] as num).toInt(),
      ),
    );
    mission.appliedResolutionIds.addAll(
      List<String>.from(
          map['appliedResolutionIds'] as List? ?? const <String>[]),
    );
    mission.workedBiomeIds.addAll(
      List<String>.from(map['workedBiomeIds'] as List? ?? const <String>[]),
    );
    mission.resolvedBiomeEntryIds.addAll(
      List<String>.from(
        map['resolvedBiomeEntryIds'] as List? ?? const <String>[],
      ),
    );
    return mission;
  }
}

class BiomeDangerState {
  BiomeDangerState({
    required this.biomeId,
    required this.danger,
    required this.dangerCap,
    required this.lastResolvedAt,
    this.bossDroneActive = false,
    this.lastBossDroneOutcome,
  });

  final String biomeId;
  int danger;
  final int dangerCap;
  DateTime lastResolvedAt;
  bool bossDroneActive;
  String? lastBossDroneOutcome;
  final Set<String> exploitationMissionIds = <String>{};

  void resolveNaturalIncrease(DateTime target, {int pointsPerTwoHours = 1}) {
    if (!target.isAfter(lastResolvedAt)) return;
    final ticks = target.difference(lastResolvedAt).inMinutes ~/ 120;
    if (ticks <= 0) return;
    danger = (danger + ticks * pointsPerTwoHours).clamp(0, dangerCap).toInt();
    lastResolvedAt = lastResolvedAt.add(Duration(hours: ticks * 2));
  }

  bool markExploited(String missionId, {int reduction = 5}) {
    if (!exploitationMissionIds.add(missionId)) return false;
    danger = (danger - reduction).clamp(0, dangerCap).toInt();
    if (danger <= 10) bossDroneActive = false;
    return true;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'biomeId': biomeId,
        'danger': danger,
        'dangerCap': dangerCap,
        'lastResolvedAt': lastResolvedAt.millisecondsSinceEpoch,
        'bossDroneActive': bossDroneActive,
        'lastBossDroneOutcome': lastBossDroneOutcome,
        'exploitationMissionIds': exploitationMissionIds.toList(),
      };

  factory BiomeDangerState.fromMap(Map<String, dynamic> map) {
    final danger = BiomeDangerState(
      biomeId: map['biomeId'] as String,
      danger: (map['danger'] as num).toInt(),
      dangerCap: (map['dangerCap'] as num).toInt(),
      lastResolvedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['lastResolvedAt'] as num).toInt(),
      ),
      bossDroneActive: map['bossDroneActive'] as bool? ?? false,
      lastBossDroneOutcome: map['lastBossDroneOutcome'] as String?,
    );
    danger.exploitationMissionIds.addAll(
      List<String>.from(
          map['exploitationMissionIds'] as List? ?? const <String>[]),
    );
    return danger;
  }
}

double finalEncounterChance(
    {required int biomeDanger, required double groupSecurity}) {
  final security = groupSecurity.clamp(0, 100) / 100;
  return (biomeDanger.clamp(0, 100) * (1 - security)).toDouble();
}

enum LisiereEncounterType { toxic, standardDrone, fall }

class LisiereEncounterResolution {
  const LisiereEncounterResolution({
    required this.type,
    required this.cargoLossPercent,
    required this.vitalityLossPercent,
    required this.appliesToxicAffliction,
  });

  final LisiereEncounterType type;
  final double cargoLossPercent;
  final double vitalityLossPercent;
  final bool appliesToxicAffliction;

  int cargoLost(int cargoAmount) =>
      truncatedLoss(cargoAmount, cargoLossPercent);

  int vitalityAfter({
    required int currentVitality,
    required int maxVitality,
    required int requiredReturnVitality,
  }) =>
      vitalityAfterEncounter(
        currentVitality: currentVitality,
        maxVitality: maxVitality,
        lossPercent: vitalityLossPercent,
        requiredReturnVitality: requiredReturnVitality,
      );
}

const Map<LisiereEncounterType, LisiereEncounterResolution>
    defaultLisiereEncounterResolutions =
    <LisiereEncounterType, LisiereEncounterResolution>{
  LisiereEncounterType.toxic: LisiereEncounterResolution(
    type: LisiereEncounterType.toxic,
    cargoLossPercent: .10,
    vitalityLossPercent: 0,
    appliesToxicAffliction: true,
  ),
  LisiereEncounterType.standardDrone: LisiereEncounterResolution(
    type: LisiereEncounterType.standardDrone,
    cargoLossPercent: .25,
    vitalityLossPercent: .15,
    appliesToxicAffliction: false,
  ),
  LisiereEncounterType.fall: LisiereEncounterResolution(
    type: LisiereEncounterType.fall,
    cargoLossPercent: .10,
    vitalityLossPercent: .20,
    appliesToxicAffliction: false,
  ),
};

/// A seeded roll allows offline replay and guarantees a maximum of one
/// encounter for the same biome visit. The `visitId` belongs to the mission
/// checkpoint, never to a rendered screen.
LisiereEncounterResolution? resolveBiomeEntryEncounter({
  required String visitId,
  required int randomSeed,
  required int biomeDanger,
  required double groupSecurity,
  required Set<String> resolvedVisitIds,
}) {
  if (!resolvedVisitIds.add(visitId)) return null;
  final roller = _SeededRoller(randomSeed ^ lisiereStableSeed(visitId));
  final chance = finalEncounterChance(
    biomeDanger: biomeDanger,
    groupSecurity: groupSecurity,
  );
  if (roller.nextInt(100) >= chance) return null;
  return defaultLisiereEncounterResolutions[LisiereEncounterType
      .values[roller.nextInt(LisiereEncounterType.values.length)]];
}

int truncatedLoss(int amount, double percent) =>
    (amount * percent.clamp(0, 1)).truncate();

int vitalityAfterEncounter({
  required int currentVitality,
  required int maxVitality,
  required double lossPercent,
  required int requiredReturnVitality,
}) =>
    (currentVitality - truncatedLoss(maxVitality, lossPercent))
        .clamp(requiredReturnVitality, currentVitality)
        .toInt();

enum BossDroneOutcome { neutralized, interrupted }

BossDroneOutcome resolveAutonomousBossDrone({required double groupSecurity}) =>
    groupSecurity >= 50
        ? BossDroneOutcome.neutralized
        : BossDroneOutcome.interrupted;

class LisiereStarterMission {
  LisiereStarterMission({
    this.id = 'premiers-materiaux',
    this.organicsRequired = 5,
    this.mineralsRequired = 3,
    this.completedAt,
  });

  final String id;
  final int organicsRequired;
  final int mineralsRequired;
  DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  String get message =>
      'Nous avons besoin de matière organique pour la nourriture et de minéraux pour finir les tentes. Rapporte autant que tu peux transporter ; déjà $organicsRequired Organique et $mineralsRequired Minéral nous aideront beaucoup.';

  void refreshFromCamp(LisiereFieldInventory camp, DateTime now) {
    if (isCompleted ||
        (camp.amounts[LisiereResourceKind.organic] ?? 0) < organicsRequired ||
        (camp.amounts[LisiereResourceKind.mineral] ?? 0) < mineralsRequired) {
      return;
    }
    completedAt = now;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'organicsRequired': organicsRequired,
        'mineralsRequired': mineralsRequired,
        'completedAt': completedAt?.millisecondsSinceEpoch,
      };

  factory LisiereStarterMission.fromMap(Map<String, dynamic> map) =>
      LisiereStarterMission(
        id: map['id'] as String? ?? 'premiers-materiaux',
        organicsRequired: (map['organicsRequired'] as num?)?.toInt() ?? 5,
        mineralsRequired: (map['mineralsRequired'] as num?)?.toInt() ?? 3,
        completedAt: map['completedAt'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (map['completedAt'] as num).toInt())
            : null,
      );
}

class LisierePlayerLoadout {
  const LisierePlayerLoadout({
    this.toolId = 'multi-outils-de-base',
    this.equipmentId,
  });

  final String toolId;
  final String? equipmentId;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'toolId': toolId,
        'equipmentId': equipmentId,
      };

  factory LisierePlayerLoadout.fromMap(Map<String, dynamic> map) =>
      LisierePlayerLoadout(
        toolId: map['toolId'] as String? ?? 'multi-outils-de-base',
        equipmentId: map['equipmentId'] as String?,
      );
}

/// Persistable V2 state. Every inventory is keyed by its physical location;
/// transfers are represented by a rotation and never by writing a resource
/// directly from one stock into another.
class LisiereV2Snapshot {
  LisiereV2Snapshot({
    required this.version,
    required this.graphs,
    required this.nodes,
    required this.inventories,
    required this.jobProgress,
    required this.dangers,
    required this.missions,
    required this.updatedAt,
    Map<String, LisierePtipoteState>? ptipotes,
    Map<String, LisiereTeam>? teams,
    Map<String, LisierePTibugState>? ptibugs,
    Map<String, OutpostInstance>? outposts,
    Map<String, LisiereCargoRotation>? rotations,
    Set<String>? resolvedVisitIds,
    Map<String, String>? pendingToxicAfflictions,
    Map<String, List<String>>? biomeConnections,
    LisiereStarterMission? starterMission,
    LisierePlayerLoadout? playerLoadout,
  })  : ptipotes = Map<String, LisierePtipoteState>.from(ptipotes ?? const {}),
        teams = Map<String, LisiereTeam>.from(teams ?? const {}),
        ptibugs = Map<String, LisierePTibugState>.from(ptibugs ?? const {}),
        outposts = Map<String, OutpostInstance>.from(outposts ?? const {}),
        rotations =
            Map<String, LisiereCargoRotation>.from(rotations ?? const {}),
        resolvedVisitIds = Set<String>.from(resolvedVisitIds ?? const {}),
        pendingToxicAfflictions =
            Map<String, String>.from(pendingToxicAfflictions ?? const {}),
        biomeConnections = Map<String, List<String>>.fromEntries(
          (biomeConnections ?? const <String, List<String>>{}).entries.map(
                (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
              ),
        ),
        starterMission = starterMission ?? LisiereStarterMission(),
        playerLoadout = playerLoadout ?? const LisierePlayerLoadout();

  final String version;
  final Map<String, BiomeParcelGraph> graphs;
  final Map<String, LisiereResourceNode> nodes;
  final Map<String, LisiereFieldInventory> inventories;
  final Map<String, LisiereJobProgress> jobProgress;
  final Map<String, BiomeDangerState> dangers;
  final Map<String, LisiereMissionInstance> missions;
  final Map<String, LisierePtipoteState> ptipotes;
  final Map<String, LisiereTeam> teams;
  final Map<String, LisierePTibugState> ptibugs;
  final Map<String, OutpostInstance> outposts;
  final Map<String, LisiereCargoRotation> rotations;
  final Set<String> resolvedVisitIds;

  /// V2 persists the effect request until the shared V1 affliction service
  /// acknowledges it. This preserves the unique Intoxiqué state on restart.
  final Map<String, String> pendingToxicAfflictions;

  /// Regional gateways are data, not an unlock or construction prerequisite.
  final Map<String, List<String>> biomeConnections;
  final LisiereStarterMission starterMission;
  final LisierePlayerLoadout playerLoadout;
  DateTime updatedAt;

  static const String currentVersion = 'ZONE0_V2_LISIERE_1';

  Map<String, dynamic> toMap() => <String, dynamic>{
        'version': version,
        'graphs': graphs.map((key, value) => MapEntry(key, value.toMap())),
        'nodes': nodes.map((key, value) => MapEntry(key, value.toMap())),
        'inventories':
            inventories.map((key, value) => MapEntry(key, value.toMap())),
        'jobProgress':
            jobProgress.map((key, value) => MapEntry(key, value.toMap())),
        'dangers': dangers.map((key, value) => MapEntry(key, value.toMap())),
        'missions': missions.map((key, value) => MapEntry(key, value.toMap())),
        'ptipotes': ptipotes.map((key, value) => MapEntry(key, value.toMap())),
        'teams': teams.map((key, value) => MapEntry(key, value.toMap())),
        'ptibugs': ptibugs.map((key, value) => MapEntry(key, value.toMap())),
        'outposts': outposts.map((key, value) => MapEntry(key, value.toMap())),
        'rotations':
            rotations.map((key, value) => MapEntry(key, value.toMap())),
        'resolvedVisitIds': resolvedVisitIds.toList(),
        'pendingToxicAfflictions': pendingToxicAfflictions,
        'biomeConnections': biomeConnections,
        'starterMission': starterMission.toMap(),
        'playerLoadout': playerLoadout.toMap(),
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory LisiereV2Snapshot.fromMap(Map<String, dynamic> map) {
    Map<String, T> decode<T>(
        String key, T Function(Map<String, dynamic>) read) {
      final raw = map[key];
      if (raw is! Map) return <String, T>{};
      return <String, T>{
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String:
                read(Map<String, dynamic>.from(entry.value as Map)),
      };
    }

    return LisiereV2Snapshot(
      version: map['version'] as String? ?? currentVersion,
      graphs: decode('graphs', BiomeParcelGraph.fromMap),
      nodes: decode('nodes', LisiereResourceNode.fromMap),
      inventories: decode('inventories', LisiereFieldInventory.fromMap),
      jobProgress: decode('jobProgress', LisiereJobProgress.fromMap),
      dangers: decode('dangers', BiomeDangerState.fromMap),
      missions: decode('missions', LisiereMissionInstance.fromMap),
      ptipotes: decode('ptipotes', LisierePtipoteState.fromMap),
      teams: decode('teams', LisiereTeam.fromMap),
      ptibugs: decode('ptibugs', LisierePTibugState.fromMap),
      outposts: decode('outposts', OutpostInstance.fromMap),
      rotations: decode('rotations', LisiereCargoRotation.fromMap),
      resolvedVisitIds: Set<String>.from(
        map['resolvedVisitIds'] as List? ?? const <String>[],
      ),
      pendingToxicAfflictions: Map<String, String>.from(
          map['pendingToxicAfflictions'] as Map? ?? const <String, String>{}),
      biomeConnections: (map['biomeConnections'] as Map? ?? const {})
          .map<String, List<String>>(
        (key, value) =>
            MapEntry('$key', List<String>.from(value as List? ?? const [])),
      ),
      starterMission: map['starterMission'] is Map
          ? LisiereStarterMission.fromMap(
              Map<String, dynamic>.from(map['starterMission'] as Map),
            )
          : null,
      playerLoadout: map['playerLoadout'] is Map
          ? LisierePlayerLoadout.fromMap(
              Map<String, dynamic>.from(map['playerLoadout'] as Map),
            )
          : null,
      updatedAt: map['updatedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['updatedAt'] as num).toInt())
          : DateTime.now(),
    );
  }
}

LisiereV2Snapshot createLisiereV2Snapshot({
  required Iterable<String> biomeIds,
  required int seed,
  required DateTime createdAt,
  Map<String, List<String>> biomeConnections = const <String, List<String>>{},
  Map<String, int> biomeSeeds = const <String, int>{},
  Map<String, Map<String, dynamic>> biomeVisualProfiles =
      const <String, Map<String, dynamic>>{},
}) {
  final graphs = <String, BiomeParcelGraph>{};
  final nodes = <String, LisiereResourceNode>{};
  final dangers = <String, BiomeDangerState>{};
  for (final biomeId in biomeIds) {
    final visualProfile =
        biomeVisualProfiles[biomeId] ?? const <String, dynamic>{};
    final graph = createBiomeParcelGraph(
      biomeId: biomeId,
      seed: biomeSeeds[biomeId] ?? (seed ^ lisiereStableSeed(biomeId)),
    );
    graphs[biomeId] = graph;
    dangers[biomeId] = BiomeDangerState(
      biomeId: biomeId,
      danger: 0,
      dangerCap: 100,
      lastResolvedAt: createdAt,
    );
    for (final parcel in graph.parcels) {
      final nodeSeed = seed ^ parcel.seed;
      nodes['${parcel.id}-organic'] = LisiereResourceNode.organic(
        id: '${parcel.id}-organic',
        parcelId: parcel.id,
        // ECOLOGY_0: one vitality is one physical Organique. Ten actions
        // exhaust a standard node; traits only affect the resulting bonus.
        maxResistance: 10,
        standardYield: 1,
        visualVariant: lisiereBiomeNodeVisual(
          visualProfile: visualProfile,
          kind: LisiereResourceKind.organic,
          seed: nodeSeed,
        ),
        regenerationReference: createdAt,
      );
      nodes['${parcel.id}-mineral'] = LisiereResourceNode.mineral(
        id: '${parcel.id}-mineral',
        parcelId: parcel.id,
        maxResistance: (6 + (nodeSeed & 3)).toDouble(),
        standardYield: 2 + (nodeSeed % 4),
        remainingLayers: 1 + (nodeSeed.abs() % 3),
        visualVariant: lisiereBiomeNodeVisual(
          visualProfile: visualProfile,
          kind: LisiereResourceKind.mineral,
          seed: nodeSeed,
        ),
      );
      nodes['${parcel.id}-waste'] = LisiereResourceNode.waste(
        id: '${parcel.id}-waste',
        parcelId: parcel.id,
        maxResistance: 10,
        standardYield: 1,
        remainingLayers: 1,
        visualVariant: lisiereBiomeNodeVisual(
          visualProfile: visualProfile,
          kind: LisiereResourceKind.waste,
          seed: nodeSeed,
        ),
      );
    }
  }
  return LisiereV2Snapshot(
    version: LisiereV2Snapshot.currentVersion,
    graphs: graphs,
    nodes: nodes,
    inventories: <String, LisiereFieldInventory>{
      'camp-storage-v2':
          LisiereFieldInventory(id: 'camp-storage-v2', capacity: 250),
    },
    jobProgress: <String, LisiereJobProgress>{},
    dangers: dangers,
    missions: <String, LisiereMissionInstance>{},
    biomeConnections: biomeConnections,
    updatedAt: createdAt,
  );
}

/// The visual profile is data-driven; emoji remain the prototype art bank
/// until final sprites arrive. This does not change resource economics.
String lisiereBiomeNodeVisual({
  required Map<String, dynamic> visualProfile,
  required LisiereResourceKind kind,
  required int seed,
}) {
  final ground = '${visualProfile['groundSet'] ?? ''}';
  final variants = switch (kind) {
    LisiereResourceKind.organic => switch (ground) {
        'shore' => const <String>['🪸', '🌿', '🐚'],
        'wet_roots' || 'marsh' => const <String>['🌱', '🪷', '🍄'],
        'sand' || 'dry_grass' => const <String>['🌵', '🌾', '🪵'],
        'highland' || 'hillside' => const <String>['🌿', '🍄', '🌲'],
        _ => const <String>['🌿', '🍄', '🌾'],
      },
    LisiereResourceKind.mineral => switch (ground) {
        'shore' => const <String>['🪨', '🐚', '💎'],
        'sand' => const <String>['🪨', '⛏️', '🟤'],
        'highland' || 'hillside' => const <String>['⛰️', '🪨', '💎'],
        _ => const <String>['🪨', '⛏️', '💎'],
      },
    LisiereResourceKind.waste => switch (ground) {
        'shore' || 'wet_roots' || 'marsh' => const <String>['🧴', '🪵', '♻️'],
        _ => const <String>['♻️', '🧰', '🪵'],
      },
  };
  return variants[seed.abs() % variants.length];
}

int lisiereStableSeed(String value) {
  var hash = 17;
  for (final codeUnit in value.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash;
}

/// Small local PRNG. It avoids `Random()` so a graph never depends on device
/// state or the number of times it was reconstructed.
class _SeededRoller {
  _SeededRoller(int seed) : _state = seed & 0x7fffffff;

  int _state;

  int nextInt(int upperBound) {
    _state = (1103515245 * _state + 12345) & 0x7fffffff;
    return _state % upperBound;
  }
}

BiomeParcelGraph createBiomeParcelGraph({
  required String biomeId,
  required int seed,
  LisiereV2Config? config,
}) {
  final active = config ?? lisiereV2Config;
  final roller = _SeededRoller(seed);
  final parcelCount = active.minimumParcels +
      roller.nextInt(active.maximumParcels - active.minimumParcels + 1);
  final ids = List<String>.generate(
    parcelCount,
    (index) => '$biomeId-parcel-${index + 1}',
    growable: false,
  );
  final links = <String, Set<String>>{for (final id in ids) id: <String>{}};
  final edges = <TravelEdge>[];

  void addEdge(String first, String second) {
    if (links[first]!.contains(second)) return;
    links[first]!.add(second);
    links[second]!.add(first);
    final difficulty = LisiereTravelDifficulty
        .values[roller.nextInt(LisiereTravelDifficulty.values.length)];
    edges.add(TravelEdge(
      id: 'edge-$first-$second',
      fromParcelId: first,
      toParcelId: second,
      difficulty: difficulty,
    ));
  }

  // A connected backbone, then deterministic optional branches. The result is
  // never a mandatory linear route because a branch is guaranteed for 6+.
  for (var index = 1; index < ids.length; index += 1) {
    addEdge(ids[index - 1], ids[index]);
  }
  addEdge(ids[0], ids[2]);
  if (ids.length >= 7) addEdge(ids[2], ids[roller.nextInt(ids.length - 3) + 3]);
  if (ids.length >= 8) addEdge(ids[1], ids[ids.length - 2]);

  final parcels = List<ParcelInstance>.generate(
    ids.length,
    (index) => ParcelInstance(
      id: ids[index],
      biomeId: biomeId,
      ordinal: index,
      seed: seed ^ index,
      connectedParcelIds: links[ids[index]]!.toList()..sort(),
      compatibleInfrastructureSlots: 1,
    ),
    growable: false,
  );
  return BiomeParcelGraph(
    biomeId: biomeId,
    seed: seed,
    parcels: parcels,
    edges: List<TravelEdge>.unmodifiable(edges),
  );
}
