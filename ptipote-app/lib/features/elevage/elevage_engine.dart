import 'dart:convert';
import 'dart:math';

import 'elevage_config.dart';

const int elevageSaveSchemaVersion = 1;

class ElevageSave {
  ElevageSave(this.data);

  final Map<String, dynamic> data;

  factory ElevageSave.initial(ElevageConfig config, {required int now}) {
    return ElevageSave(<String, dynamic>{
      'schemaVersion': elevageSaveSchemaVersion,
      'savedAt': now,
      'activeConfigRevision': config.revision,
      'inventory': <String, dynamic>{
        'generic': <String, int>{'organic': 0, 'mineral': 0},
        'special': <String, int>{'ROOT': 1, 'LEAF': 1},
        'bioPiles': 0,
      },
      'alcoves': List<Map<String, dynamic>>.generate(
        config.alcoveCount,
        (index) => <String, dynamic>{
          'id': 'alcove-${index + 1}',
          'slotLimit': config.installationSlotCount,
          'occupantIndividualId': null,
          'slots': List<dynamic>.filled(config.installationSlotCount, null),
          'createdAt': now,
        },
      ),
      'individuals': <String, dynamic>{},
      'activeIndividualIds': <String>[],
      'discoveredItemIds': <String>[],
      'installationInventory': <String, dynamic>{},
      // Items placed in the four visible Alcôve zones. They are deliberately
      // separate from both the player inventory and installed constructions.
      'sceneItemsByAlcoveId': <String, dynamic>{},
      'runsByIndividualId': <String, dynamic>{},
      'memoryEvents': <String, dynamic>{},
      'coRearingReturnLedger': <String, dynamic>{},
      'pendingNotifications': <dynamic>[],
      // Marqueur déjà appliqué aux nouvelles parties : les anciennes saves
      // reçoivent le même starter lors de leur première ouverture Lot 17.
      'qaInventoryResetV17': true,
    });
  }

  factory ElevageSave.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != elevageSaveSchemaVersion) {
      throw const FormatException('Version de sauvegarde Élevage inconnue.');
    }
    final normalized = _clone(json);
    normalized.putIfAbsent('runsByIndividualId', () => <String, dynamic>{});
    normalized.putIfAbsent('installationInventory', () => <String, dynamic>{});
    normalized.putIfAbsent('sceneItemsByAlcoveId', () => <String, dynamic>{});
    normalized.putIfAbsent('discoveredItemIds', () => <String>[]);
    normalized.putIfAbsent('coRearingReturnLedger', () => <String, dynamic>{});
    normalized.putIfAbsent('pendingNotifications', () => <dynamic>[]);
    // Migration QA one-shot, strictement limitée à la sauvegarde Élevage.
    // Elle enlève les stocks de test historiques sans toucher Zone 0 ni la
    // configuration locale, puis restitue le starter normal minimal.
    if (normalized['qaInventoryResetV17'] != true) {
      normalized['inventory'] = <String, dynamic>{
        'generic': <String, int>{'organic': 0, 'mineral': 0},
        'special': <String, int>{'ROOT': 1, 'LEAF': 1},
        'bioPiles': 0,
      };
      normalized['qaInventoryResetV17'] = true;
    }
    final individuals = normalized['individuals'] as Map?;
    individuals?.forEach((_, raw) {
      if (raw is Map) {
        raw.putIfAbsent('observationJournal',
            () => <String, dynamic>{'observations': <String, dynamic>{}});
        raw.putIfAbsent(
            'wellbeing',
            () => <String, dynamic>{
                  'value': 60,
                  'lastUpdatedAt': normalized['savedAt'] ?? 0,
                });
        raw.putIfAbsent('activeRequest', () => null);
        raw.putIfAbsent(
            'social',
            () => <String, dynamic>{
                  'cuddleCooldownUntil': 0,
                  'cuddleAttempts': 0,
                  'lastReaction': 'NEUTRAL',
                });
        final personality = raw['personality'];
        if (personality is Map) {
          personality.putIfAbsent(
              'development',
              () => <String, dynamic>{
                    'babyExperience': <String, int>{
                      'initiative': 0,
                      'contact': 0,
                      'tempo': 0,
                    },
                    'intermediateExperience': <String, int>{
                      'initiative': 0,
                      'contact': 0,
                      'tempo': 0,
                    },
                    'adultPlasticity': <String, int>{
                      'initiative': 0,
                      'contact': 0,
                      'tempo': 0,
                    },
                  });
        }
      }
    });
    return ElevageSave(normalized);
  }

  ElevageSave copy() => ElevageSave(_clone(data));
  Map<String, dynamic> toJson() => _clone(data);
  String encode() => jsonEncode(toJson());
}

class ElevageSceneItemOutcome {
  const ElevageSceneItemOutcome({
    required this.behavior,
    required this.observationCount,
    this.targetZoneId,
    this.consumed = false,
  });

  final String behavior;
  final int observationCount;
  final String? targetZoneId;
  final bool consumed;
}

/// Choix pur du prochain objet à examiner. La scène anime les étapes, puis
/// appelle `interactSceneItem` une seule fois pour la mutation réelle.
class ElevageAutonomousSceneDecision {
  const ElevageAutonomousSceneDecision({
    required this.instanceId,
    required this.zoneId,
    required this.outcome,
  });

  final String instanceId;
  final String zoneId;
  final ElevageSceneItemOutcome outcome;
}

Map<String, dynamic> _clone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

class ElevageDomain {
  static const List<String> foodItems = <String>[
    'ROOT',
    'LEAF',
    'MOSS',
    'ALGAE',
    'MUSHROOM',
  ];
  static const List<String> treatItems = <String>[
    'FIBROUS_FRUIT',
    'FRUIT_JELLY',
  ];
  static const List<String> structuralItems = <String>[
    'IRON',
    'LIMESTONE',
    'QUARTZ',
  ];

  /// Tout le loot spécifique actuellement atteignable dans la Mini-Lisière.
  /// Cette liste sert aussi de garde-fou QA pour éviter le fallback joueur
  /// « Objet inconnu ».
  static const List<String> foragingLootItemIds = <String>[
    'ROOT',
    'LEAF',
    'FRUIT',
    'SEED',
    'SPROUT',
    'MOSS',
    'MUSHROOM',
    'ALGAE',
    'ALGAE_FRAGMENT',
    'LIMESTONE',
    'QUARTZ',
    'IRON',
  ];
  static const Set<String> _placeableSceneItems = <String>{
    'ROOT',
    'LEAF',
    'MOSS',
    'ALGAE',
    'MUSHROOM',
    'FIBROUS_FRUIT',
    'FRUIT_JELLY',
    'IRON',
    'LIMESTONE',
    'QUARTZ',
  };

  /// Répartition provisoire commune V0 : elle est volontairement centralisée
  /// ici pour que chaque axe puisse recevoir sa propre pondération plus tard.
  /// Voir aussi la Data Card : ce n'est pas encore une règle canonique.
  static Map<String, double> personalityWeights(ElevageConfig config) =>
      <String, double>{
        'baseline': config.personalityBaselineWeight,
        'baby': config.personalityBabyWeight,
        'intermediate': config.personalityIntermediateWeight,
        'adultPlasticity': config.personalityAdultPlasticityWeight,
      };

  /// Valeur 0–1 lisible par le comportement, sans exposer le nombre au joueur.
  static double personalityValue(Map individual, String axis) {
    final personality = individual['personality'] as Map;
    final baseline = ((personality['baseline'] as Map)[axis] as num).toDouble();
    final tendencies =
        ((personality['tendencies'] as Map)[axis] as num?)?.toDouble() ?? 0;
    return ((baseline + tendencies) / 100).clamp(0.0, 1.0);
  }

  static double wellbeing(Map individual) =>
      (((individual['wellbeing'] as Map?)?['value'] as num?)?.toDouble() ?? 60)
          .clamp(0, 100);

  static int normalMoveDurationFor(Map individual, ElevageConfig config) {
    final tempo = personalityValue(individual, 'tempo');
    // Posé (>= .5) : 0.85× ; spontané (< .5) : 1.15×.
    final factor = tempo >= .5 ? .85 : 1.15;
    return (config.normalMoveDurationMs * factor).round();
  }

  static int idlePauseFor(Map individual, ElevageConfig config) {
    final tempo = personalityValue(individual, 'tempo');
    final factor = tempo >= .5 ? 1.25 : .75;
    return max(1, (config.idlePauseSeconds * factor).round());
  }

