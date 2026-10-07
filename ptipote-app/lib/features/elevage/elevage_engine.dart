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
        'special': <String, int>{},
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
      'runsByIndividualId': <String, dynamic>{},
      'memoryEvents': <String, dynamic>{},
      'coRearingReturnLedger': <String, dynamic>{},
      'pendingNotifications': <dynamic>[],
    });
  }

  factory ElevageSave.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != elevageSaveSchemaVersion) {
      throw const FormatException('Version de sauvegarde Élevage inconnue.');
    }
    final normalized = _clone(json);
    normalized.putIfAbsent('runsByIndividualId', () => <String, dynamic>{});
    normalized.putIfAbsent('installationInventory', () => <String, dynamic>{});
    normalized.putIfAbsent('discoveredItemIds', () => <String>[]);
    normalized.putIfAbsent('coRearingReturnLedger', () => <String, dynamic>{});
    normalized.putIfAbsent('pendingNotifications', () => <dynamic>[]);
    return ElevageSave(normalized);
  }

  ElevageSave copy() => ElevageSave(_clone(data));
  Map<String, dynamic> toJson() => _clone(data);
  String encode() => jsonEncode(toJson());
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
      return state;
    }
    if (!foodItems.contains(item)) {
      throw StateError('Cet objet ne nourrit pas Résonance.');
    }
    special[item] = special[item]! - 1;
    final care = individual['care'] as Map<String, dynamic>;
    care['lastMealAt'] = now;
    care['metabolicMeals'] = (care['metabolicMeals'] as int) + 1;
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
    } else {
      _interaction(individual, 'FOOD', contact: 1);
    }
    _memory(state, id, 'FIRST_FOOD', now);
    return state;
  }

  static ElevageSave offerStructural(
      ElevageSave source, String id, String item, int now) {
    final state = source.copy();
    final individual = _individual(state, id);
    final gains = <String, int>{'IRON': 2, 'LIMESTONE': 1, 'QUARTZ': 0};
    final gain = gains[item];
    if (gain == null) throw StateError('Matériau inconnu.');
    if (gain == 0) return state;
    final special = _special(state);
    if ((special[item] ?? 0) < 1) throw StateError('Matériau non disponible.');
    special[item] = special[item]! - 1;
    final intake =
        individual['care']['structuralIntake'] as Map<String, dynamic>;
    intake['total'] = (intake['total'] as int) + gain;
    final byMaterial = intake['byMaterial'] as Map<String, dynamic>;
    byMaterial[item] = (byMaterial[item] as int? ?? 0) + gain;
    _interaction(individual, 'STRUCTURE', tempo: 1);
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
    if (hours >= config.hungerVeryHungryHours) return 'VERY_HUNGRY';
    if (hours >= config.hungerHungryHours) return 'HUNGRY';
    if (hours >= config.hungerNormalHours) return 'NORMAL';
    return 'SATIATED';
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
    if (hunger(state, residentId, now, config) == 'HUNGRY' ||
        hunger(state, residentId, now, config) == 'VERY_HUNGRY') {
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
        final care = individual['care'] as Map<String, dynamic>;
        care['lastMealAt'] = now;
        care['autonomousMealCount'] = (care['autonomousMealCount'] as int) + 1;
        _memory(state, residentId, 'FIRST_AUTONOMOUS_MEAL', now);
        _interaction(individual, 'AUTONOMOUS_MEAL', initiative: 1);
      }
    }
    final structural = _consumeLocal(alcove, const <String>['IRON']);
    if (structural != null) {
      final intake =
          individual['care']['structuralIntake'] as Map<String, dynamic>;
      intake['total'] = (intake['total'] as int) + 2;
      final byMaterial = intake['byMaterial'] as Map;
      byMaterial['IRON'] = ((byMaterial['IRON'] as num?)?.toInt() ?? 0) + 2;
    }
    return state;
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
  static Map<String, dynamic> _individual(ElevageSave state, String id) =>
      Map<String, dynamic>.from((state.data['individuals'] as Map)[id] as Map);
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