  static int evidenceForInspection(Map individual) =>
      personalityValue(individual, 'tempo') >= .5 ? 2 : 1;

  static String circadianProfile(Map individual) =>
      switch (individual['family']) {
        'VEGETAL' => 'DIURNAL',
        'FUNGAL' => 'BIPHASIC',
        _ => 'SHIFTED_DIURNAL',
      };

  /// Les fenêtres peuvent être multiples : le profil fongique est biphasique.
  /// Chaque couple est exprimé en fraction du cycle complet [0–1].
  static List<List<double>> sleepWindows(Map individual) =>
      switch (circadianProfile(individual)) {
        'DIURNAL' => const <List<double>>[
            <double>[.667, 1],
          ],
        'BIPHASIC' => const <List<double>>[
            <double>[.34, .48],
            <double>[.61, .74],
          ],
        _ => const <List<double>>[
            <double>[0, .25],
            <double>[.84, 1],
          ],
      };

  static bool isSleeping(Map individual, int now, ElevageConfig config) {
    final cycleMs =
        config.dayNightCycleHours * const Duration(hours: 1).inMilliseconds;
    final position = (now % cycleMs) / cycleMs;
    return sleepWindows(individual)
        .any((window) => position >= window[0] && position < window[1]);
  }

  static String sleepZone(
      ElevageSave state, String individualId, int now, ElevageConfig config,
      {String? phaseOverride}) {
    final individual = _individual(state, individualId);
    return bestComfortZone(state, individual['alcoveId'] as String, config, now,
        phaseOverride: phaseOverride);
  }

  static ElevageSave adopt({
    required ElevageSave source,
    required String alcoveId,
    required String name,
    required bool physical,
    required int now,
    required ElevageConfig config,
    String? physicalFigureRef,
  }) {
    final state = source.copy();
    final alcove = _alcove(state, alcoveId);
    if (alcove['occupantIndividualId'] != null) {
      throw StateError('Cette Alcôve est déjà occupée.');
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 32) {
      throw StateError('Choisissez un nom entre 1 et 32 caractères.');
    }
    final ref = physicalFigureRef ?? '';
    if (physical && (ref.isEmpty || _physicalAlreadyLinked(state, ref))) {
      throw StateError('Cette figurine est déjà liée à un P’TIPOTE actif.');
    }
    final seed =
        '${now}_${state.data['individuals'].length}_${cleanName.hashCode}';
    final random = Random(_hash(seed));
    final id = 'elevage-$now-${random.nextInt(99999)}';
    final favorite = random.nextBool() ? 'ROOT' : 'LEAF';
    final individual = <String, dynamic>{
      'id': id,
      'name': cleanName,
      'family': 'MINERAL',
      'nature': 'RESONANCE',
      'individualSeed': seed,
      'seedAlgorithmVersion': 1,
      'ownership': physical
          ? <String, dynamic>{'mode': 'PHYSICAL', 'physicalFigureRef': ref}
          : <String, dynamic>{
              'mode': 'CO_REARING',
              'startedAt': now,
              'expiresAt': now +
                  config.coRearingDurationHours *
                      const Duration(hours: 1).inMilliseconds,
              'sourcePoolId': 'MINERAL_RESONANCE',
              'returnProcessedAt': null,
            },
      'lifecycle': <String, dynamic>{'stage': 'BABY', 'stageEnteredAt': now},
      'generatedProfile': <String, dynamic>{
        'foodPreference': favorite,
        'environmentalVariation': <String, int>{
          'light': random.nextInt(3) - 1,
          'temperature': random.nextInt(3) - 1,
          'humidity': random.nextInt(3) - 1,
        },
        'behaviorTendencies': <String, int>{'curiosity': random.nextInt(3) - 1},
      },
      'personality': <String, dynamic>{
        'baseline': <String, int>{
          'initiative': 45 + random.nextInt(11),
          'contact': 45 + random.nextInt(11),
          'tempo': 45 + random.nextInt(11),
        },
        'tendencies': <String, int>{'initiative': 0, 'contact': 0, 'tempo': 0},
        'development': <String, dynamic>{
          'babyExperience': <String, int>{
            'initiative': 0,
            'contact': 0,
            'tempo': 0,
          },
          'intermediateExperience': <String, int>{
            'initiative': 0,
            'contact': 0,
            'tempo': 0,
          },
          'adultPlasticity': <String, int>{
            'initiative': 0,
            'contact': 0,
            'tempo': 0,
          },
        },
      },
      'wellbeing': <String, dynamic>{'value': 60, 'lastUpdatedAt': now},
      'activeRequest': null,
      'social': <String, dynamic>{
        'cuddleCooldownUntil': 0,
        'cuddleAttempts': 0,
        'lastReaction': 'NEUTRAL',
      },
      'care': <String, dynamic>{
        'lastMealAt': null,
        'metabolicMeals': 0,
        'structuralIntake': <String, dynamic>{
          'total': 0,
          'byMaterial': <String, int>{'IRON': 0, 'LIMESTONE': 0},
        },
        'autonomousMealCount': 0,
      },
      'preferenceDiscovery': <String, dynamic>{
        'foodPreference': <String, dynamic>{'status': 'UNKNOWN', 'evidence': 0},
      },
      'observationJournal': <String, dynamic>{
        'observations': <String, dynamic>{},
      },
      'progressionEvidence': <String, dynamic>{
        'interactionTypes': <String>[],
        'foragingCount': 0,
        'environmentExperiments': 0,
        'personalityEvents': 0,
        'stageSnapshot': <String, dynamic>{},
      },
      'alcoveId': alcoveId,
      'createdAt': now,
      'adoptedAt': now,
    };
    (state.data['individuals'] as Map<String, dynamic>)[id] = individual;
    (state.data['activeIndividualIds'] as List).add(id);
    alcove['occupantIndividualId'] = id;
    _memory(state, id, 'ADOPTED', now);
    return state;
  }

  static ElevageSave resetGame(ElevageConfig config, int now) =>
      ElevageSave.initial(config, now: now);

  /// Keeps the player configuration and portable inventory, while removing all
  /// Alcôve-bound state that could contaminate a spatial QA run.
  static ElevageSave resetAlcoves(
      ElevageSave source, ElevageConfig config, int now) {
    final state = source.copy();
    state.data['alcoves'] = List<Map<String, dynamic>>.generate(
        config.alcoveCount,
        (index) => <String, dynamic>{
              'id': 'alcove-${index + 1}',
              'slotLimit': config.installationSlotCount,
              'occupantIndividualId': null,
              'slots': List<dynamic>.filled(config.installationSlotCount, null),
              'createdAt': now,
            });
    state.data['individuals'] = <String, dynamic>{};
    state.data['activeIndividualIds'] = <String>[];
    state.data['installationInventory'] = <String, dynamic>{};
    state.data['sceneItemsByAlcoveId'] = <String, dynamic>{};
    state.data['runsByIndividualId'] = <String, dynamic>{};
    state.data['memoryEvents'] = <String, dynamic>{};
    state.data['coRearingReturnLedger'] = <String, dynamic>{};
    state.data['pendingNotifications'] = <dynamic>[];
    return state;
  }

  static ElevageSave offerFood(ElevageSave source, String id, String item,
      int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, id);
    final special = _special(state);
    if ((special[item] ?? 0) < 1) throw StateError('Objet non disponible.');
    final favorite = individual['generatedProfile']['foodPreference'] as String;
    if (treatItems.contains(item)) {
      special[item] = special[item]! - 1;
      _memory(state, id, 'FIRST_TREAT', now);
      _interaction(individual, 'TREAT', contact: 1);
      _adjustWellbeing(individual, 2, now);
      return state;
    }
    if (!foodItems.contains(item)) {
      throw StateError('Cet objet ne nourrit pas Résonance.');
    }
    if (!canOfferNormalFood(state, id, now, config)) {
      throw StateError('P’TIPOTE n’a pas faim.');
    }
    special[item] = special[item]! - 1;
    final care = individual['care'] as Map<String, dynamic>;
    care['lastMealAt'] = now;
    care['metabolicMeals'] = (care['metabolicMeals'] as int) + 1;
    individual['activeRequest'] = null;
    if (item == favorite) {
      final discovery = individual['preferenceDiscovery']['foodPreference']
          as Map<String, dynamic>;
      discovery['evidence'] = (discovery['evidence'] as int) + 1;
      final evidence = discovery['evidence'] as int;
      discovery['status'] = evidence >= config.confirmedThreshold
          ? 'CONFIRMED'
          : evidence >= config.suspectedThreshold
              ? 'SUSPECTED'
              : 'UNKNOWN';
      _memory(state, id, 'FIRST_FAVORITE_FOOD', now);
      _interaction(individual, 'FAVORITE_FOOD', contact: 1);
      _adjustWellbeing(individual,
          personalityValue(individual, 'initiative') < .5 ? 3 : 1, now);
      final count = _observe(individual, 'FOOD_FAVORITE', now,
          relatedItemId: item, config: config);
      _setObservationStatus(
          individual, 'FOOD_FAVORITE:$item', count, config, now);
    } else {
      _interaction(individual, 'FOOD', contact: 1);
      _adjustWellbeing(individual, 1, now);
      final count = _observe(individual, 'FOOD_ACCEPTED', now,
          relatedItemId: item, config: config);
      _setObservationStatus(
          individual, 'FOOD_ACCEPTED:$item', count, config, now);
    }
    _memory(state, id, 'FIRST_FOOD', now);
    return state;
  }

  static ElevageSave offerStructural(
      ElevageSave source, String id, String item, int now,
      [ElevageConfig? config]) {
    final state = source.copy();
    final individual = _individual(state, id);
    final gains = <String, int>{'IRON': 2, 'LIMESTONE': 1, 'QUARTZ': 0};
    final gain = gains[item];
    if (gain == null) throw StateError('Matériau inconnu.');
    final special = _special(state);
    if ((special[item] ?? 0) < 1) throw StateError('Matériau non disponible.');
    if (gain == 0) {
      final count = _observe(individual, 'STRUCTURAL_AVOIDED', now,
          relatedItemId: item, config: config ?? defaultElevageConfig);
      _setObservationStatus(individual, 'STRUCTURAL_AVOIDED:$item', count,
          config ?? defaultElevageConfig, now);
      return state;
    }
    special[item] = special[item]! - 1;
    final intake =
        individual['care']['structuralIntake'] as Map<String, dynamic>;
    intake['total'] = (intake['total'] as int) + gain;
    final byMaterial = intake['byMaterial'] as Map<String, dynamic>;
    byMaterial[item] = (byMaterial[item] as int? ?? 0) + gain;
    _interaction(individual, 'STRUCTURE', tempo: 1);
    individual['activeRequest'] = null;
    _adjustWellbeing(individual, 1, now);
    final count = _observe(individual, 'STRUCTURAL_REACTION', now,
        relatedItemId: item, config: config ?? defaultElevageConfig);
    _setObservationStatus(individual, 'STRUCTURAL_REACTION:$item', count,
        config ?? defaultElevageConfig, now);
    return state;
  }

  static ElevageSave addDevInventory(ElevageSave source) {
    final state = source.copy();
    final special = _special(state);
    for (final item in <String>[
      ...foodItems,
      ...treatItems,
      ...structuralItems,
      'SEED',
      'SPROUT',
      'ALGAE_FRAGMENT'
    ]) {
      special[item] = (special[item] ?? 0) + 3;
    }
    final generic = _generic(state);
    generic['organic'] = (generic['organic'] ?? 0) + 30;
    generic['mineral'] = (generic['mineral'] ?? 0) + 30;
    state.data['inventory']['bioPiles'] =
        (state.data['inventory']['bioPiles'] as int) + 10;
    return state;
  }

  static String hunger(
      ElevageSave state, String id, int now, ElevageConfig config) {
    final lastMeal = _individual(state, id)['care']['lastMealAt'] as int?;
    if (lastMeal == null) return 'SATIATED';
    final hours = (now - lastMeal) / const Duration(hours: 1).inMilliseconds;
    final speed = _hungerSpeed(state, id, config);
    if (hours >= config.hungerVeryHungryHours / speed) return 'VERY_HUNGRY';
    if (hours >= config.hungerHungryHours / speed) return 'HUNGRY';
    if (hours >= config.hungerNormalHours / speed) return 'NORMAL';
    return 'SATIATED';
  }

  static int satietyPercent(
      ElevageSave state, String id, int now, ElevageConfig config) {
    final lastMeal = _individual(state, id)['care']['lastMealAt'] as int?;
    if (lastMeal == null) return 100;
    final elapsed = max(0, now - lastMeal);
    final span = config.hungerVeryHungryHours /
        _hungerSpeed(state, id, config) *
        const Duration(hours: 1).inMilliseconds;
    return (100 - elapsed * 100 / span).round().clamp(0, 100);
  }

  /// Prototype accéléré pour que la boucle faim → objet posé → décision soit
  /// observable en playtest ; TARGET conserve les durées de design lentes.
  static double _hungerSpeed(
      ElevageSave state, String id, ElevageConfig config) {
    final stage = _individual(state, id)['lifecycle']['stage'] as String;
    if (config.preset == ElevagePreset.prototype) {
      return switch (stage) { 'BABY' => 5, 'INTERMEDIATE' => 3, _ => 1 };
    }
    // TARGET conserve les seuils historiques : aucun accélérateur de
    // playtest ne doit modifier son rythme dérivé.
    return 1;
  }

  static bool canOfferNormalFood(
      ElevageSave state, String id, int now, ElevageConfig config) {
    final lastMeal = _individual(state, id)['care']['lastMealAt'] as int?;
    return lastMeal == null || satietyPercent(state, id, now, config) < 95;
  }

  static List<Map<String, dynamic>> sceneItems(
      ElevageSave state, String alcoveId) {
    final all = state.data['sceneItemsByAlcoveId'] as Map;
    final raw = all[alcoveId] as List? ?? const <dynamic>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// Moves a compatible item out of the player inventory and into one physical
  /// zone of an Alcôve. A zone holds at most one item in the V0 prototype.
  static ElevageSave placeSceneItem(ElevageSave source, String alcoveId,
      String item, String zoneId, int now, ElevageConfig config) {
    if (!_placeableSceneItems.contains(item)) {
      throw StateError('Cet objet ne peut pas être posé dans l’Alcôve.');
    }
    if (config.sceneZone(zoneId) == null) throw StateError('Zone invalide.');
    final state = source.copy();
    _alcove(state, alcoveId);
    final special = _special(state);
    if ((special[item] ?? 0) < 1) throw StateError('Objet non disponible.');
    final placed = _sceneItems(state, alcoveId);
    if (placed.any((entry) => entry['zoneId'] == zoneId)) {
      throw StateError('Cette zone contient déjà un objet.');
    }
    special[item] = special[item]! - 1;
    placed.add(<String, dynamic>{
      'instanceId': 'scene-$now-${placed.length}-$item',
      'itemId': item,
      'zoneId': zoneId,
      'placedAt': now,
      'source': 'PLAYER',
      'interactionCount': 0,
    });
    return state;
  }

  static ElevageSave recoverSceneItem(
      ElevageSave source, String alcoveId, String instanceId) {
    final state = source.copy();
    final placed = _sceneItems(state, alcoveId);
    final index =
        placed.indexWhere((entry) => entry['instanceId'] == instanceId);
    if (index < 0) throw StateError('Objet posé introuvable.');
    final item = placed.removeAt(index)['itemId'] as String;
    final special = _special(state);
    special[item] = (special[item] ?? 0) + 1;
    return state;
  }

  /// Evaluates only facts already present in the domain: item, hunger and the
  /// relative environment of its zone. No preference is revealed by this API.
  static ElevageSceneItemOutcome sceneItemOutcome(
      ElevageSave state,
      String individualId,
      String alcoveId,
      String instanceId,
      int now,
      ElevageConfig config,
      {String? phaseOverride}) {
    final placed = _sceneItems(state, alcoveId);
    final item =
        placed.where((entry) => entry['instanceId'] == instanceId).firstOrNull;
    if (item == null) throw StateError('Objet posé introuvable.');
    final individual = _individual(state, individualId);
    final itemId = item['itemId'] as String;
    final effective = zoneEnvironment(
        state, alcoveId, item['zoneId'] as String, config,
        now: now, phaseOverride: phaseOverride);
    final favorite = individual['generatedProfile']['foodPreference'] as String;

    if (foodItems.contains(itemId) &&
        itemId == favorite &&
        (effective['humidity'] ?? 0) >= 2) {
      final target = _drierSceneZone(
          state, alcoveId, item['zoneId'] as String, config, now,
          phaseOverride: phaseOverride);
      if (target != null) {
        return ElevageSceneItemOutcome(
          behavior: 'MOVE_ITEM',
          targetZoneId: target,
          observationCount:
              _observationCount(individual, 'HUMIDITY_AVOIDANCE:ROOT') + 1,
        );
      }
    }
    if (itemId == 'QUARTZ') {
      return ElevageSceneItemOutcome(
          behavior: 'STEP_BACK',
          observationCount:
              _observationCount(individual, 'STRUCTURAL_AVOIDED:QUARTZ') + 1);
    }
    if (treatItems.contains(itemId)) {
      return const ElevageSceneItemOutcome(
          behavior: 'RUSH_SHAKE', observationCount: 0, consumed: true);
    }
    if (foodItems.contains(itemId)) {
      if (!canOfferNormalFood(state, individualId, now, config)) {
        return const ElevageSceneItemOutcome(
            behavior: 'OBSERVE', observationCount: 0);
      }
      return ElevageSceneItemOutcome(
        behavior: itemId == favorite ? 'RUSH_SHAKE' : 'APPROACH',
        observationCount: _observationCount(individual,
                '${itemId == favorite ? 'FOOD_FAVORITE' : 'FOOD_ACCEPTED'}:$itemId') +
            1,
        consumed: true,
      );
    }
    if (itemId == 'IRON' || itemId == 'LIMESTONE') {
      return ElevageSceneItemOutcome(
        behavior: itemId == 'IRON' ? 'VIBRATE' : 'APPROACH',
        observationCount:
            _observationCount(individual, 'STRUCTURAL_REACTION:$itemId') + 1,
        consumed: true,
      );
    }
    return const ElevageSceneItemOutcome(
        behavior: 'OBSERVE', observationCount: 0);
  }

  static ElevageAutonomousSceneDecision? nextAutonomousSceneDecision(
      ElevageSave state,
      String individualId,
      String alcoveId,
      int now,
      ElevageConfig config,
      {String? lastBehavior,
      String? phaseOverride}) {
    for (final item in _sceneItems(state, alcoveId)) {
      final outcome = sceneItemOutcome(state, individualId, alcoveId,
          item['instanceId'] as String, now, config,
          phaseOverride: phaseOverride);
      if (lastBehavior != null && outcome.behavior == lastBehavior) continue;
      return ElevageAutonomousSceneDecision(
        instanceId: item['instanceId'] as String,
        zoneId: item['zoneId'] as String,
        outcome: outcome,
      );
    }
    return null;
  }

  static ElevageSave interactSceneItem(ElevageSave source, String individualId,
      String alcoveId, String instanceId, int now, ElevageConfig config,
      {String? phaseOverride}) {
    final outcome = sceneItemOutcome(
        source, individualId, alcoveId, instanceId, now, config,
        phaseOverride: phaseOverride);
    final state = source.copy();
    final placed = _sceneItems(state, alcoveId);
    final index =
        placed.indexWhere((entry) => entry['instanceId'] == instanceId);
    if (index < 0) throw StateError('Objet posé introuvable.');
    final entry = placed[index];
    final item = entry['itemId'] as String;
    entry['interactionCount'] =
        ((entry['interactionCount'] as num?)?.toInt() ?? 0) + 1;
    final individual = _individual(state, individualId);

    if (outcome.behavior == 'MOVE_ITEM') {
      entry['zoneId'] = outcome.targetZoneId;
      final count = _observe(individual, 'HUMIDITY_AVOIDANCE', now,
          relatedEnvironmentAxis: 'HUMIDITY', config: config);
      _setObservationStatus(
          individual, 'HUMIDITY_AVOIDANCE:HUMIDITY', count, config, now);
      return state;
    }
    if (outcome.behavior == 'STEP_BACK' && item == 'QUARTZ') {
      final count = _observe(individual, 'STRUCTURAL_AVOIDED', now,
          relatedItemId: item, config: config);
      _setObservationStatus(
          individual, 'STRUCTURAL_AVOIDED:$item', count, config, now);
      return state;
    }
    if (!outcome.consumed) return state;

    // Reuse the existing nutrition/structure rules without making scene items
    // coexist with the player inventory: a transient unit is consumed by the
    // same atomic domain operation, then the placed instance is removed.
    final special = _special(state);
    special[item] = (special[item] ?? 0) + 1;
    final consumed = structuralItems.contains(item)
        ? offerStructural(state, individualId, item, now, config)
        : offerFood(state, individualId, item, now, config);
    final consumedItems = _sceneItems(consumed, alcoveId);
    consumedItems
        .removeWhere((sceneItem) => sceneItem['instanceId'] == instanceId);
    return consumed;
  }

  static Map<String, int> zoneEnvironment(
      ElevageSave state, String alcoveId, String zoneId, ElevageConfig config,
      {int? now, String? phaseOverride}) {
    final zone = config.sceneZone(zoneId);
    if (zone == null) throw StateError('Zone invalide.');
    final phase = phaseOverride ??
        dayNightPhase(now ?? DateTime.now().millisecondsSinceEpoch, config);
    final nightOffset = phase == 'NIGHT' ? config.nightLightOffset(zoneId) : 0;
    final result = <String, int>{
      'light': zone.light + nightOffset,
      'temperature': zone.temperature,
      'humidity': zone.humidity,
    };
    final slots = _alcove(state, alcoveId)['slots'] as List;
    for (var index = 0; index < slots.length; index++) {
      final raw = slots[index];
      if (raw is! Map) continue;
      // Les anciennes sauvegardes n'avaient pas encore la position spatiale
      // des installations : leur slot reste une position de repli stable.
      final installedZone = raw['zoneId'] as String? ?? 'ZONE_${index + 1}';
      if (installedZone != zoneId) continue;
      final definition = config.installation(raw['definitionId'] as String);
      if (definition == null) continue;
      result['light'] = result['light']! + definition.light;
      result['temperature'] = result['temperature']! + definition.temperature;
      result['humidity'] = result['humidity']! + definition.humidity;
    }
    return result;
  }

  /// HUD global : moyenne des quatre micro-environnements, jamais la zone
  /// actuelle du P’TIPOTE. Les décisions biologiques restent locales.
  static Map<String, int> averageZoneEnvironment(
      ElevageSave state, String alcoveId, ElevageConfig config,
      {required int now, String? phaseOverride}) {
    final result = <String, int>{};
    for (final axis in <String>['light', 'temperature', 'humidity']) {
      final total = config.sceneZones.fold<int>(
          0,
          (sum, zone) =>
              sum +
              zoneEnvironment(state, alcoveId, zone.id, config,
                  now: now, phaseOverride: phaseOverride)[axis]!);
      result[axis] = (total / config.sceneZones.length).round();
    }
    return result;
  }

  /// V0 Résonance : le confort provient de la zone locale. Il prépare les
  /// observations sans devenir une seconde source de préférence persistée.
  static String localComfort(
      Map<String, int> environment, ElevageConfig config) {
    const severity = <String, int>{
      'IDEAL': 0,
      'GOOD': 1,
      'NEUTRAL': 2,
      'BAD': 3,
      'EXTREME': 4,
    };
    final axes = <String>['light', 'temperature', 'humidity']
        .map((axis) => config.resonanceAxisComfort(
            axis, ((environment[axis] ?? 0) + 3).clamp(1, 5)))
        .toList()
      ..sort((left, right) => severity[right]!.compareTo(severity[left]!));
    // Le pire axe l’emporte : aucun extrême ne peut être masqué par une
    // moyenne favorable sur les deux autres axes.
    return axes.first;
  }

  static String bestComfortZone(
      ElevageSave state, String alcoveId, ElevageConfig config, int now,
      {String? phaseOverride, String? excludingZoneId}) {
    const severity = <String, int>{
      'IDEAL': 0,
      'GOOD': 1,
      'NEUTRAL': 2,
      'BAD': 3,
      'EXTREME': 4,
    };
    final zones =
        config.sceneZones.where((zone) => zone.id != excludingZoneId).toList()
          ..sort((left, right) {
            final leftComfort = localComfort(
                zoneEnvironment(state, alcoveId, left.id, config,
                    now: now, phaseOverride: phaseOverride),
                config);
            final rightComfort = localComfort(
                zoneEnvironment(state, alcoveId, right.id, config,
                    now: now, phaseOverride: phaseOverride),
                config);
            return severity[leftComfort]!.compareTo(severity[rightComfort]!);
          });
    return zones.first.id;
  }

  static String dayNightPhase(int now, ElevageConfig config) {
    final dayMs =
        config.dayDurationHours * const Duration(hours: 1).inMilliseconds;
    final cycleMs =
        config.dayNightCycleHours * const Duration(hours: 1).inMilliseconds;
    return now % cycleMs < dayMs ? 'DAY' : 'NIGHT';
  }

  static int dayNightRemainingMs(int now, ElevageConfig config,
      {String? phaseOverride}) {
    final phase = phaseOverride ?? dayNightPhase(now, config);
    if (phaseOverride != null) {
      return (phase == 'DAY'
              ? config.dayDurationHours
              : config.nightDurationHours) *
          const Duration(hours: 1).inMilliseconds;
    }
    final dayMs =
        config.dayDurationHours * const Duration(hours: 1).inMilliseconds;
    final cycleMs =
        config.dayNightCycleHours * const Duration(hours: 1).inMilliseconds;
    final position = now % cycleMs;
    return phase == 'DAY' ? dayMs - position : cycleMs - position;
  }

  static ElevageSave observeShade(
      ElevageSave source, String id, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, id);
    final count = _observe(individual, 'LIGHT_SHADE', now,
        relatedEnvironmentAxis: 'LIGHT', config: config);
    _setObservationStatus(individual, 'LIGHT_SHADE:LIGHT', count, config, now);
    return state;
  }

  static ElevageSave follow(ElevageSave source, String id, String zoneId,
      int now, ElevageConfig config) {
    final state = source.copy();
    if (config.sceneZone(zoneId) == null) throw StateError('Zone invalide.');
    final individual = _individual(state, id);
    _interaction(individual, 'FOLLOW', contact: 1);
    final count = _observe(individual, 'FOLLOW', now, config: config);
    _setObservationStatus(individual, 'FOLLOW:GENERAL', count, config, now);
    return state;
  }

  static ElevageSave cuddle(
      ElevageSave source, String id, int now, ElevageConfig config,
      {int durationMs = 1000}) {
    final state = source.copy();
    final individual = _individual(state, id);
    final boundedDuration = durationMs.clamp(1000, 5000);
    final social = individual['social'] as Map<String, dynamic>;
    final contact = personalityValue(individual, 'contact');
    final cooldownUntil = (social['cuddleCooldownUntil'] as num?)?.toInt() ?? 0;
    if (now < cooldownUntil) {
      final attempts = ((social['cuddleAttempts'] as num?)?.toInt() ?? 0) + 1;
      social['cuddleAttempts'] = attempts;
      social['lastReaction'] = attempts >= 2 ? 'IRRITATED' : 'NEUTRAL';
      _adjustWellbeing(individual, attempts >= 2 ? -5 : -1, now);
      final count = _observe(individual, 'CUDDLE_SPACE', now, config: config);
      _setObservationStatus(
          individual, 'CUDDLE_SPACE:GENERAL', count, config, now);
      return state;
    }
    (individual['progressionEvidence'] as Map)['lastCuddleDurationMs'] =
        boundedDuration;
    social['cuddleAttempts'] = 0;
    final prolonged = boundedDuration >= 4000;
    final prefersLong = contact >= .55;
    social['lastReaction'] = prolonged && !prefersLong ? 'RESERVED' : 'CONTENT';
    social['cuddleCooldownUntil'] = now +
        (contact >= .55
                ? config.warmCuddleCooldownSeconds
                : config.reservedCuddleCooldownSeconds) *
            1000;
    _interaction(individual, 'CUDDLE',
        contact: prolonged && prefersLong ? 1 : 0);
    _adjustWellbeing(individual, prolonged == prefersLong ? 3 : 1, now);
    final count = _observe(individual, 'CUDDLE', now, config: config);
    _setObservationStatus(individual, 'CUDDLE:GENERAL', count, config, now);
    return state;
  }

  static ElevageSave startForaging(ElevageSave source, String id, String biome,
      int now, ElevageConfig config) {
    final state = source.copy();
    final runs = state.data['runsByIndividualId'] as Map<String, dynamic>;
    final previous = runs[id] as Map?;
    if (previous != null &&
        _runStatus(Map<String, dynamic>.from(previous), now) != 'COMPLETED') {
      throw StateError('Ce P’TIPOTE a déjà une sortie en cours.');
    }
    const allowed = <String>['FOREST', 'COAST', 'HILL'];
    if (!allowed.contains(biome)) throw StateError('Biome inconnu.');
    final seed = '${id}_${now}_$biome';
    runs[id] = <String, dynamic>{
      'id': 'run-$now',
      'individualId': id,
      'biomeId': biome,
      'startedAt': now,
      'readyAt': now + config.foragingDurationSeconds * 1000,
      'seed': seed,
      'points': _foragingPoints(biome, seed),
      'selectedPointId': null,
      'rewardClaimedAt': null,
    };
    final progress =
        _individual(state, id)['progressionEvidence'] as Map<String, dynamic>;
    progress['foragingCount'] = (progress['foragingCount'] as int) + 1;
    _interaction(_individual(state, id), 'FORAGING', initiative: 1, tempo: -1);
    return state;
  }

  static String foragingStatus(ElevageSave state, String id, int now) {
    final run = (state.data['runsByIndividualId'] as Map<String, dynamic>)[id];
    return run is Map
        ? _runStatus(Map<String, dynamic>.from(run), now)
        : 'NONE';
  }

  static ElevageSave claimForaging(
      ElevageSave source, String id, String pointId, int now) {
    final state = source.copy();
    final run = (state.data['runsByIndividualId'] as Map<String, dynamic>)[id];
    if (run is! Map ||
        _runStatus(Map<String, dynamic>.from(run), now) != 'READY') {
      throw StateError('La sortie n’est pas prête.');
    }
    if (run['selectedPointId'] != null || run['rewardClaimedAt'] != null) {
      throw StateError('La récompense a déjà été attribuée.');
    }
    final point = (run['points'] as List)
        .cast<Map>()
        .where((item) => item['id'] == pointId)
        .cast<Map?>()
        .firstOrNull;
    if (point == null) throw StateError('Point d’intérêt invalide.');
    final reward = point['reward'] as Map;
    final generic = reward['generic'] as Map;
    final inventoryGeneric = _generic(state);
    generic.forEach((key, value) {
      final inventoryKey = key.toLowerCase();
      inventoryGeneric[inventoryKey] =
          (inventoryGeneric[inventoryKey] ?? 0) + (value as num).toInt();
    });
    final specialId = reward['special'] as String;
    final inventorySpecial = _special(state);
    inventorySpecial[specialId] = (inventorySpecial[specialId] ?? 0) + 1;
    final discovered = state.data['discoveredItemIds'] as List;
    if (!discovered.contains(specialId)) discovered.add(specialId);
    run['selectedPointId'] = pointId;
    run['rewardClaimedAt'] = now;
    return state;
  }

  static bool recipeKnown(ElevageSave state, ElevageRecipe recipe) =>
      recipe.isBase ||
      recipe.unlockItems.every(
          (item) => (state.data['discoveredItemIds'] as List).contains(item));

  static ElevageSave craft(
      ElevageSave source, ElevageRecipe recipe, int now, ElevageConfig config) {
    final state = source.copy();
    if (!recipeKnown(state, recipe)) throw StateError('Recette inconnue.');
    final generic = _generic(state);
    final special = _special(state);
    if ((generic['organic'] ?? 0) < recipe.organic ||
        (generic['mineral'] ?? 0) < recipe.mineral ||
        recipe.special.entries
            .any((entry) => (special[entry.key] ?? 0) < entry.value)) {
      throw StateError('Ressources insuffisantes.');
    }
    generic['organic'] = generic['organic']! - recipe.organic;
    generic['mineral'] = generic['mineral']! - recipe.mineral;
    recipe.special
        .forEach((item, amount) => special[item] = special[item]! - amount);
    final instanceId = 'installation-$now-${recipe.id}';
    (state.data['installationInventory'] as Map<String, dynamic>)[instanceId] =
        <String, dynamic>{
      'instanceId': instanceId,
      'definitionId': recipe.installationId,
      'acquisitionMode': 'CRAFTED',
      'craftedAt': now,
      'paidCost': <String, dynamic>{
        'organic': recipe.organic,
        'mineral': recipe.mineral,
        'specialComponents': recipe.special
      },
      'sourceConfigRevision': config.revision,
      'productionState': <String, dynamic>{
        'lastResolvedAt': now,
        'availableByItemId': <String, int>{}
      },
    };
    return state;
  }

  static ElevageSave place(ElevageSave source, String alcoveId, int slot,
      String instanceId, int now) {
    final state = source.copy();
    final alcove = _alcove(state, alcoveId);
    final slots = alcove['slots'] as List;
    if (slot < 0 || slot >= slots.length) {
      throw StateError('Emplacement invalide.');
    }
    final inventory =
        state.data['installationInventory'] as Map<String, dynamic>;
    final instance = inventory.remove(instanceId);
    if (instance == null) throw StateError('Installation non disponible.');
    if (slots[slot] != null) {
      inventory[(slots[slot] as Map)['instanceId'] as String] = slots[slot];
    }
    (instance as Map)['installedAt'] = now;
    instance['zoneId'] = 'ZONE_${slot + 1}';
    slots[slot] = instance;
    return state;
  }

  static ElevageSave remove(ElevageSave source, String alcoveId, int slot) {
    final state = source.copy();
    final slots = _alcove(state, alcoveId)['slots'] as List;
    final instance = slots[slot];
    if (instance == null) return state;
    (state.data['installationInventory'] as Map<String, dynamic>)[
        (instance as Map)['instanceId'] as String] = instance;
    slots[slot] = null;
    return state;
  }

  static Map<String, int> environment(
      ElevageSave state, String alcoveId, ElevageConfig config) {
    final result = <String, int>{'light': 0, 'temperature': 0, 'humidity': 0};
    for (final raw in _alcove(state, alcoveId)['slots'] as List) {
      if (raw is! Map) continue;
      final definition = config.installation(raw['definitionId'] as String);
      if (definition == null) continue;
      result['light'] = result['light']! + definition.light;
      result['temperature'] = result['temperature']! + definition.temperature;
      result['humidity'] = result['humidity']! + definition.humidity;
    }
    return result;
  }

  static ElevageSave refreshAlcove(
      ElevageSave source, String alcoveId, int now, ElevageConfig config) {
    final state = source.copy();
    final alcove = _alcove(state, alcoveId);
    for (final raw in alcove['slots'] as List) {
      if (raw is! Map) continue;
      final definition = config.installation(raw['definitionId'] as String);
      if (definition == null || !definition.productive) continue;
      final production = raw.putIfAbsent(
          'productionState',
          () => <String, dynamic>{
                'lastResolvedAt': now,
                'availableByItemId': <String, int>{}
              }) as Map;
      final last = production['lastResolvedAt'] as int? ?? now;
      final cycles =
          max(0, (now - last) ~/ (config.productionIntervalSeconds * 1000));
      if (cycles > 0) {
        final stock = production['availableByItemId'] as Map;
        definition.outputs.forEach((item, quantity) {
          final current = (stock[item] as num?)?.toInt() ?? 0;
          stock[item] =
              min(config.productionMaxStock, current + cycles * quantity);
        });
        production['lastResolvedAt'] =
            last + cycles * config.productionIntervalSeconds * 1000;
      }
    }
    final residentId = alcove['occupantIndividualId'] as String?;
    if (residentId == null) return state;
    final individual = _individual(state, residentId);
    final stage = individual['lifecycle']['stage'] as String;
    final initiative = personalityValue(individual, 'initiative');
    final care = individual['care'] as Map<String, dynamic>;
    final autonomyDelayMs = (stage == 'MATURE'
                ? 10
                : stage == 'INTERMEDIATE'
                    ? 20
                    : 999999) *
            const Duration(minutes: 1).inMilliseconds +
        ((1 - initiative) * const Duration(minutes: 10).inMilliseconds).round();
    final lastAutonomy = (care['lastAutonomousAt'] as num?)?.toInt() ?? 0;
    final mayActAutonomously = stage != 'BABY' &&
        now - lastAutonomy >= autonomyDelayMs &&
        !isSleeping(individual, now, config);
    if (mayActAutonomously &&
        (hunger(state, residentId, now, config) == 'HUNGRY' ||
            hunger(state, residentId, now, config) == 'VERY_HUNGRY')) {
      final favorite =
          individual['generatedProfile']['foodPreference'] as String;
      final food = _consumeLocal(alcove, <String>[
        favorite,
        favorite == 'ROOT' ? 'LEAF' : 'ROOT',
        'ALGAE',
        'MOSS',
        'MUSHROOM'
      ]);
      if (food != null) {
        care['lastMealAt'] = now;
        care['autonomousMealCount'] = (care['autonomousMealCount'] as int) + 1;
        care['lastAutonomousAt'] = now;
        _memory(state, residentId, 'FIRST_AUTONOMOUS_MEAL', now);
        _interaction(individual, 'AUTONOMOUS_MEAL', initiative: 1);
        _adjustWellbeing(individual, initiative >= .5 ? 3 : 1, now);
      }
    }
    final structural = mayActAutonomously
        ? _consumeLocal(alcove, const <String>['IRON'])
        : null;
    if (structural != null) {
      final intake =
          individual['care']['structuralIntake'] as Map<String, dynamic>;
      intake['total'] = (intake['total'] as int) + 2;
      final byMaterial = intake['byMaterial'] as Map;
      byMaterial['IRON'] = ((byMaterial['IRON'] as num?)?.toInt() ?? 0) + 2;
      care['lastAutonomousAt'] = now;
      _interaction(individual, 'AUTONOMOUS_STRUCTURE', initiative: 1);
      _adjustWellbeing(individual, initiative >= .5 ? 2 : 1, now);
    }
    return state;
  }

  static ElevageSave harvestLocal(
      ElevageSave source, String alcoveId, int slot, String itemId, int now) {
    final state = source.copy();
    final slots = _alcove(state, alcoveId)['slots'] as List;
    if (slot < 0 || slot >= slots.length || slots[slot] is! Map) {
      throw StateError('Installation indisponible.');
    }
    final stock = ((slots[slot] as Map)['productionState']
        as Map?)?['availableByItemId'] as Map?;
    if (stock == null || ((stock[itemId] as num?)?.toInt() ?? 0) < 1) {
      throw StateError('Rien à récolter.');
    }
    stock[itemId] = (stock[itemId] as num).toInt() - 1;
    final special = _special(state);
    special[itemId] = (special[itemId] ?? 0) + 1;
    return state;
  }

  /// Évalue les besoins sans les confondre avec une sollicitation. Une Request
  /// n'existe que lorsque l'individu choisit réellement de communiquer.
  static ElevageSave refreshRequest(
      ElevageSave source, String id, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, id);
    final active = individual['activeRequest'] as Map?;
    if (active != null && now >= (active['expiresAt'] as int)) {
      individual['activeRequest'] = null;
    }
    if (individual['activeRequest'] != null ||
        isSleeping(individual, now, config)) {
      return state;
    }
    final hungerState = hunger(state, id, now, config);
    final need =
        hungerState == 'HUNGRY' || hungerState == 'VERY_HUNGRY' ? 'FOOD' : null;
    if (need == null) return state;
    final stage = individual['lifecycle']['stage'] as String;
    final initiative = personalityValue(individual, 'initiative');
    final alcove = _alcove(state, individual['alcoveId'] as String);
    final localFood = _hasLocal(alcove, foodItems);
    // Les individus plus autonomes essaient d'abord le stock de leur Alcôve;
    // le besoin existe tout de même, mais ne devient pas une Request visible.
    if (stage != 'BABY' && initiative >= .5 && localFood) return state;
    final preferred =
        individual['generatedProfile']['foodPreference'] as String;
    final signal = switch (stage) {
      'BABY' => 'Pti ?',
      'INTERMEDIATE' => 'FOOD',
      _ => preferred,
    };
    individual['activeRequest'] = <String, dynamic>{
      'need': need,
      'signal': signal,
      'createdAt': now,
      'expiresAt': now + config.requestDurationSeconds * 1000,
    };
    final count = _observe(individual, 'REQUEST_FOOD', now, config: config);
    _setObservationStatus(
        individual, 'REQUEST_FOOD:GENERAL', count, config, now);
    (state.data['individuals'] as Map<String, dynamic>)[id] = individual;
    return state;
  }

  static Map<String, dynamic>? activeRequest(
      ElevageSave state, String id, int now) {
    final request = _individual(state, id)['activeRequest'] as Map?;
    if (request == null || now >= (request['expiresAt'] as int)) return null;
    return Map<String, dynamic>.from(request);
  }

  static ElevageSave buyTreat(
      ElevageSave source, String item, ElevageConfig config) {
    final state = source.copy();
    final prices = <String, int>{
      'FIBROUS_FRUIT': config.fibrousFruitPrice,
      'FRUIT_JELLY': config.fruitJellyPrice,
    };
    final price = prices[item];
    if (price == null) throw StateError('Offre indisponible.');
    final inventory = state.data['inventory'] as Map;
    if ((inventory['bioPiles'] as int) < price) {
      throw StateError('Pas assez de Bio-piles.');
    }
    inventory['bioPiles'] = (inventory['bioPiles'] as int) - price;
    final special = _special(state);
    special[item] = (special[item] ?? 0) + 1;
    return state;
  }

  static ElevageSave sellGeneric(
      ElevageSave source, String item, ElevageConfig config) {
    final state = source.copy();
    final key = item == 'ORGANIC'
        ? 'organic'
        : item == 'MINERAL'
            ? 'mineral'
            : null;
    if (key == null || (_generic(state)[key] ?? 0) < config.buybackQuantity) {
      throw StateError('Quantité insuffisante.');
    }
    final generic = _generic(state);
    generic[key] = generic[key]! - config.buybackQuantity;
    state.data['inventory']['bioPiles'] =
        (state.data['inventory']['bioPiles'] as int) + config.buybackBioPiles;
    return state;
  }

  static ElevageSave processReturns(ElevageSave source, int now) {
    final state = source.copy();
    for (final id
        in List<String>.from(state.data['activeIndividualIds'] as List)) {
      final individual = _individual(state, id);
      final ownership = individual['ownership'] as Map;
      if (ownership['mode'] != 'CO_REARING' ||
          ownership['returnProcessedAt'] != null ||
          now < (ownership['expiresAt'] as int)) {
        continue;
      }
      ownership['returnProcessedAt'] = now;
      (state.data['activeIndividualIds'] as List).remove(id);
      _alcove(state, individual['alcoveId'] as String)['occupantIndividualId'] =
          null;
      (state.data['coRearingReturnLedger'] as Map<String, dynamic>)[id] =
          <String, dynamic>{
        'individualId': id,
        'alcoveId': individual['alcoveId'],
        'name': individual['name'],
        'processedAt': now
      };
      (state.data['pendingNotifications'] as List).add(<String, dynamic>{
        'id': 'return-$id',
        'type': 'CO_REARING_RETURNED',
        'name': individual['name'],
        'createdAt': now,
        'acknowledgedAt': null
      });
    }
    return state;
  }

  static Map<String, int> moveOutRefund(
      ElevageSave state, String alcoveId, ElevageConfig config) {
    final alcove = _alcove(state, alcoveId);
    if (alcove['occupantIndividualId'] != null) {
      throw StateError('Alcôve occupée.');
    }
    var organic = 0;
    var mineral = 0;
    for (final raw in alcove['slots'] as List) {
      if (raw is! Map || raw['acquisitionMode'] != 'CRAFTED') continue;
      final paid = raw['paidCost'] as Map?;
      organic += (paid?['organic'] as num?)?.toInt() ?? 0;
      mineral += (paid?['mineral'] as num?)?.toInt() ?? 0;
    }
    return <String, int>{
      'organic': (organic * config.refundOrganicRate).floor(),
      'mineral': (mineral * config.refundMineralRate).floor()
    };
  }

  static ElevageSave moveOut(
      ElevageSave source, String alcoveId, ElevageConfig config) {
    final state = source.copy();
    final refund = moveOutRefund(state, alcoveId, config);
    final generic = _generic(state);
    generic['organic'] = (generic['organic'] ?? 0) + refund['organic']!;
    generic['mineral'] = (generic['mineral'] ?? 0) + refund['mineral']!;
    final alcove = _alcove(state, alcoveId);
    alcove['slots'] =
        List<dynamic>.filled((alcove['slotLimit'] as num).toInt(), null);
    return state;
  }

  static bool metamorphosisAvailable(
      ElevageSave state, String id, int now, ElevageConfig config) {
    final individual = _individual(state, id);
    final stage = individual['lifecycle']['stage'] as String;
    if (stage == 'MATURE') return false;
    final enteredAt = individual['lifecycle']['stageEnteredAt'] as int;
    final minimum = stage == 'BABY'
        ? config.babyMinimumHours
        : config.intermediateMinimumHours;
    if (now - enteredAt < minimum * const Duration(hours: 1).inMilliseconds) {
      return false;
    }
    final care = individual['care'] as Map;
    final discovery =
        individual['preferenceDiscovery']['foodPreference'] as Map;
    final evidence = individual['progressionEvidence'] as Map;
    final slots =
        _alcove(state, individual['alcoveId'] as String)['slots'] as List;
    if (stage == 'BABY') {
      return discovery['status'] != 'UNKNOWN' &&
          (care['metabolicMeals'] as int) >= 3 &&
          ((care['structuralIntake'] as Map)['total'] as int) >= 2 &&
          (evidence['interactionTypes'] as List).length >= 3 &&
          slots.any((slot) => slot != null);
    }
    return discovery['status'] == 'CONFIRMED' &&
        (care['metabolicMeals'] as int) >= 5 &&
        ((care['structuralIntake'] as Map)['total'] as int) >= 6 &&
        (care['autonomousMealCount'] as int) > 0 &&
        (evidence['personalityEvents'] as int) >= 5;
  }

  static ElevageSave metamorphose(ElevageSave source, String id, int now) {
    final state = source.copy();
    final individual = _individual(state, id);
    final lifecycle = individual['lifecycle'] as Map;
    final next = lifecycle['stage'] == 'BABY' ? 'INTERMEDIATE' : 'MATURE';
    lifecycle['stage'] = next;
    lifecycle['stageEnteredAt'] = now;
    _memory(
        state,
        id,
        next == 'INTERMEDIATE' ? 'FIRST_METAMORPHOSIS' : 'SECOND_METAMORPHOSIS',
        now);
    return state;
  }

  static String? communication(
      ElevageSave state, String id, int now, ElevageConfig config) {
    final individual = _individual(state, id);
    final stage = individual['lifecycle']['stage'] as String;
    if (stage == 'BABY') return null;
    if (hunger(state, id, now, config) == 'HUNGRY' ||
        hunger(state, id, now, config) == 'VERY_HUNGRY') {
      return stage == 'MATURE'
          ? individual['generatedProfile']['foodPreference'] as String
          : 'FOOD';
    }
    final structural = individual['care']['structuralIntake']['total'] as int;
    if (structural < 6) return stage == 'MATURE' ? 'IRON' : 'MINERAL';
    return null;
  }

  static String reactionFor(String item, Map<String, dynamic> individual) {
    if (treatItems.contains(item) ||
        item == individual['generatedProfile']['foodPreference']) {
      return 'RUSH_SHAKE';
    }
    if (item == 'IRON') return 'VIBRATE';
    if (item == 'QUARTZ') return 'STEP_BACK';
    return 'APPROACH';
  }

  static Map<String, dynamic> _alcove(ElevageSave state, String id) =>
      (state.data['alcoves'] as List)
          .cast<Map>()
          .where((item) => item['id'] == id)
          .cast<Map<String, dynamic>>()
          .first;
  static List<Map<String, dynamic>> _sceneItems(
      ElevageSave state, String alcoveId) {
    final byAlcove = state.data['sceneItemsByAlcoveId'] as Map<String, dynamic>;
    final raw = byAlcove.putIfAbsent(alcoveId, () => <dynamic>[]) as List;
    return raw
        .cast<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList()
      ..also((items) => byAlcove[alcoveId] = items);
  }

  static String? _drierSceneZone(ElevageSave state, String alcoveId,
      String currentZoneId, ElevageConfig config, int now,
      {String? phaseOverride}) {
    final occupied = _sceneItems(state, alcoveId)
        .where((entry) => entry['zoneId'] != currentZoneId)
        .map((entry) => entry['zoneId'] as String)
        .toSet();
    final candidates = config.sceneZones
        .where(
            (zone) => zone.id != currentZoneId && !occupied.contains(zone.id))
        .toList()
      ..sort((left, right) => zoneEnvironment(state, alcoveId, left.id, config,
              now: now, phaseOverride: phaseOverride)['humidity']!
          .compareTo(zoneEnvironment(state, alcoveId, right.id, config,
              now: now, phaseOverride: phaseOverride)['humidity']!));
    return candidates.isEmpty ? null : candidates.first.id;
  }

  static int _observationCount(Map<String, dynamic> individual, String id) {
    final observations =
        ((individual['observationJournal'] as Map?)?['observations'] as Map?) ??
            const <String, dynamic>{};
    return ((observations[id] as Map?)?['count'] as num?)?.toInt() ?? 0;
  }

  static Map<String, dynamic> _individual(ElevageSave state, String id) {
    final individuals = state.data['individuals'] as Map<String, dynamic>;
    final individual = Map<String, dynamic>.from(individuals[id] as Map);
    // Les mutations métier touchent parfois des champs de premier niveau
    // (`activeRequest`, `wellbeing`, cooldown social). Réinsérer la copie évite
    // qu’elles disparaissent silencieusement tout en gardant l’API historique.
    individuals[id] = individual;
    return individual;
  }

  static Map<String, int> _generic(ElevageSave state) =>
      Map<String, int>.from((state.data['inventory']['generic'] as Map)
          .map((key, value) => MapEntry('$key', (value as num).toInt())))
        ..also((map) => state.data['inventory']['generic'] = map);
  static Map<String, int> _special(ElevageSave state) =>
      Map<String, int>.from((state.data['inventory']['special'] as Map)
          .map((key, value) => MapEntry('$key', (value as num).toInt())))
        ..also((map) => state.data['inventory']['special'] = map);

  static bool _physicalAlreadyLinked(ElevageSave state, String ref) =>
      (state.data['activeIndividualIds'] as List).any((id) =>
          (state.data['individuals'] as Map)[id]['ownership']
              ['physicalFigureRef'] ==
          ref);
  static void _memory(ElevageSave state, String id, String event, int now) {
    final events = state.data['memoryEvents'] as Map<String, dynamic>;
    final individualEvents =
        events.putIfAbsent(id, () => <String, dynamic>{}) as Map;
    individualEvents.putIfAbsent(event, () => now);
  }

  static int _observe(Map<String, dynamic> individual, String type, int now,
      {String? relatedItemId,
      String? relatedEnvironmentAxis,
      String status = 'UNKNOWN',
      ElevageConfig? config}) {
    final rules = config ?? defaultElevageConfig;
    final journal = individual['observationJournal'] as Map;
    final observations = journal.putIfAbsent(
        'observations', () => <String, dynamic>{}) as Map<String, dynamic>;
    final subject = relatedItemId ?? relatedEnvironmentAxis ?? 'GENERAL';
    final id = '$type:$subject';
    final entry = observations.putIfAbsent(
        id,
        () => <String, dynamic>{
              'id': id,
              'type': type,
              'individualId': individual['id'],
              'firstObservedAt': now,
              'lastObservedAt': now,
              'count': 0,
              'rawBehaviorCount': 0,
              'meaningfulEvidenceCount': 0,
              'lastEvidenceAt': null,
              'relatedItemId': relatedItemId,
              'relatedEnvironmentAxis': relatedEnvironmentAxis,
              'status': status,
            }) as Map;
    entry['lastObservedAt'] = now;
    entry['rawBehaviorCount'] = ((entry['rawBehaviorCount'] as num?)?.toInt() ??
            (entry['count'] as num?)?.toInt() ??
            0) +
        1;
    final existing = (entry['meaningfulEvidenceCount'] as num?)?.toInt() ??
        (entry['count'] as num?)?.toInt() ??
        0;
    final lastEvidence = entry['lastEvidenceAt'] as int?;
    final outsideWindow = lastEvidence == null ||
        now - lastEvidence >=
            rules.observationEvidenceCooldownMinutes *
                const Duration(minutes: 1).inMilliseconds;
    final evidence = entry['status'] == 'CONFIRMED' || !outsideWindow
        ? existing
        : existing + 1;
    if (evidence != existing) entry['lastEvidenceAt'] = now;
    entry['meaningfulEvidenceCount'] = evidence;
    entry['count'] = evidence;
    if (status != 'UNKNOWN') entry['status'] = status;
    return evidence;
  }

  static void _setObservationStatus(Map<String, dynamic> individual, String id,
      int count, ElevageConfig config, int now) {
    final observations = (individual['observationJournal']
        as Map)['observations'] as Map<String, dynamic>;
    final entry = observations[id] as Map?;
    if (entry == null) return;
    if (count >= config.suspectedThreshold && entry['suspectedAt'] == null) {
      entry['suspectedAt'] = now;
    }
    entry['status'] =
        count >= config.confirmedThreshold && entry['suspectedAt'] != null
            ? 'CONFIRMED'
            : count >= config.suspectedThreshold
                ? 'SUSPECTED'
                : 'OBSERVED';
  }

  static void _interaction(Map<String, dynamic> individual, String type,
      {int initiative = 0, int contact = 0, int tempo = 0}) {
    final evidence = individual['progressionEvidence'] as Map;
    final types = evidence['interactionTypes'] as List;
    if (!types.contains(type)) types.add(type);
    evidence['personalityEvents'] = (evidence['personalityEvents'] as int) + 1;
    final trends = individual['personality']['tendencies'] as Map;
    for (final item in <String, int>{
      'initiative': initiative,
      'contact': contact,
      'tempo': tempo
    }.entries) {
      final current = (trends[item.key] as num).toInt();
      trends[item.key] = (current + item.value).clamp(-16, 16);
    }
    final development = individual['personality']['development'] as Map?;
    if (development == null) return;
    final stage = individual['lifecycle']['stage'] as String;
    final bucketName = stage == 'BABY'
        ? 'babyExperience'
        : stage == 'INTERMEDIATE'
            ? 'intermediateExperience'
            : 'adultPlasticity';
    final bucket = development[bucketName] as Map;
    for (final item in <String, int>{
      'initiative': initiative,
      'contact': contact,
      'tempo': tempo,
    }.entries) {
      final current = (bucket[item.key] as num?)?.toInt() ?? 0;
      bucket[item.key] = (current + item.value).clamp(-16, 16);
    }
  }

  static void _adjustWellbeing(
      Map<String, dynamic> individual, int delta, int now) {
    final wellbeing = individual.putIfAbsent('wellbeing',
        () => <String, dynamic>{'value': 60, 'lastUpdatedAt': now}) as Map;
    final current = (wellbeing['value'] as num?)?.toInt() ?? 60;
    wellbeing['value'] = (current + delta).clamp(0, 100);
    wellbeing['lastUpdatedAt'] = now;
  }

  static bool _hasLocal(Map<String, dynamic> alcove, List<String> choices) {
    for (final raw in alcove['slots'] as List) {
      if (raw is! Map) continue;
      final stock = raw['productionState']?['availableByItemId'];
      if (stock is Map &&
          choices.any((item) => ((stock[item] as num?)?.toInt() ?? 0) > 0)) {
        return true;
      }
    }
    return false;
  }

  static String? _consumeLocal(
      Map<String, dynamic> alcove, List<String> choices) {
    for (final choice in choices) {
      for (final raw in alcove['slots'] as List) {
        if (raw is! Map) continue;
        final stock = raw['productionState']?['availableByItemId'];
        if (stock is Map && ((stock[choice] as num?)?.toInt() ?? 0) > 0) {
          stock[choice] = (stock[choice] as int) - 1;
          return choice;
        }
      }
    }
    return null;
  }

  static String _runStatus(Map<String, dynamic> run, int now) =>
      run['rewardClaimedAt'] != null
          ? 'COMPLETED'
          : now >= (run['readyAt'] as int)
              ? 'READY'
              : 'IN_PROGRESS';
  static int _hash(String value) =>
      value.codeUnits.fold<int>(7, (hash, unit) => hash * 31 + unit);
  static List<Map<String, dynamic>> _foragingPoints(String biome, String seed) {
    final random = Random(_hash(seed));
    final table = switch (biome) {
      'FOREST' => <String>[
          'ROOT',
          'LEAF',
          'FRUIT',
          'SEED',
          'SPROUT',
          'MOSS',
          'MUSHROOM'
        ],
      'COAST' => <String>['ALGAE', 'ALGAE_FRAGMENT', 'LIMESTONE'],
      _ => <String>['LIMESTONE', 'QUARTZ', 'IRON'],
    };
    final labels = switch (biome) {
      'FOREST' => <String>['Sous les racines', 'Buisson', 'Sol humide'],
      'COAST' => <String>['Bord de l’eau', 'Dépôt calcaire', 'Banc d’algues'],
      _ => <String>['Affleurement', 'Fissure rocheuse', 'Pierrier'],
    };
    return List<Map<String, dynamic>>.generate(3, (index) {
      final generic = biome == 'FOREST'
          ? <String, int>{'organic': 2}
          : biome == 'COAST'
              ? <String, int>{'organic': 1, 'mineral': 1}
              : <String, int>{'mineral': 3};
      return <String, dynamic>{
        'id': 'point-$index',
        'label': labels[index],
        'reward': <String, dynamic>{
          'generic': generic,
          'special': table[random.nextInt(table.length)]
        }
      };
    });
  }
}

extension _Also<T> on T {
  T also(void Function(T value) action) {
    action(this);
    return this;
  }
}
