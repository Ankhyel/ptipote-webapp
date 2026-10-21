import 'dart:convert';
import 'dart:math';

import 'elevage_config.dart';

const int elevageSaveSchemaVersion = 1;
const Set<String> _resonanceFormationIds = <String>{
  'FORMATION_METALLIQUE',
  'FORMATION_CRISTALLINE',
  'FORMATION_MINERALE',
};

class ElevageSave {
  ElevageSave(this.data);

  final Map<String, dynamic> data;

  factory ElevageSave.initial(ElevageConfig config, {required int now}) {
    return ElevageSave(<String, dynamic>{
      'schemaVersion': elevageSaveSchemaVersion,
      'savedAt': now,
      'activeConfigRevision': config.revision,
      'inventory': <String, dynamic>{
        'generic': <String, int>{'organic': 0, 'mineral': 0, 'energy': 0},
        'special': <String, int>{'ROOT': 1, 'LEAF': 1},
        'bioPiles': 0,
      },
      'alcoves': List<Map<String, dynamic>>.generate(
        config.alcoveCount,
        (index) => <String, dynamic>{
          'id': 'alcove-${index + 1}',
          'slotLimit': config.installationSlotCount,
          'occupantIndividualId': null,
          'progressState': index <
                  (config.devMode && config.preset == ElevagePreset.prototype
                      ? config.alcoveCount
                      : config.startingAlcoveCount)
              ? 'READY'
              : 'LOCKED',
          'batterySlot': null,
          'biogeneratorSlot': null,
          'localEnergy': 0,
          'slots': List<dynamic>.filled(config.installationSlotCount, null),
          'createdAt': now,
        },
      ),
      'individuals': <String, dynamic>{},
      'activeIndividualIds': <String>[],
      'discoveredItemIds': <String>[],
      'installationInventory': <String, dynamic>{},
      'moduleInventory': <String, dynamic>{},
      'batteryInventory': <String, dynamic>{
        for (var index = 0; index < config.startingBioBatteryCount; index++)
          'battery-$now-$index': <String, dynamic>{
            'instanceId': 'battery-$now-$index',
            'itemId': 'BIO_BATTERY',
            'currentEnergy': config.bioBatteryEnergy,
            'maxEnergy': config.bioBatteryEnergy,
            'createdAt': now,
          },
      },
      'biogeneratorInventory': <String, dynamic>{},
      // The cooker is a Refuge infrastructure: it is never attached to Z1–Z4.
      'cooker': <String, dynamic>{
        'infrastructureId': 'COOKER',
        'crafted': false,
        'installed': false,
        'cookingHeat': 0,
      },
      'cookedMeals': <String, dynamic>{},
      'cookedMealInventory': <String, dynamic>{},
      'knownCookingRecipes': <String, dynamic>{},
      'waterTank': 0.0,
      'weather': <String, dynamic>{'lastUpdatedAt': now},
      // `contribution` is retained as a legacy mirror for older saves and
      // integrations. `trust` is the canonical player-facing progression.
      'refugeProgress': <String, dynamic>{
        'contribution': 0,
        'trust': 0,
        'trustHistory': <dynamic>[],
        'trustEventIds': <String, dynamic>{},
      },
      'habitatInventory': <String, dynamic>{},
      'habitatItemsByAlcoveId': <String, dynamic>{},
      // Items placed in the four visible Alcôve zones. They are deliberately
      // separate from both the player inventory and installed constructions.
      'sceneItemsByAlcoveId': <String, dynamic>{},
      'runsByIndividualId': <String, dynamic>{},
      'exploration': ElevageDomain.initialExplorationState(now, config),
      'memoryEvents': <String, dynamic>{},
      'coRearingReturnLedger': <String, dynamic>{},
      'pendingNotifications': <dynamic>[],
      // Marqueur déjà appliqué aux nouvelles parties : les anciennes saves
      // reçoivent le même starter lors de leur première ouverture Lot 17.
      'qaInventoryResetV17': true,
      // `inventory` is the Refuge-wide reserve. It is intentionally not
      // attached to an Alcôve; only scene items and producer stocks are local.
      'sharedReserveMigrationV21': true,
    });
  }

  factory ElevageSave.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != elevageSaveSchemaVersion) {
      throw const FormatException('Version de sauvegarde Élevage inconnue.');
    }
    final normalized = _clone(json);
    normalized.putIfAbsent('runsByIndividualId', () => <String, dynamic>{});
    ElevageDomain.normalizeExplorationState(
        normalized, (normalized['savedAt'] as num?)?.toInt() ?? 0);
    normalized.putIfAbsent('installationInventory', () => <String, dynamic>{});
    normalized.putIfAbsent('moduleInventory', () => <String, dynamic>{});
    normalized.putIfAbsent('batteryInventory', () => <String, dynamic>{});
    normalized.putIfAbsent('biogeneratorInventory', () => <String, dynamic>{});
    normalized.putIfAbsent('cookedMeals', () => <String, dynamic>{});
    normalized.putIfAbsent(
        'cooker',
        () => <String, dynamic>{
              'infrastructureId': 'COOKER',
              'crafted': false,
              'installed': false,
              'cookingHeat': 0,
            });
    final cooker = normalized['cooker'] as Map;
    cooker.putIfAbsent('infrastructureId', () => 'COOKER');
    cooker.putIfAbsent('crafted', () => false);
    cooker.putIfAbsent('installed', () => false);
    cooker.putIfAbsent('cookingHeat', () => 0);
    normalized.putIfAbsent('cookedMealInventory', () => <String, dynamic>{});
    normalized.putIfAbsent('knownCookingRecipes', () => <String, dynamic>{});
    // Cuisine V1 stored batches outside the physical inventory. Convert their
    // unclaimed portions once, retaining every known composition and never
    // recreating them on a later reload.
    if (normalized['cookedMealsMigrationV227'] != true) {
      final legacy = normalized['cookedMeals'] as Map;
      final meals = normalized['cookedMealInventory'] as Map<String, dynamic>;
      final recipes = normalized['knownCookingRecipes'] as Map<String, dynamic>;
      for (final entry in legacy.entries.where((entry) => entry.value is Map)) {
        final batch = entry.value as Map;
        final ingredients =
            (batch['ingredientIds'] as List? ?? const <dynamic>[])
                .whereType<String>()
                .toList(growable: false);
        if (ingredients.isEmpty) continue;
        final usedWater = batch['usedWater'] == true;
        final key = ElevageDomain.cookingRecipeKey(ingredients, usedWater);
        recipes.putIfAbsent(
            key,
            () => <String, dynamic>{
                  'recipeKey': key,
                  'customName': 'Préparation héritée',
                  'ingredientIds': ingredients,
                  'usedWater': usedWater,
                  'createdAt': batch['createdAt'] ?? 0,
                });
        final portions = batch['satietyPerPortionDistribution'] as List? ??
            const <dynamic>[];
        final remaining = (batch['remainingPortions'] as num?)?.toInt() ?? 0;
        final total =
            (batch['portionCount'] as num?)?.toInt() ?? portions.length;
        final consumed = (total - remaining).clamp(0, portions.length);
        for (var index = consumed; index < portions.length; index++) {
          final id = 'legacy-cooked-${entry.key}-$index';
          meals.putIfAbsent(
              id,
              () => <String, dynamic>{
                    'instanceId': id,
                    'itemId': 'COOKED_MEAL',
                    'recipeKey': key,
                    'recipeName': 'Préparation héritée',
                    'ingredientIds': ingredients,
                    'usedWater': usedWater,
                    'satietyValue': (portions[index] as num?)?.toDouble() ?? 0,
                    'createdAt': batch['createdAt'] ?? 0,
                    'batchId': entry.key,
                  });
        }
      }
      legacy.clear();
      normalized['cookedMealsMigrationV227'] = true;
    }
    normalized.putIfAbsent('waterTank', () => 0.0);
    normalized.putIfAbsent(
        'weather',
        () => <String, dynamic>{
              'lastUpdatedAt': (normalized['savedAt'] as num?)?.toInt() ?? 0,
            });
    normalized.putIfAbsent('refugeProgress',
        () => <String, dynamic>{'contribution': 0, 'trust': 0});
    final refugeProgress = normalized['refugeProgress'] as Map;
    // Lot 22.4 migration: never discard historic Contribution. Older saves
    // receive its exact value as their starting Confiance once, while keeping
    // the legacy field readable for prior Dashboard/config integrations.
    if (refugeProgress['trustMigrationV224'] != true) {
      refugeProgress['trust'] = (refugeProgress['trust'] as num?)?.toInt() ??
          (refugeProgress['contribution'] as num?)?.toInt() ??
          0;
      refugeProgress['trustMigrationV224'] = true;
    }
    refugeProgress.putIfAbsent('contribution', () => refugeProgress['trust']);
    refugeProgress.putIfAbsent('trust', () => 0);
    refugeProgress.putIfAbsent('trustHistory', () => <dynamic>[]);
    refugeProgress.putIfAbsent('trustEventIds', () => <String, dynamic>{});
    normalized.putIfAbsent('habitatInventory', () => <String, dynamic>{});
    normalized.putIfAbsent('habitatItemsByAlcoveId', () => <String, dynamic>{});
    normalized.putIfAbsent('sceneItemsByAlcoveId', () => <String, dynamic>{});
    normalized.putIfAbsent('discoveredItemIds', () => <String>[]);
    normalized.putIfAbsent('coRearingReturnLedger', () => <String, dynamic>{});
    normalized.putIfAbsent('pendingNotifications', () => <dynamic>[]);
    // Formations are resonance supports, never resource producers. Remove
    // any legacy local stock that a previous prototype may have persisted.
    for (final alcove in (normalized['alcoves'] as List? ?? const <dynamic>[])
        .whereType<Map>()) {
      alcove.putIfAbsent('progressState', () => 'READY');
      alcove.putIfAbsent('batterySlot', () => null);
      alcove.putIfAbsent('biogeneratorSlot', () => null);
      alcove.putIfAbsent('localEnergy', () => 0);
      for (final slot
          in (alcove['slots'] as List? ?? const <dynamic>[]).whereType<Map>()) {
        slot.putIfAbsent('installedModules', () => <dynamic>[]);
        if (_resonanceFormationIds.contains(slot['definitionId'])) {
          slot.remove('productionState');
        }
      }
    }
    for (final instance in (normalized['installationInventory'] as Map)
        .values
        .whereType<Map>()) {
      instance.putIfAbsent('installedModules', () => <dynamic>[]);
    }
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
    // Lot 21: historic Alcôve-bound portable inventories are folded exactly
    // once into the existing player-level inventory, now named Réserve in UI.
    // Physical scene items and producer stocks stay where they are.
    if (normalized['sharedReserveMigrationV21'] != true) {
      final reserve = normalized['inventory'] as Map? ?? <String, dynamic>{};
      reserve.putIfAbsent(
          'generic', () => <String, int>{'organic': 0, 'mineral': 0});
      reserve.putIfAbsent('special', () => <String, int>{});
      reserve.putIfAbsent('bioPiles', () => 0);
      final reserveGeneric = reserve['generic'] as Map;
      final reserveSpecial = reserve['special'] as Map;
      for (final alcove in (normalized['alcoves'] as List? ?? const <dynamic>[])
          .whereType<Map>()) {
        final legacy = alcove.remove('inventory');
        if (legacy is! Map) continue;
        final generic = legacy['generic'] as Map?;
        final special = legacy['special'] as Map?;
        generic?.forEach((key, value) {
          final amount = (value as num?)?.toInt() ?? 0;
          reserveGeneric[key] =
              ((reserveGeneric[key] as num?)?.toInt() ?? 0) + amount;
        });
        special?.forEach((key, value) {
          final amount = (value as num?)?.toInt() ?? 0;
          reserveSpecial[key] =
              ((reserveSpecial[key] as num?)?.toInt() ?? 0) + amount;
        });
      }
      normalized['inventory'] = reserve;
      normalized['sharedReserveMigrationV21'] = true;
    }
    final generic = (normalized['inventory'] as Map)['generic'] as Map;
    generic.putIfAbsent('energy', () => 0);
    // Canonical resource migration: ALGAE_FRAGMENT was a legacy duplicate of
    // ALGAE. Merge numeric stock keys and rewrite all preference/loot/recipe
    // references once, leaving no second resource for runtime behaviour.
    if (normalized['algaeNormalizationV211'] != true) {
      _normalizeLegacyAlgae(normalized);
      normalized['algaeNormalizationV211'] = true;
    }
    // Installed geothermal holes become active bio-organic ovens in place,
    // preserving their instance ID, zone and any user placement metadata.
    if (normalized['bioOrganicOvenMigrationV211'] != true) {
      _normalizeLegacyGeothermal(normalized);
      normalized['bioOrganicOvenMigrationV211'] = true;
    }
    // Apply Refuge locks only once. Occupied legacy Alcôves remain available
    // to avoid evicting a resident when upgrading an existing save.
    if (normalized['refugeProgressMigrationV213'] != true) {
      final alcoves = normalized['alcoves'] as List? ?? const <dynamic>[];
      for (var index = 1; index < alcoves.length; index++) {
        final alcove = alcoves[index];
        if (alcove is Map &&
            alcove['occupantIndividualId'] == null &&
            !(alcove['slots'] as List? ?? const <dynamic>[])
                .any((slot) => slot != null)) {
          alcove['progressState'] = 'LOCKED';
        }
      }
      normalized['refugeProgressMigrationV213'] = true;
    }
    final individuals = normalized['individuals'] as Map?;
    individuals?.forEach((_, raw) {
      if (raw is Map) {
        final care = raw.putIfAbsent('care', () => <String, dynamic>{}) as Map;
        if (normalized['satietyV22Migration'] != true &&
            care['satiety'] is! num) {
          final lastMeal = (care['lastMealAt'] as num?)?.toInt();
          final savedAt =
              (normalized['savedAt'] as num?)?.toInt() ?? lastMeal ?? 0;
          // V1 only knew the time of the last meal. Preserve a recently fed
          // resident comfortably, while old/unknown meals become hungry but
          // never arrive at an arbitrary zero on upgrade.
          final elapsedHours = lastMeal == null
              ? 0
              : max(0, savedAt - lastMeal) ~/
                  const Duration(hours: 1).inMilliseconds;
          care['satiety'] = lastMeal == null
              ? 100
              : elapsedHours <= 24
                  ? 100
                  : elapsedHours <= 72
                      ? 70
                      : 50;
          care['satietyUpdatedAt'] = savedAt;
        }
        raw.putIfAbsent('observationJournal',
            () => <String, dynamic>{'observations': <String, dynamic>{}});
        raw.putIfAbsent(
            'wellbeing',
            () => <String, dynamic>{
                  'value': 60,
                  'lastUpdatedAt': normalized['savedAt'] ?? 0,
                });
        raw.putIfAbsent('activeRequest', () => null);
        raw.putIfAbsent('communicationCounts', () => <String, int>{});
        raw.putIfAbsent('conceptExposures', () => <String, dynamic>{});
        raw.putIfAbsent('decorPreferences', () => <String, dynamic>{});
        raw.putIfAbsent(
            'sleep',
            () => <String, dynamic>{
                  'awakeUntil': 0,
                  'wakeCount': 0,
                  'lastWakeAt': null,
                });
        final sleep = raw['sleep'] as Map?;
        sleep?.putIfAbsent('dayNapUntil', () => 0);
        sleep?.putIfAbsent('dayNapZoneId', () => null);
        sleep?.putIfAbsent('lastDayNapAt', () => 0);
        // Existing residents have already completed their introduction. New
        // adoptions set this explicitly to true below.
        raw.putIfAbsent('onboardingAwakeLock', () => false);
        raw.putIfAbsent('onboardingSleepAllowedAt', () => 0);
        raw.putIfAbsent('environmentalMemory',
            () => <String, dynamic>{'temporaryRejectedZones': <String>[]});
        final journal = raw['observationJournal'] as Map?;
        journal?.putIfAbsent('knowledge', () => <String, dynamic>{});
        raw.putIfAbsent(
            'professions',
            () => <String, dynamic>{
                  'TRACKER': <String, dynamic>{
                    'professionId': 'TRACKER',
                    'xp': 0,
                    'level': 0,
                  },
                });
        raw.putIfAbsent(
            'explorationStamina',
            () => <String, dynamic>{
                  'current': 10,
                  'lastUpdatedAt': normalized['savedAt'] ?? 0,
                });
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
    normalized['satietyV22Migration'] = true;
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

void _normalizeLegacyAlgae(Object? value) {
  if (value is Map) {
    final legacy = value.remove('ALGAE_FRAGMENT');
    if (legacy != null) {
      if (legacy is num && value['ALGAE'] is num) {
        value['ALGAE'] = (value['ALGAE'] as num).toInt() + legacy.toInt();
      } else if (legacy is num) {
        value['ALGAE'] = legacy.toInt();
      } else if (!value.containsKey('ALGAE')) {
        value['ALGAE'] = legacy;
      }
    }
    for (final entry in value.entries.toList()) {
      if (entry.value == 'ALGAE_FRAGMENT') {
        value[entry.key] = 'ALGAE';
      } else {
        _normalizeLegacyAlgae(entry.value);
      }
    }
  } else if (value is List) {
    for (var index = 0; index < value.length; index++) {
      if (value[index] == 'ALGAE_FRAGMENT') {
        value[index] = 'ALGAE';
      } else {
        _normalizeLegacyAlgae(value[index]);
      }
    }
  }
}

void _normalizeLegacyGeothermal(Object? value) {
  if (value is Map) {
    for (final entry in value.entries.toList()) {
      if (entry.value == 'TROU_GEOTHERMIQUE_CHAUD') {
        value[entry.key] = 'FOUR_BIO_ORGANIQUE';
      } else {
        _normalizeLegacyGeothermal(entry.value);
      }
    }
  } else if (value is List) {
    for (final entry in value) {
      _normalizeLegacyGeothermal(entry);
    }
  }
}

class ElevageDomain {
  static const List<String> foodItems = <String>[
    'ROOT',
    'LEAF',
    'MOSS',
    'ALGAE',
    'MUSHROOM',
    'FRUIT',
    'COOKED_MEAL',
  ];
  static const List<String> treatItems = <String>[
    'FIBROUS_FRUIT',
    'FRUIT_JELLY',
  ];
  static const List<String> structuralItems = <String>[
    'IRON',
    'LIMESTONE',
    'QUARTZ',
    'SEED',
    'SPORE',
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
    'LIMESTONE',
    'QUARTZ',
    'IRON',
  ];

  /// Fixed Exploration V2 sectors. They are data, not procedural nodes: a
  /// save persists only mutable ecology/discovery while the dashboard may
  /// override every numeric rule and loot entry through this schema later.
  static const List<Map<String, dynamic>> explorationSectors =
      <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'FORET_HUMIDE_LISIERE',
      'biomeId': 'FORET_HUMIDE',
      'label': 'Lisière',
      'organic': 30,
      'mineral': 30,
      'lootTable': <Map<String, dynamic>>[
        <String, dynamic>{
          'resourceId': 'ORGANIC',
          'weight': 4,
          'resourceCategory': 'GENERIC_ORGANIC'
        },
        <String, dynamic>{
          'resourceId': 'ROOT',
          'weight': 3,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'LEAF',
          'weight': 3,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'MINERAL',
          'weight': 2,
          'resourceCategory': 'GENERIC_MINERAL'
        },
      ],
    },
    <String, dynamic>{
      'id': 'FORET_HUMIDE_SOUS_BOIS',
      'biomeId': 'FORET_HUMIDE',
      'label': 'Sous-bois',
      'organic': 40,
      'mineral': 20,
      'lootTable': <Map<String, dynamic>>[
        <String, dynamic>{
          'resourceId': 'LEAF',
          'weight': 4,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'ROOT',
          'weight': 4,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'MOSS',
          'weight': 3,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'MUSHROOM',
          'weight': 3,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'MINERAL',
          'weight': 1,
          'resourceCategory': 'GENERIC_MINERAL'
        },
      ],
    },
    <String, dynamic>{
      'id': 'FORET_HUMIDE_FORET_PROFONDE',
      'biomeId': 'FORET_HUMIDE',
      'label': 'Forêt profonde',
      'organic': 50,
      'mineral': 10,
      'lootTable': <Map<String, dynamic>>[
        <String, dynamic>{
          'resourceId': 'MUSHROOM',
          'weight': 4,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'SEED',
          'weight': 3,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'SPORE',
          'weight': 3,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'MOSS',
          'weight': 3,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
      ],
    },
    <String, dynamic>{
      'id': 'LITTORAL_PLAGE',
      'biomeId': 'LITTORAL',
      'label': 'Plage',
      'organic': 5,
      'mineral': 30,
      'lootTable': <Map<String, dynamic>>[
        <String, dynamic>{
          'resourceId': 'MINERAL',
          'weight': 4,
          'resourceCategory': 'GENERIC_MINERAL'
        },
        <String, dynamic>{
          'resourceId': 'SALT',
          'weight': 3,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'LIMESTONE',
          'weight': 2,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'ALGAE',
          'weight': 1,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
      ],
    },
    <String, dynamic>{
      'id': 'LITTORAL_DUNE',
      'biomeId': 'LITTORAL',
      'label': 'Dune',
      'organic': 10,
      'mineral': 40,
      'lootTable': <Map<String, dynamic>>[
        <String, dynamic>{
          'resourceId': 'SALT',
          'weight': 5,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'MINERAL',
          'weight': 4,
          'resourceCategory': 'GENERIC_MINERAL'
        },
        <String, dynamic>{
          'resourceId': 'QUARTZ',
          'weight': 2,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'ALGAE',
          'weight': 1,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
      ],
    },
    <String, dynamic>{
      'id': 'LITTORAL_CRIQUE',
      'biomeId': 'LITTORAL',
      'label': 'Crique',
      'organic': 25,
      'mineral': 70,
      'lootTable': <Map<String, dynamic>>[
        <String, dynamic>{
          'resourceId': 'ALGAE',
          'weight': 4,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'SALT',
          'weight': 4,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'LIMESTONE',
          'weight': 3,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'MINERAL',
          'weight': 3,
          'resourceCategory': 'GENERIC_MINERAL'
        },
      ],
    },
    <String, dynamic>{
      'id': 'COLLINE_PLATEAU',
      'biomeId': 'COLLINE',
      'label': 'Plateau',
      'organic': 20,
      'mineral': 40,
      'lootTable': <Map<String, dynamic>>[
        <String, dynamic>{
          'resourceId': 'MINERAL',
          'weight': 4,
          'resourceCategory': 'GENERIC_MINERAL'
        },
        <String, dynamic>{
          'resourceId': 'IRON',
          'weight': 3,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'LIMESTONE',
          'weight': 3,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'ROOT',
          'weight': 1,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
      ],
    },
    <String, dynamic>{
      'id': 'COLLINE_GROTTE',
      'biomeId': 'COLLINE',
      'label': 'Grotte',
      'organic': 20,
      'mineral': 100,
      'lootTable': <Map<String, dynamic>>[
        <String, dynamic>{
          'resourceId': 'IRON',
          'weight': 5,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'QUARTZ',
          'weight': 4,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'LIMESTONE',
          'weight': 4,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'MINERAL',
          'weight': 2,
          'resourceCategory': 'GENERIC_MINERAL'
        },
      ],
    },
    <String, dynamic>{
      'id': 'COLLINE_SOMMET',
      'biomeId': 'COLLINE',
      'label': 'Sommet',
      'organic': 30,
      'mineral': 30,
      'lootTable': <Map<String, dynamic>>[
        <String, dynamic>{
          'resourceId': 'MINERAL',
          'weight': 3,
          'resourceCategory': 'GENERIC_MINERAL'
        },
        <String, dynamic>{
          'resourceId': 'QUARTZ',
          'weight': 3,
          'resourceCategory': 'MINERAL_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'MOSS',
          'weight': 2,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
        <String, dynamic>{
          'resourceId': 'LEAF',
          'weight': 2,
          'resourceCategory': 'ORGANIC_SPECIFIC'
        },
      ],
    },
  ];

  /// Free resources that can physically exist in an Alcôve. Seeds and spores
  /// are now inspectable by Babies and structurally usable from Intermediate.
  static const Set<String> placeableSceneItems = <String>{
    'ROOT',
    'LEAF',
    'MOSS',
    'ALGAE',
    'MUSHROOM',
    'FRUIT',
    'FIBROUS_FRUIT',
    'FRUIT_JELLY',
    'IRON',
    'LIMESTONE',
    'QUARTZ',
    'SEED',
    'SPORE',
    'COOKED_MEAL',
  };

  static List<String> structuralResourcesForFamily(String family) =>
      switch (family) {
        'VEGETAL' => const <String>['SEED'],
        'FUNGAL' => const <String>['SPORE'],
        _ => const <String>['IRON', 'LIMESTONE', 'QUARTZ'],
      };

  static List<String> accessibleFoodPool(Map individual, ElevageConfig config) {
    final family = individual['family'] as String? ?? 'MINERAL';
    final stage =
        (individual['lifecycle'] as Map?)?['stage'] as String? ?? 'BABY';
    if (stage == 'MATURE') {
      return config.foodPool(family, 'matureCompatibleFoodPool');
    }
    final pool = <String>[...config.foodPool(family, 'babyFoodPool')];
    if (stage == 'INTERMEDIATE') {
      pool.addAll(config.foodPool(family, 'intermediateFoodUnlocks'));
    }
    return pool.toSet().toList(growable: false);
  }

  static bool canEat(Map individual, String itemId, ElevageConfig config) =>
      treatItems.contains(itemId) ||
      accessibleFoodPool(individual, config).contains(itemId);

  static bool isFutureCompatibleFood(
          Map individual, String itemId, ElevageConfig config) =>
      config
          .foodPool(individual['family'] as String? ?? 'MINERAL',
              'matureCompatibleFoodPool')
          .contains(itemId) &&
      !canEat(individual, itemId, config);

  static bool canAbsorb(Map individual, String itemId, ElevageConfig config) {
    final stage =
        (individual['lifecycle'] as Map?)?['stage'] as String? ?? 'BABY';
    return config.stageAbility(stage, 'canAbsorb', stage != 'BABY') &&
        structuralResourcesForFamily(
                individual['family'] as String? ?? 'MINERAL')
            .contains(itemId);
  }

  static bool canResonate(Map individual, ElevageConfig config) {
    final stage =
        (individual['lifecycle'] as Map?)?['stage'] as String? ?? 'BABY';
    return config.stageAbility(stage, 'canResonate', stage != 'BABY');
  }

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
  /// Chaque couple est une fraction du cycle [0–1] construite depuis les
  /// durées du Dashboard, et non plus depuis des fractions codées en dur.
  static List<List<double>> sleepWindows(Map individual,
      [ElevageConfig config = defaultElevageConfig]) {
    final cycleMinutes = config.dayNightCycleHours * 60;
    final dayMinutes = config.dayDurationHours * 60;

    List<double> endingAtCycle(int duration) => <double>[
          (cycleMinutes - duration) / cycleMinutes,
          1,
        ];
    List<double> startingAtCycleStart(int duration) =>
        <double>[0, duration / cycleMinutes];
    List<double> centredAt(int centre, int duration) {
      final safeDuration = duration.clamp(1, cycleMinutes).toDouble();
      final start = (centre - safeDuration / 2)
          .clamp(0.0, cycleMinutes - safeDuration)
          .toDouble();
      return <double>[
        start / cycleMinutes,
        (start + safeDuration) / cycleMinutes
      ];
    }

    return switch (circadianProfile(individual)) {
      // Le Végétal dort à la fin du cycle : sa fenêtre reste nocturne tant que
      // sa durée ne dépasse pas la nuit configurée.
      'DIURNAL' => <List<double>>[
          endingAtCycle(config.vegetalSleepMinutes),
        ],
      // Le Fongique conserve son sommeil polyphasique, centré sur le milieu
      // du jour puis sur la transition Jour/Nuit.
      'BIPHASIC' => <List<double>>[
          centredAt(dayMinutes ~/ 2, config.fungalMidDaySleepMinutes),
          centredAt(dayMinutes, config.fungalTransitionSleepMinutes),
        ],
      // Résonance dort en fin de nuit puis au début du jour. Les deux durées
      // sont indépendantes afin que les testeurs puissent régler précisément
      // l'heure de réveil sans modifier le cycle de l'Alcôve.
      _ => <List<double>>[
          startingAtCycleStart(config.mineralDaySleepMinutes),
          endingAtCycle(config.mineralLateNightSleepMinutes),
        ],
    };
  }

  static bool isSleeping(Map individual, int now, ElevageConfig config) {
    final sleep = individual['sleep'] as Map?;
    // A voluntary daytime nap is independent from the onboarding lock, which
    // only suppresses the biological main sleep on an arrival night.
    if ((sleep?['dayNapUntil'] as num? ?? 0).toInt() > now) return true;
    if (individual['onboardingAwakeLock'] == true &&
        now <
            ((individual['onboardingSleepAllowedAt'] as num?)?.toInt() ?? 0)) {
      return false;
    }
    if ((sleep?['awakeUntil'] as num? ?? 0).toInt() > now) return false;
    final cycleMs =
        config.dayNightCycleHours * const Duration(hours: 1).inMilliseconds;
    final position = (now % cycleMs) / cycleMs;
    return sleepWindows(individual, config)
        .any((window) => position >= window[0] && position < window[1]);
  }

  static String sleepZone(
      ElevageSave state, String individualId, int now, ElevageConfig config,
      {String? phaseOverride}) {
    final individual = _individual(state, individualId);
    final sleep = individual['sleep'] as Map?;
    if ((sleep?['dayNapUntil'] as num? ?? 0).toInt() > now &&
        sleep?['dayNapZoneId'] is String) {
      return sleep!['dayNapZoneId'] as String;
    }
    return bestComfortZone(state, individual['alcoveId'] as String, config, now,
        phaseOverride: phaseOverride, individual: individual);
  }

  /// Communication stays deliberately tiny: a Baby only vocalises, while an
  /// Intermediate gradually associates a word with an already familiar cue.
  static String vocalCategoryForAction(String action) => switch (action) {
        'STRUCTURAL_ABSORB' => 'ABSORB',
        'EAT' => 'CONTENT',
        'REJECT' => 'REJECT',
        'DISCOMFORT' || 'FLEE' || 'FLEE_WITH_ITEM' => 'DISCOMFORT',
        'CUDDLE' => 'CONTENT',
        'WAKE' => 'SURPRISE',
        'INSPECT' || 'THINK' => 'CURIOSITY',
        _ => 'CALL',
      };

  static Map<String, String?> communicationExpression(
    Map individual,
    String category,
    ElevageConfig config, {
    String? precise,
    String? conceptId,
  }) {
    final vocal = config.vocalizations[category] ??
        config.vocalizations['CALL'] ??
        'Pti !';
    final stage =
        ((individual['lifecycle'] as Map)['stage'] as String?) ?? 'BABY';
    if (stage == 'BABY') return {'vocal': vocal, 'word': null};

    final genericWords = <String, String>{
      'ABSORB': 'Matière',
      'CONTENT': 'Bien',
      'REJECT': 'Non',
      'DISCOMFORT': 'Aïe',
      'SURPRISE': 'Oh',
      'CURIOSITY': 'Regarde',
      'CALL': 'Viens',
    };
    if (stage == 'MATURE') {
      return {
        'vocal': vocal,
        'word': precise ??
            config.communicationText(
                category, 'MATURE', genericWords[category] ?? vocal),
      };
    }
    final concept = conceptId ?? precise ?? category;
    final exposure =
        ((individual['conceptExposures'] as Map?)?[concept] as Map?);
    final total = (exposure?['total'] as num?)?.toInt() ?? 0;
    final baby = (exposure?['baby'] as num?)?.toInt() ?? 0;
    final threshold = baby > 0
        ? config.juvenileBabyKnownConceptWordThreshold
        : config.juvenileNewConceptWordThreshold;
    return {
      'vocal': vocal,
      'word': total >= threshold
          ? (precise ??
              config.communicationText(
                  category, 'JUVENILE', genericWords[category] ?? vocal))
          : null,
    };
  }

  static ElevageSave recordCommunication(
      ElevageSave source, String individualId, String category,
      {String? conceptId}) {
    final state = source.copy();
    final individual = _individual(state, individualId);
    final counts = individual.putIfAbsent(
        'communicationCounts', () => <String, int>{}) as Map;
    counts[category] = (counts[category] as num? ?? 0).toInt() + 1;
    _recordConceptExposure(individual, conceptId ?? category);
    return state;
  }

  /// Persisted semantic exposure. Baby memories count, but require the longer
  /// juvenile threshold so metamorphosis never grants a free vocabulary.
  static ElevageSave recordConceptExposure(
      ElevageSave source, String individualId, String conceptId) {
    final state = source.copy();
    _recordConceptExposure(_individual(state, individualId), conceptId);
    return state;
  }

  static int bubbleDurationSeconds(String action, ElevageConfig config) =>
      action == 'STRUCTURAL_ABSORB'
          ? config.absorptionBubbleSeconds
          : config.reactionBubbleSeconds;

  /// A new stimulus shortens, but never cancels, an interruptible action.
  static int interruptedRemainingMs(
    Map individual,
    int remainingMs, {
    required String eventType,
  }) {
    final stage =
        ((individual['lifecycle'] as Map)['stage'] as String?) ?? 'BABY';
    final isBaby = stage == 'BABY';
    final seconds = switch (eventType) {
      'NEW_ITEM' => isBaby
          ? (personalityValue(individual, 'tempo') >= .5 ? 4 : 6)
          : (personalityValue(individual, 'tempo') >= .5 ? 2 : 3),
      'CUDDLE' => isBaby
          ? (personalityValue(individual, 'initiative') >= .5 ? 4 : 6)
          : (personalityValue(individual, 'initiative') >= .5 ? 2 : 3),
      _ => 0,
    };
    return max(0, remainingMs - seconds * 1000);
  }

  static ElevageSave wake(
      ElevageSave source, String individualId, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, individualId);
    final sleep = individual.putIfAbsent(
        'sleep',
        () => <String, dynamic>{
              'awakeUntil': 0,
              'wakeCount': 0,
              'lastWakeAt': null,
            }) as Map;
    final previousWake = (sleep['lastWakeAt'] as num?)?.toInt();
    final repeated = previousWake != null &&
        now - previousWake <
            config.dayNightCycleHours * const Duration(hours: 1).inMilliseconds;
    final posed = personalityValue(individual, 'tempo') >= .5;
    sleep['awakeUntil'] = now + config.wakeGraceSeconds * 1000;
    sleep['lastWakeAt'] = now;
    sleep['wakeCount'] = (sleep['wakeCount'] as num? ?? 0).toInt() + 1;
    _adjustWellbeing(
        individual, repeated ? (posed ? -5 : -2) : (posed ? -2 : -1), now);
    _interaction(individual, 'WAKE', tempo: posed ? -1 : 1);
    return state;
  }

  static ElevageSave adopt({
    required ElevageSave source,
    required String alcoveId,
    required String name,
    required bool physical,
    required int now,
    required ElevageConfig config,
    String? physicalFigureRef,
    String family = 'MINERAL',
    String nature = 'RESONANCE',
  }) {
    final state = source.copy();
    final alcove = _alcove(state, alcoveId);
    if (alcove['progressState'] != 'READY') {
      throw StateError('Cette Alcôve n’est pas encore construite.');
    }
    if (alcove['occupantIndividualId'] != null) {
      throw StateError('Cette Alcôve est déjà occupée.');
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 32) {
      throw StateError('Choisissez un nom entre 1 et 32 caractères.');
    }
    final ref = physicalFigureRef ?? '';
    final profile = config.natureProfile(family, nature);
    if (profile.family != family || profile.nature != nature) {
      throw StateError('Nature Élevage invalide.');
    }
    if (physical && (ref.isEmpty || _physicalAlreadyLinked(state, ref))) {
      throw StateError('Cette figurine est déjà liée à un P’TIPOTE actif.');
    }
    final seed =
        '${now}_${state.data['individuals'].length}_${cleanName.hashCode}';
    final random = Random(_hash(seed));
    final id = 'elevage-$now-${random.nextInt(99999)}';
    final favorite = random.nextBool() ? 'ROOT' : 'LEAF';
    final cycleMs =
        config.dayNightCycleHours * const Duration(hours: 1).inMilliseconds;
    final dayMs =
        config.dayDurationHours * const Duration(hours: 1).inMilliseconds;
    final cyclePosition = now % cycleMs;
    // The first night is dedicated to onboarding. A shifted mineral sleep
    // window may cross into the following day, so it is also held awake until
    // the *next* night starts.
    final onboardingSleepAllowedAt =
        now - cyclePosition + (cyclePosition < dayMs ? dayMs : cycleMs + dayMs);
    final individual = <String, dynamic>{
      'id': id,
      'name': cleanName,
      'family': family,
      'nature': nature,
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
              'sourcePoolId': profile.id,
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
      'communicationCounts': <String, int>{},
      'conceptExposures': <String, dynamic>{},
      'decorPreferences': <String, dynamic>{},
      'sleep': <String, dynamic>{
        'awakeUntil': 0,
        'wakeCount': 0,
        'lastWakeAt': null,
        'dayNapUntil': 0,
        'dayNapZoneId': null,
        'lastDayNapAt': 0,
      },
      'onboardingAwakeLock': true,
      'onboardingSleepAllowedAt': onboardingSleepAllowedAt,
      'environmentalMemory': <String, dynamic>{
        'temporaryRejectedZones': <String>[],
        'favoriteZone': null,
        'lastKnownSafeZone': null,
      },
      'professions': <String, dynamic>{
        'TRACKER': <String, dynamic>{
          'professionId': 'TRACKER',
          'xp': 0,
          'level': 0,
        },
      },
      'explorationStamina': <String, dynamic>{
        'current': config.explorationInt('ptipoteStaminaMax', 10),
        'lastUpdatedAt': now,
      },
      'social': <String, dynamic>{
        'cuddleCooldownUntil': 0,
        'cuddleAttempts': 0,
        'lastReaction': 'NEUTRAL',
      },
      'care': <String, dynamic>{
        'lastMealAt': null,
        'satiety': config.initialSatiety,
        'satietyUpdatedAt': now,
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
        'knowledge': <String, dynamic>{},
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
    _applyTrustChange(state,
        amount: config.trustGainAdoption,
        now: now,
        reasonType: 'ADOPTION',
        ptipoteId: id,
        text: _trustText('ADOPTION', cleanName),
        eventId: 'adoption-$id');
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
              'progressState': index <
                      (config.devMode &&
                              config.preset == ElevagePreset.prototype
                          ? config.alcoveCount
                          : config.startingAlcoveCount)
                  ? 'READY'
                  : 'LOCKED',
              'batterySlot': null,
              'biogeneratorSlot': null,
              'localEnergy': 0,
              'slots': List<dynamic>.filled(config.installationSlotCount, null),
              'createdAt': now,
            });
    state.data['individuals'] = <String, dynamic>{};
    state.data['activeIndividualIds'] = <String>[];
    state.data['installationInventory'] = <String, dynamic>{};
    state.data['habitatInventory'] = <String, dynamic>{};
    state.data['habitatItemsByAlcoveId'] = <String, dynamic>{};
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
      final current = refreshSatiety(individual, now, config);
      setSatiety(individual, current + config.foodSatietyValue(item), now);
      _memory(state, id, 'FIRST_TREAT', now);
      _interaction(individual, 'TREAT', contact: 1);
      _adjustWellbeing(individual, 2, now);
      return state;
    }
    if (!canEat(individual, item, config)) {
      throw StateError('Cet aliment n’est pas encore accessible à ce stade.');
    }
    if (!canOfferNormalFood(state, id, now, config)) {
      throw StateError('P’TIPOTE n’a pas faim.');
    }
    special[item] = special[item]! - 1;
    final care = individual['care'] as Map<String, dynamic>;
    final current = refreshSatiety(individual, now, config);
    setSatiety(individual, current + config.foodSatietyValue(item), now);
    // Kept as an audit field for legacy saves only. Satiety V2 never reads it.
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

  static Map<String, dynamic> cookerState(ElevageSave state) {
    final raw = state.data['cooker'];
    if (raw is Map<String, dynamic>) return raw;
    final normalized = Map<String, dynamic>.from(raw as Map? ?? const {});
    state.data['cooker'] = normalized;
    return normalized;
  }

  static bool cookerInstalled(ElevageSave state) =>
      cookerState(state)['installed'] == true;

  static int cookingHeat(ElevageSave state, ElevageConfig config) =>
      ((cookerState(state)['cookingHeat'] as num?)?.toInt() ?? 0)
          .clamp(0, config.cookerHeatMax);

  static List<Map<String, dynamic>> cookedMealPortions(ElevageSave state) =>
      (state.data['cookedMealInventory'] as Map)
          .values
          .whereType<Map>()
          .map((meal) => Map<String, dynamic>.from(meal))
          .toList(growable: false);

  // Compatibility alias for the V1 sheet while callers migrate to portions.
  static List<Map<String, dynamic>> cookedMeals(ElevageSave state) =>
      cookedMealPortions(state);

  static String cookingRecipeKey(List<String> ingredients, bool usedWater) {
    final canonical = List<String>.from(ingredients)..sort();
    return '${canonical.join('+')}|water:${usedWater ? 1 : 0}';
  }

  static Map<String, dynamic> cookingPreview(
      List<String> ingredients, bool usedWater, ElevageConfig config) {
    if (ingredients.isEmpty ||
        ingredients.any((item) => config.foodSatietyValue(item) <= 0)) {
      throw StateError('Choisissez au moins un ingrédient alimentaire.');
    }
    if (ingredients.length > config.maxFoodIngredients) {
      throw StateError('Trop d’ingrédients alimentaires.');
    }
    final elements =
        ingredients.length + (usedWater && config.waterCountsAsElement ? 1 : 0);
    if (elements < config.minRecipeElements) {
      throw StateError('Choisissez au moins deux éléments.');
    }
    final average = ingredients
            .map(config.foodSatietyValue)
            .reduce((value, next) => value + next) /
        ingredients.length;
    final perPortion = average +
        (usedWater ? config.wetBonusPerPortion : config.dryBonusPerPortion);
    return <String, dynamic>{
      'recipeKey': cookingRecipeKey(ingredients, usedWater),
      'portionCount': elements,
      'satietyPerPortion': perPortion,
      'batchSatiety': perPortion * elements,
      'heatCost': elements * config.cookerHeatCostPerPortion,
    };
  }

  static ElevageSave craftCooker(
      ElevageSave source, int now, ElevageConfig config) {
    final state = source.copy();
    final cooker = cookerState(state);
    if (cooker['crafted'] == true) {
      throw StateError('La Cuisinière est déjà fabriquée.');
    }
    final recipe = config.cookerBuildRecipe;
    final organic = (recipe['organic'] as num?)?.toInt() ?? 0;
    final mineral = (recipe['mineral'] as num?)?.toInt() ?? 0;
    final special = Map<String, dynamic>.from(
        recipe['special'] as Map? ?? const <dynamic, dynamic>{});
    final generic = _generic(state);
    final reserve = _special(state);
    if ((generic['organic'] ?? 0) < organic ||
        (generic['mineral'] ?? 0) < mineral ||
        special.entries.any((entry) =>
            (reserve[entry.key] ?? 0) < (entry.value as num).toInt())) {
      throw StateError('Ressources insuffisantes pour la Cuisinière.');
    }
    generic['organic'] = generic['organic']! - organic;
    generic['mineral'] = generic['mineral']! - mineral;
    special.forEach(
        (key, value) => reserve[key] = reserve[key]! - (value as num).toInt());
    cooker['crafted'] = true;
    cooker['infrastructureId'] = 'COOKER';
    cooker['craftedAt'] = now;
    return state;
  }

  static ElevageSave installCooker(ElevageSave source, int now) {
    final state = source.copy();
    final cooker = cookerState(state);
    if (cooker['crafted'] != true) {
      throw StateError('Fabriquez d’abord la Cuisinière.');
    }
    cooker['installed'] = true;
    cooker['installedAt'] = now;
    return state;
  }

  static ElevageSave rechargeCooker(
      ElevageSave source, String alcoveId, int now, ElevageConfig config) {
    final state = source.copy();
    final cooker = cookerState(state);
    if (cooker['installed'] != true) throw StateError('Cuisinière absente.');
    final heat = cookingHeat(state, config);
    if (heat >= config.cookerHeatMax) {
      throw StateError('La Cuisinière est déjà chaude.');
    }
    final alcove = _alcove(state, alcoveId);
    final energy = (alcove['localEnergy'] as num?)?.toInt() ?? 0;
    if (energy < config.cookerEnergyCostPerRecharge) {
      throw StateError('Énergie locale insuffisante.');
    }
    alcove['localEnergy'] = energy - config.cookerEnergyCostPerRecharge;
    cooker['cookingHeat'] =
        min(config.cookerHeatMax, heat + config.cookerHeatPerEnergy);
    cooker['lastChargedAt'] = now;
    return state;
  }

  static double waterTank(ElevageSave state) =>
      ((state.data['waterTank'] as num?)?.toDouble() ?? 0)
          .clamp(0, double.infinity);

  static ElevageSave cookMeal(ElevageSave source, List<String> ingredients,
      bool usedWater, int now, ElevageConfig config,
      {String? recipeName}) {
    final state = refreshWeather(source, now, config);
    if (!cookerInstalled(state)) throw StateError('Cuisinière non installée.');
    final preview = cookingPreview(ingredients, usedWater, config);
    final special = _special(state);
    final required = <String, int>{};
    for (final item in ingredients) {
      required[item] = (required[item] ?? 0) + 1;
    }
    if (required.entries
        .any((entry) => (special[entry.key] ?? 0) < entry.value)) {
      throw StateError('Ingrédients insuffisants.');
    }
    final waterCost = usedWater ? config.waterCostPerWetRecipe : 0;
    if (waterTank(state) < waterCost) throw StateError('Eau insuffisante.');
    required.forEach((item, count) => special[item] = special[item]! - count);
    state.data['waterTank'] = (waterTank(state) - waterCost)
        .clamp(0, config.waterTankCapacity)
        .toDouble();
    final heatCost = preview['heatCost'] as int;
    final cooker = cookerState(state);
    final heat = cookingHeat(state, config);
    if (heat < heatCost) throw StateError('Chaleur insuffisante.');
    cooker['cookingHeat'] = heat - heatCost;
    final recipeKey = preview['recipeKey'] as String;
    final recipes = state.data['knownCookingRecipes'] as Map<String, dynamic>;
    final known = recipes[recipeKey] as Map?;
    final name = (known?['customName'] as String?)?.trim().isNotEmpty == true
        ? known!['customName'] as String
        : (recipeName?.trim().isNotEmpty == true
            ? recipeName!.trim()
            : 'Nouvelle recette');
    recipes.putIfAbsent(
        recipeKey,
        () => <String, dynamic>{
              'recipeKey': recipeKey,
              'customName': name,
              'ingredientIds': List<String>.from(ingredients),
              'usedWater': usedWater,
              'createdAt': now,
            });
    final portions = preview['portionCount'] as int;
    final batchId = 'cooked-batch-$now-${recipes.length}';
    final inventory = state.data['cookedMealInventory'] as Map<String, dynamic>;
    for (var index = 0; index < portions; index++) {
      final id = '$batchId-$index';
      inventory[id] = <String, dynamic>{
        'instanceId': id,
        'itemId': 'COOKED_MEAL',
        'recipeKey': recipeKey,
        'recipeName': name,
        'ingredientIds': List<String>.from(ingredients),
        'usedWater': usedWater,
        'satietyValue': preview['satietyPerPortion'],
        'createdAt': now,
        'batchId': batchId,
      };
    }
    return state;
  }

  static ElevageSave offerCookedMeal(ElevageSave source, String id,
      String mealId, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, id);
    final meals = state.data['cookedMealInventory'] as Map<String, dynamic>;
    final meal = meals[mealId] as Map?;
    if (meal == null) {
      throw StateError('Cette préparation est épuisée.');
    }
    final ingredients = (meal['ingredientIds'] as List).cast<String>();
    if (ingredients.any((item) => !canEat(individual, item, config))) {
      throw StateError(
          'Cette préparation contient un aliment non accessible à ce stade.');
    }
    if (!canOfferNormalFood(state, id, now, config)) {
      throw StateError('P’TIPOTE n’a pas faim.');
    }
    final satiety = (meal['satietyValue'] as num?)?.toDouble() ?? 0;
    setSatiety(
        individual, refreshSatiety(individual, now, config) + satiety, now);
    meals.remove(mealId);
    return state;
  }

  static ElevageSave offerStructural(
      ElevageSave source, String id, String item, int now,
      [ElevageConfig? config]) {
    final state = source.copy();
    final individual = _individual(state, id);
    final resolvedConfig = config ?? defaultElevageConfig;
    if (!canAbsorb(individual, item, resolvedConfig)) {
      throw StateError('Cette ressource ne peut pas encore être absorbée.');
    }
    final gains = <String, int>{
      'IRON': 2,
      'LIMESTONE': 1,
      'QUARTZ': 1,
      'SEED': 1,
      'SPORE': 1,
    };
    final gain = gains[item];
    if (gain == null) throw StateError('Matériau inconnu.');
    final special = _special(state);
    if ((special[item] ?? 0) < 1) throw StateError('Matériau non disponible.');
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
        relatedItemId: item, config: resolvedConfig);
    _setObservationStatus(
        individual, 'STRUCTURAL_REACTION:$item', count, resolvedConfig, now);
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
      'ALGAE',
      'SALT'
    ]) {
      special[item] = (special[item] ?? 0) + 3;
    }
    final generic = _generic(state);
    generic['organic'] = (generic['organic'] ?? 0) + 30;
    generic['mineral'] = (generic['mineral'] ?? 0) + 30;
    state.data['inventory']['bioPiles'] =
        (state.data['inventory']['bioPiles'] as int) + 10;
    final batteries = _batteryInventory(state);
    final batteryId = 'battery-dev-${DateTime.now().microsecondsSinceEpoch}';
    batteries[batteryId] = <String, dynamic>{
      'instanceId': batteryId,
      'itemId': 'BIO_BATTERY',
      'currentEnergy': 10,
      'maxEnergy': 10,
    };
    return state;
  }

  /// Canonical Refuge progression value. `contribution` remains an alias only
  /// so existing saves and older debug calls stay valid after Lot 22.4.
  static int trust(ElevageSave state) {
    final progress = state.data['refugeProgress'] as Map?;
    return ((progress?['trust'] ?? progress?['contribution']) as num?)
            ?.toInt() ??
        0;
  }

  static int contribution(ElevageSave state) => trust(state);

  static List<Map<String, dynamic>> trustHistory(ElevageSave state) {
    final history =
        ((state.data['refugeProgress'] as Map?)?['trustHistory'] as List?) ??
            const <dynamic>[];
    return history
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  static ElevageSave addTrust(ElevageSave source, int amount,
      {required int now,
      String reasonType = 'DEBUG',
      String? ptipoteId,
      String? text,
      String? eventId}) {
    final state = source.copy();
    _applyTrustChange(state,
        amount: amount,
        now: now,
        reasonType: reasonType,
        ptipoteId: ptipoteId,
        text: text,
        eventId: eventId);
    return state;
  }

  static ElevageSave setTrust(ElevageSave source, int value,
      {required int now}) {
    final state = source.copy();
    final progress = _refugeProgress(state);
    final next = max(0, value);
    final delta = next - trust(state);
    progress['trust'] = next;
    // Keep the old field synchronized for integrations that have not yet
    // moved to the new name. Setting debug value is intentionally visible.
    progress['contribution'] = next;
    if (delta != 0) {
      _appendTrustHistory(progress,
          timestamp: now,
          delta: delta,
          reasonType: 'DEBUG_SET',
          text: 'Confiance réglée en mode développement');
    }
    return state;
  }

  /// Dashboard-only shortcut for validating the individual 24-hour rule. It
  /// creates a real completed critical period, then uses the normal refresh
  /// path rather than bypassing the penalty ledger.
  static ElevageSave simulateCriticalWellbeingTrustPeriod(
      ElevageSave source, String individualId, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, individualId);
    final duration = config.criticalWellbeingPenaltyHours *
        const Duration(hours: 1).inMilliseconds;
    final wellbeing =
        individual.putIfAbsent('wellbeing', () => <String, dynamic>{}) as Map;
    wellbeing['value'] = max(0, config.criticalWellbeingThreshold - 1);
    individual['criticalWellbeingSince'] = now - duration;
    individual['lastCriticalWellbeingTrustPenaltyAt'] = now - duration;
    return refreshRefugeProgress(state, now, config);
  }

  static ElevageSave addContribution(ElevageSave source, int amount) =>
      addTrust(source, amount,
          now: DateTime.now().millisecondsSinceEpoch, reasonType: 'DEBUG');

  static ElevageSave setContribution(ElevageSave source, int value) =>
      setTrust(source, value, now: DateTime.now().millisecondsSinceEpoch);

  static String alcoveProgressState(
      ElevageSave state, String alcoveId, ElevageConfig config, int now) {
    final alcove = _alcove(state, alcoveId);
    final status = alcove['progressState'] as String? ?? 'READY';
    if (status == 'UNDER_CONSTRUCTION') {
      final due =
          ((alcove['construction'] as Map?)?['readyAt'] as num?)?.toInt() ??
              now + 1;
      if (now >= due) return 'READY';
      return status;
    }
    if (status == 'LOCKED') {
      final index = (state.data['alcoves'] as List).indexOf(alcove) + 1;
      final required =
          (config.requirementForAlcove(index)['requiredContribution'] as num?)
                  ?.toInt() ??
              0;
      return trust(state) >= required ? 'AVAILABLE_TO_BUILD' : status;
    }
    return status;
  }

  static ElevageSave refreshRefugeProgress(
      ElevageSave source, int now, ElevageConfig config) {
    final state = source.copy();
    for (final raw in state.data['alcoves'] as List) {
      final alcove = raw as Map<String, dynamic>;
      final status =
          alcoveProgressState(state, alcove['id'] as String, config, now);
      if (status == 'READY') {
        alcove['progressState'] = 'READY';
        alcove.remove('construction');
      } else if (status == 'AVAILABLE_TO_BUILD') {
        alcove['progressState'] = 'AVAILABLE_TO_BUILD';
      }
    }
    _flushPendingTrustEvents(state, now, config);
    _applyCriticalWellbeingTrustPenalties(state, now, config);
    _processLoanReturns(state, now);
    return state;
  }

  static ElevageSave startAlcoveConstruction(ElevageSave source,
      String alcoveId, String route, int now, ElevageConfig config) {
    final state = refreshRefugeProgress(source, now, config);
    final alcove = _alcove(state, alcoveId);
    if (alcove['progressState'] != 'AVAILABLE_TO_BUILD') {
      throw StateError('Cette Alcôve n’est pas encore disponible.');
    }
    final index = (state.data['alcoves'] as List).indexOf(alcove) + 1;
    final requirement = config.requirementForAlcove(index);
    final bioPiles = state.data['inventory']['bioPiles'] as int;
    final isTurnkey = route == 'TURNKEY';
    final biopileCost =
        (requirement[isTurnkey ? 'turnkeyBiopileCost' : 'assistedBiopileCost']
                    as num?)
                ?.toInt() ??
            0;
    if (bioPiles < biopileCost) throw StateError('Bio-piles insuffisantes.');
    final generic = _generic(state);
    final assisted = isTurnkey
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(
            requirement['assistedResourceCosts'] as Map? ??
                const <dynamic, dynamic>{});
    if (assisted.entries.any((entry) =>
        (generic[entry.key.toLowerCase()] ?? 0) <
        (entry.value as num).toInt())) {
      throw StateError('Ressources insuffisantes pour le chantier.');
    }
    state.data['inventory']['bioPiles'] = bioPiles - biopileCost;
    assisted.forEach((key, value) {
      final resource = key.toLowerCase();
      generic[resource] = generic[resource]! - (value as num).toInt();
    });
    final duration =
        (requirement['constructionDurationSeconds'] as num?)?.toInt() ?? 0;
    alcove['progressState'] = 'UNDER_CONSTRUCTION';
    alcove['construction'] = <String, dynamic>{
      'route': isTurnkey ? 'TURNKEY' : 'ASSISTED',
      'startedAt': now,
      'readyAt': now + duration * 1000,
    };
    return state;
  }

  static ElevageSave craftBioBattery(
      ElevageSave source, int now, ElevageConfig config) {
    throw StateError('Les Bio-batteries sont fournies par le Refuge.');
  }

  static ElevageSave craftBatteryExport(
      ElevageSave source, String alcoveId, int now, ElevageConfig config) {
    final state = source.copy();
    final recipe = Map<String, dynamic>.from(
        config.refugeProgression['batteryExport'] as Map? ??
            const <dynamic, dynamic>{});
    final organic = (recipe['organic'] as num?)?.toInt() ?? 1;
    final mineral = (recipe['mineral'] as num?)?.toInt() ?? 1;
    final energy = (recipe['energy'] as num?)?.toInt() ?? 100;
    final generic = _generic(state);
    final alcove = _alcove(state, alcoveId);
    final local = (alcove['localEnergy'] as num?)?.toInt() ?? 0;
    if ((generic['organic'] ?? 0) < organic ||
        (generic['mineral'] ?? 0) < mineral ||
        local < energy) {
      throw StateError('Ressources ou énergie insuffisantes.');
    }
    generic['organic'] = generic['organic']! - organic;
    generic['mineral'] = generic['mineral']! - mineral;
    alcove['localEnergy'] = local - energy;
    final special = _special(state);
    special['BATTERY_EXPORT'] = (special['BATTERY_EXPORT'] ?? 0) + 1;
    return state;
  }

  static ElevageSave insertBattery(
      ElevageSave source, String alcoveId, String batteryInstanceId, int now) {
    final state = source.copy();
    final alcove = _alcove(state, alcoveId);
    final batteries = _batteryInventory(state);
    final battery = batteries.remove(batteryInstanceId);
    if (battery == null) throw StateError('Bio-pile non disponible.');
    final previous = alcove['batterySlot'];
    if (previous is Map) batteries[previous['instanceId'] as String] = previous;
    alcove['batterySlot'] = battery;
    return state;
  }

  /// The durable generator is an Alcôve technical appliance, never a Z1–Z4
  /// construction. It must first be crafted, then explicitly installed.
  static ElevageSave craftBiogenerator(
      ElevageSave source, int now, ElevageConfig config) {
    final state = source.copy();
    final recipe = Map<String, dynamic>.from(
        config.refugeProgression['biogeneratorRecipe'] as Map? ??
            const <dynamic, dynamic>{});
    final generic = _generic(state);
    final special = _special(state);
    final organic = (recipe['organic'] as num?)?.toInt() ?? 0;
    final mineral = (recipe['mineral'] as num?)?.toInt() ?? 0;
    final parts = Map<String, dynamic>.from(
        recipe['special'] as Map? ?? const <dynamic, dynamic>{});
    if ((generic['organic'] ?? 0) < organic ||
        (generic['mineral'] ?? 0) < mineral ||
        parts.entries.any((entry) =>
            (special[entry.key] ?? 0) < (entry.value as num).toInt())) {
      throw StateError('Ressources insuffisantes pour le Biogénérateur.');
    }
    generic['organic'] = generic['organic']! - organic;
    generic['mineral'] = generic['mineral']! - mineral;
    parts.forEach(
        (key, value) => special[key] = special[key]! - (value as num).toInt());
    final id = 'biogenerator-$now-${_biogeneratorInventory(state).length}';
    _biogeneratorInventory(state)[id] = _newBiogenerator(id, now);
    return state;
  }

  static ElevageSave installBiogenerator(
      ElevageSave source, String alcoveId, String instanceId, int now) {
    final state = source.copy();
    final alcove = _alcove(state, alcoveId);
    final inventory = _biogeneratorInventory(state);
    final generator = inventory.remove(instanceId);
    if (generator == null) throw StateError('Biogénérateur indisponible.');
    final previous = alcove['biogeneratorSlot'];
    if (previous is Map) {
      inventory[previous['instanceId'] as String] = previous;
    }
    alcove['biogeneratorSlot'] = generator;
    return state;
  }

  static ElevageSave transferBiogeneratorFuel(ElevageSave source,
      String alcoveId, String resourceId, int quantity, ElevageConfig config) {
    if (quantity <= 0 ||
        !const <String>{'ORGANIC', 'MINERAL'}.contains(resourceId)) {
      throw StateError('Transfert invalide.');
    }
    final state = source.copy();
    final alcove = _alcove(state, alcoveId);
    final generator = alcove['biogeneratorSlot'];
    if (generator is! Map) throw StateError('Biogénérateur absent.');
    final tanks = _generatorTanks(generator);
    final capacities = biogeneratorTankCapacities(generator, config);
    final key = resourceId.toLowerCase();
    final space = max(0, capacities[key]! - (tanks[key] ?? 0));
    if (quantity > space) throw StateError('Capacité de cuve insuffisante.');
    final generic = _generic(state);
    if ((generic[key] ?? 0) < quantity) {
      throw StateError('Réserve insuffisante.');
    }
    generic[key] = generic[key]! - quantity;
    tanks[key] = (tanks[key] ?? 0) + quantity;
    return state;
  }

  static Map<String, int> biogeneratorTankCapacities(
      Map generator, ElevageConfig config) {
    final installed = installedModules(generator, config);
    final capacityModules = installed
        .where((module) =>
            (module['definition'] as ElevageModuleDefinition?)?.category ==
            'CAPACITY')
        .length;
    return <String, int>{
      'organic': config.biogeneratorOrganicTankCapacity +
          capacityModules * config.biogeneratorCapacityOrganicBonus,
      'mineral': config.biogeneratorMineralTankCapacity +
          capacityModules * config.biogeneratorCapacityMineralBonus,
    };
  }

  static Map<String, int> biogeneratorCycleProfile(
      Map generator, ElevageConfig config) {
    final installed = installedModules(generator, config);
    final efficiency = installed.any((module) =>
        (module['definition'] as ElevageModuleDefinition?)?.category ==
        'EFFICIENCY');
    final power = installed.any((module) =>
        (module['definition'] as ElevageModuleDefinition?)?.category ==
        'POWER');
    return <String, int>{
      'organic': max(
          config.biogeneratorMinimumOrganicCost,
          config.biogeneratorOrganicCost -
              (efficiency ? config.biogeneratorEfficiencyOrganicReduction : 0)),
      'mineral': max(
          config.biogeneratorMinimumMineralCost,
          config.biogeneratorMineralCost -
              (efficiency ? config.biogeneratorEfficiencyMineralReduction : 0)),
      'energy': config.biogeneratorEnergyPerCycle +
          (power ? config.biogeneratorPowerEnergyBonus : 0),
    };
  }

  /// Progress of the durable generator's current ten-second production cycle.
  /// It deliberately lives on the installed instance so navigation and offline
  /// refreshes cannot duplicate a cycle.
  static double biogeneratorCycleProgress(
      Map generator, Map alcove, int now, ElevageConfig config) {
    final profile = biogeneratorCycleProfile(generator, config);
    final tanks = _generatorTanks(generator);
    final stored = (alcove['localEnergy'] as num?)?.toInt() ?? 0;
    if (stored >= config.energyStorageMax ||
        (tanks['organic'] ?? 0) < profile['organic']! ||
        (tanks['mineral'] ?? 0) < profile['mineral']!) {
      return 0;
    }
    final startedAt = (generator['cycleStartedAt'] as num?)?.toInt() ?? now;
    final duration =
        Duration(seconds: config.biogeneratorCycleSeconds).inMilliseconds;
    return ((now - startedAt) / duration).clamp(0, 1).toDouble();
  }

  static ElevageSave installBiogeneratorModule(ElevageSave source,
      String alcoveId, String moduleInstanceId, ElevageConfig config) {
    final state = source.copy();
    final generator = _alcove(state, alcoveId)['biogeneratorSlot'];
    if (generator is! Map) throw StateError('Biogénérateur absent.');
    final profile = config.modulesFor('BIOGENERATOR');
    final inventory = _moduleInventory(state);
    final instance = inventory[moduleInstanceId] as Map?;
    final definition = config.module(instance?['moduleId'] as String? ?? '');
    if (instance == null ||
        definition == null ||
        !definition.enabled ||
        !profile.allowedModuleIds.contains(definition.id)) {
      throw StateError('Module incompatible.');
    }
    final installed =
        generator.putIfAbsent('installedModules', () => <dynamic>[]) as List;
    if (installed.length >= profile.moduleSlots ||
        installed
            .whereType<Map>()
            .any((entry) => entry['moduleId'] == definition.id)) {
      throw StateError('Ce module ne peut plus être cumulé.');
    }
    installed.add(Map<String, dynamic>.from(instance));
    inventory.remove(moduleInstanceId);
    return state;
  }

  static ElevageSave removeBiogeneratorModule(
      ElevageSave source, String alcoveId, String moduleInstanceId) {
    final state = source.copy();
    final generator = _alcove(state, alcoveId)['biogeneratorSlot'];
    final installed =
        generator is Map ? generator['installedModules'] as List? : null;
    final index = installed?.indexWhere((entry) =>
            entry is Map && entry['instanceId'] == moduleInstanceId) ??
        -1;
    if (index < 0) throw StateError('Module absent.');
    final module = Map<String, dynamic>.from(installed!.removeAt(index) as Map);
    _moduleInventory(state)[moduleInstanceId] = module;
    return state;
  }

  static String hunger(
      ElevageSave state, String id, int now, ElevageConfig config) {
    final satiety = satietyPercent(state, id, now, config);
    if (satiety >= config.satietySatiatedThreshold) return 'SATIATED';
    if (satiety >= config.satietyHungryThreshold) return 'HUNGRY';
    return 'VERY_HUNGRY';
  }

  /// Derives the displayed value from a persisted 0–100 value and timestamp.
  /// This makes offline loss deterministic without a permanent timer.
  static double satietyPercent(
      ElevageSave state, String id, int now, ElevageConfig config) {
    return _resolvedSatiety(_individual(state, id), now, config);
  }

  static double _resolvedSatiety(
      Map individual, int now, ElevageConfig config) {
    final care = individual['care'] as Map? ?? const <dynamic, dynamic>{};
    final stored = (care['satiety'] as num?)?.toDouble() ??
        config.initialSatiety.toDouble();
    final updatedAt = (care['satietyUpdatedAt'] as num?)?.toInt() ?? now;
    final elapsed = max(0, now - updatedAt);
    final stage =
        ((individual['lifecycle'] as Map?)?['stage'] as String?) ?? 'BABY';
    final loss = elapsed *
        config.satietyLossPerHour(stage) /
        const Duration(hours: 1).inMilliseconds;
    // A point is lost only after its complete duration elapsed. Flooring the
    // final subtraction would turn 100 into 99 a millisecond after a meal.
    return (stored - loss.floor()).clamp(0, 100).toDouble();
  }

  /// Commits elapsed satiety before a meal, a stage transition or a debug
  /// edit. The timestamp ensures a new biological stage only affects future
  /// time, never the time that preceded the transition.
  static double refreshSatiety(Map individual, int now, ElevageConfig config) {
    final value = _resolvedSatiety(individual, now, config);
    final care =
        individual.putIfAbsent('care', () => <String, dynamic>{}) as Map;
    care['satiety'] = value;
    care['satietyUpdatedAt'] = now;
    return value;
  }

  static double setSatiety(Map individual, num value, int now) {
    final care =
        individual.putIfAbsent('care', () => <String, dynamic>{}) as Map;
    final clamped = value.clamp(0, 100);
    care['satiety'] = clamped;
    care['satietyUpdatedAt'] = now;
    return clamped.toDouble();
  }

  static ElevageSave setIndividualSatiety(
      ElevageSave source, String id, int value, int now) {
    final state = source.copy();
    setSatiety(_individual(state, id), value, now);
    return state;
  }

  static ElevageSave addIndividualSatiety(ElevageSave source, String id,
      int amount, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, id);
    final current = refreshSatiety(individual, now, config);
    setSatiety(individual, current + amount, now);
    return state;
  }

  /// Dashboard-only simulation using the exact same timestamp-based offline
  /// calculation as a real save.
  static ElevageSave simulateSatietyElapsedHours(
      ElevageSave source, String id, int hours, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, id);
    final care =
        individual.putIfAbsent('care', () => <String, dynamic>{}) as Map;
    care['satiety'] = refreshSatiety(individual, now, config);
    care['satietyUpdatedAt'] =
        now - max(0, hours) * const Duration(hours: 1).inMilliseconds;
    refreshSatiety(individual, now, config);
    return state;
  }

  static ElevageSave refreshSatietyState(
      ElevageSave source, int now, ElevageConfig config) {
    final state = source.copy();
    for (final individual
        in (state.data['individuals'] as Map? ?? const <dynamic, dynamic>{})
            .values
            .whereType<Map>()) {
      refreshSatiety(individual, now, config);
    }
    return state;
  }

  static bool canOfferNormalFood(
      ElevageSave state, String id, int now, ElevageConfig config) {
    return satietyPercent(state, id, now, config) < 100;
  }

  /// Hunger remains a body state. This compact presentation layer never turns
  /// it into a detailed food request: a future "veux fruit" is separate.
  static Map<String, String>? hungerExpression(
      ElevageSave state, String id, int now, ElevageConfig config) {
    final hungerState = hunger(state, id, now, config);
    if (hungerState == 'SATIATED') return null;
    final individual = _individual(state, id);
    final stage = (individual['lifecycle'] as Map)['stage'] as String;
    final cooldown = config.hungerSignalCooldown(stage, hungerState);
    if ((now ~/ 1000) % cooldown != 0) return null;
    if (stage == 'BABY') {
      return <String, String>{
        'icon': 'HUNGER',
        'voice': hungerState == 'VERY_HUNGRY' ? 'Nnh…' : 'Pti…',
      };
    }
    final exposure =
        ((individual['conceptExposures'] as Map?)?['HUNGER'] as Map?);
    final total = (exposure?['total'] as num?)?.toInt() ?? 0;
    final baby = (exposure?['baby'] as num?)?.toInt() ?? 0;
    final threshold = baby > 0
        ? config.juvenileBabyKnownConceptWordThreshold
        : config.juvenileNewConceptWordThreshold;
    if (stage == 'INTERMEDIATE') {
      final intent = hungerState == 'VERY_HUNGRY' ? 'VERY_HUNGRY' : 'HUNGER';
      return <String, String>{
        'icon': 'HUNGER',
        'voice': total >= threshold
            ? config.communicationText(intent, 'JUVENILE',
                hungerState == 'VERY_HUNGRY' ? 'faim !' : 'faim')
            : 'Pti !',
      };
    }
    final intent = hungerState == 'VERY_HUNGRY' ? 'VERY_HUNGRY' : 'HUNGER';
    return <String, String>{
      'icon': 'HUNGER',
      'voice': config.communicationText(intent, 'MATURE',
          hungerState == 'VERY_HUNGRY' ? 'J’ai très faim.' : 'J’ai faim.'),
    };
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

  /// Meubles et décorations sont des instances libres, distinctes des
  /// ressources posées et des structures techniques attachées aux slots.
  static List<Map<String, dynamic>> habitatItems(
      ElevageSave state, String alcoveId) {
    final all = state.data['habitatItemsByAlcoveId'] as Map;
    return ((all[alcoveId] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static ElevageSave placeHabitatItem(ElevageSave source, String alcoveId,
      String instanceId, String zoneId, int now, ElevageConfig config) {
    if (config.sceneZone(zoneId) == null) throw StateError('Zone invalide.');
    final state = source.copy();
    final inventory = state.data['habitatInventory'] as Map<String, dynamic>;
    final instance = inventory.remove(instanceId);
    if (instance == null) throw StateError('Objet d’habitat indisponible.');
    final definition = config.installation(instance['definitionId'] as String);
    if (definition == null || definition.category == 'STRUCTURE') {
      throw StateError('Cet objet doit être placé dans un slot Structure.');
    }
    final all = state.data['habitatItemsByAlcoveId'] as Map<String, dynamic>;
    final placed = (all.putIfAbsent(alcoveId, () => <dynamic>[]) as List);
    placed.add(<String, dynamic>{
      ...Map<String, dynamic>.from(instance),
      'zoneId': zoneId,
      'positionOrder': placed
          .whereType<Map>()
          .where((entry) => entry['zoneId'] == zoneId)
          .length,
      'placedAt': now,
      'interactionCount': 0,
      'reorganizationCooldownUntil': 0,
    });
    return state;
  }

  static ElevageSave recoverHabitatItem(
      ElevageSave source, String alcoveId, String instanceId) {
    final state = source.copy();
    final all = state.data['habitatItemsByAlcoveId'] as Map<String, dynamic>;
    final placed = (all[alcoveId] as List? ?? <dynamic>[]);
    final index = placed.indexWhere(
        (entry) => entry is Map && entry['instanceId'] == instanceId);
    if (index < 0) throw StateError('Objet d’habitat introuvable.');
    final item = Map<String, dynamic>.from(placed.removeAt(index) as Map);
    item.removeWhere((key, _) => <String>{
          'zoneId',
          'positionOrder',
          'placedAt',
          'interactionCount',
          'reorganizationCooldownUntil'
        }.contains(key));
    (state.data['habitatInventory'] as Map<String, dynamic>)[instanceId] = item;
    return state;
  }

  static bool canCarryHabitatItem(
      Map individual, ElevageInstallationDefinition definition) {
    final stage = individual['lifecycle']['stage'] as String;
    if (definition.category == 'STRUCTURE' || stage == 'BABY') return false;
    if (definition.category == 'DECORATION') return stage != 'BABY';
    return stage == 'MATURE' && definition.movableByPtipote;
  }

  static ElevageSave moveHabitatItem(
      ElevageSave source,
      String individualId,
      String alcoveId,
      String instanceId,
      String targetZoneId,
      int now,
      ElevageConfig config) {
    if (config.sceneZone(targetZoneId) == null) {
      throw StateError('Zone cible invalide.');
    }
    final state = source.copy();
    final individual = _individual(state, individualId);
    final all = state.data['habitatItemsByAlcoveId'] as Map<String, dynamic>;
    final placed = all[alcoveId] as List? ?? <dynamic>[];
    Map? item;
    for (final entry in placed.whereType<Map>()) {
      if (entry['instanceId'] == instanceId) {
        item = entry;
        break;
      }
    }
    if (item == null) throw StateError('Objet d’habitat introuvable.');
    final definition = config.installation(item['definitionId'] as String);
    if (definition == null || !canCarryHabitatItem(individual, definition)) {
      throw StateError('Cet objet ne peut pas être déplacé par ce P’TIPOTE.');
    }
    if ((item['reorganizationCooldownUntil'] as num? ?? 0).toInt() > now) {
      return state;
    }
    item['zoneId'] = targetZoneId;
    item['reorganizationCooldownUntil'] =
        now + const Duration(minutes: 10).inMilliseconds;
    item['interactionCount'] =
        (item['interactionCount'] as num? ?? 0).toInt() + 1;
    return state;
  }

  /// Returns one low-frequency decorative reorganization when an autonomous
  /// individual has already discovered that it likes the object. The caller
  /// remains responsible for rendering the pickup/carry/drop sequence.
  static Map<String, String>? nextHabitatReorganization(ElevageSave state,
      String individualId, String alcoveId, int now, ElevageConfig config,
      {String? phaseOverride}) {
    final individual = _individual(state, individualId);
    if (personalityValue(individual, 'initiative') < .5) return null;
    final preferences = individual['decorPreferences'] as Map?;
    if (preferences == null || preferences.isEmpty) return null;
    final items = habitatItems(state, alcoveId)
      ..sort((a, b) => '${a['instanceId']}'.compareTo('${b['instanceId']}'));
    for (final item in items) {
      if ((item['reorganizationCooldownUntil'] as num? ?? 0).toInt() > now) {
        continue;
      }
      final definition = config.installation(item['definitionId'] as String);
      if (definition == null || !canCarryHabitatItem(individual, definition)) {
        continue;
      }
      final preference = preferences[definition.id] as Map?;
      if (preference?['liked'] != true) continue;
      final target = findBestSafeZone(state, alcoveId, config, now,
          phaseOverride: phaseOverride,
          excludingZoneId: item['zoneId'] as String,
          individual: individual);
      if (target == item['zoneId']) continue;
      return <String, String>{
        'instanceId': item['instanceId'] as String,
        'fromZoneId': item['zoneId'] as String,
        'targetZoneId': target,
      };
    }
    return null;
  }

  /// Selects a behavioural station without turning furniture into a second
  /// production system. Tempo only biases the choice; the instance remains
  /// the exact target of the scene sequence.
  static Map<String, dynamic>? nextFurnitureActivity(ElevageSave state,
      String individualId, String alcoveId, int now, ElevageConfig config) {
    final individual = _individual(state, individualId);
    final tempo = personalityValue(individual, 'tempo');
    final candidates = habitatItems(state, alcoveId).where((item) {
      final definition = config.installation(item['definitionId'] as String);
      final lastUsed = (item['lastUsedAt'] as num? ?? 0).toInt();
      return definition?.category == 'MEUBLE' &&
          definition?.activity != 'REST' &&
          now - lastUsed >= config.autonomousReactionIntervalSeconds * 1000;
    }).toList()
      ..sort((a, b) {
        final aScore = _furnitureAffinityScore(
            config.installation(a['definitionId'] as String),
            tempo,
            individual['family'] as String? ?? 'MINERAL');
        final bScore = _furnitureAffinityScore(
            config.installation(b['definitionId'] as String),
            tempo,
            individual['family'] as String? ?? 'MINERAL');
        return bScore == aScore
            ? '${a['instanceId']}'.compareTo('${b['instanceId']}')
            : bScore.compareTo(aScore);
      });
    return candidates.isEmpty
        ? null
        : Map<String, dynamic>.from(candidates.first);
  }

  /// A rest station is only suggested for an actual daytime nap intent. The
  /// minute bucket makes the opportunity deterministic across reloads while
  /// giving Posé a higher configured probability than Spontané.
  static Map<String, dynamic>? nextDayNapFurniture(ElevageSave state,
      String individualId, String alcoveId, int now, ElevageConfig config,
      {String? phaseOverride}) {
    if ((phaseOverride ?? dayNightPhase(now, config)) != 'DAY') return null;
    final individual = _individual(state, individualId);
    if (isSleeping(individual, now, config)) return null;
    final sleep = individual['sleep'] as Map? ?? const <String, dynamic>{};
    final lastNap = (sleep['lastDayNapAt'] as num? ?? 0).toInt();
    if (now - lastNap < config.dayNapCooldownSeconds * 1000) return null;
    final chance = personalityValue(individual, 'tempo') >= .5
        ? config.posedDayNapChancePercent
        : config.spontaneousDayNapChancePercent;
    final seed =
        '${individual['individualSeed'] ?? individualId}:${now ~/ 60000}';
    if (_hash(seed) % 100 >= chance) return null;
    final rests = habitatItems(state, alcoveId).where((item) {
      final definition = config.installation(item['definitionId'] as String);
      return definition?.category == 'MEUBLE' && definition?.activity == 'REST';
    }).toList()
      ..sort((a, b) => '${a['instanceId']}'.compareTo('${b['instanceId']}'));
    return rests.isEmpty ? null : Map<String, dynamic>.from(rests.first);
  }

  static ElevageSave startDayNap(ElevageSave source, String individualId,
      String zoneId, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, individualId);
    final sleep =
        individual.putIfAbsent('sleep', () => <String, dynamic>{}) as Map;
    final until = now + config.dayNapDurationSeconds * 1000;
    sleep['dayNapUntil'] = until;
    sleep['dayNapZoneId'] = zoneId;
    sleep['lastDayNapAt'] = now;
    individual['activeRequest'] = <String, dynamic>{
      'need': 'REST',
      'signal': 'REST_REQUEST',
      'createdAt': now,
      'expiresAt': until,
    };
    return state;
  }

  static int _furnitureAffinityScore(
      ElevageInstallationDefinition? definition, double tempo, String family) {
    final ecologicalScore = switch ('$family:${definition?.id}') {
      'VEGETAL:POTAGER_VERTICAL' ||
      'FUNGAL:LITIERE_FONGIQUE' ||
      'MINERAL:BAC_GRAVIER' =>
        3,
      _ => 0,
    };
    if (ecologicalScore > 0) return ecologicalScore;
    final activity = definition?.activity;
    if (activity == 'REST' || activity == 'READ') return tempo >= .5 ? 2 : 1;
    if (activity == 'PLAY') return tempo < .5 ? 2 : 1;
    return 1;
  }

  static ElevageSave useFurniture(ElevageSave source, String individualId,
      String alcoveId, String instanceId, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, individualId);
    final items =
        (state.data['habitatItemsByAlcoveId'] as Map)[alcoveId] as List? ??
            <dynamic>[];
    Map? item;
    for (final entry in items.whereType<Map>()) {
      if (entry['instanceId'] == instanceId) {
        item = entry;
        break;
      }
    }
    if (item == null) throw StateError('Meuble introuvable.');
    final definition = config.installation(item['definitionId'] as String);
    if (definition?.category != 'MEUBLE') {
      throw StateError('Cet objet ne constitue pas une station d’activité.');
    }
    item['interactionCount'] =
        (item['interactionCount'] as num? ?? 0).toInt() + 1;
    item['lastUsedAt'] = now;
    if (definition!.experiencedLightDelta != 0 ||
        definition.experiencedTemperatureDelta != 0 ||
        definition.experiencedHumidityDelta != 0) {
      individual['activeComfortFurniture'] = <String, dynamic>{
        'instanceId': item['instanceId'],
        'definitionId': definition.id,
        'zoneId': item['zoneId'],
      };
    } else {
      // A comfort effect is tied to the current activity, never to a zone
      // forever. Starting another furniture activity ends the nest effect.
      individual.remove('activeComfortFurniture');
    }
    final posed = personalityValue(individual, 'tempo') >= .5;
    final boost = definition.wellbeingImpact +
        ((definition.activity == 'REST' || definition.activity == 'READ') &&
                posed
            ? 1
            : 0);
    _adjustWellbeing(individual, boost, now);
    _interaction(individual, 'FURNITURE_${definition.activity ?? 'USE'}',
        tempo: definition.activity == 'PLAY' ? -1 : 1);
    return state;
  }

  /// Ends an individual comfort activity without changing the raw zone. The
  /// presentation calls this when the P'TIPOTE leaves its nest; keeping it in
  /// the domain also makes the transition deterministic for saves and tests.
  static ElevageSave stopUsingComfortFurniture(
      ElevageSave source, String individualId) {
    final state = source.copy();
    _individual(state, individualId).remove('activeComfortFurniture');
    return state;
  }

  static int zoneStaySeconds(
      Map individual, String comfort, ElevageConfig config) {
    final stage = individual['lifecycle']['stage'] as String;
    var seconds = switch (stage) {
      'BABY' => config.baseStayBabySeconds,
      'INTERMEDIATE' => config.baseStayIntermediateSeconds,
      _ => config.baseStayMatureSeconds,
    };
    seconds += personalityValue(individual, 'tempo') >= .5
        ? config.tempoPosedStayModifierSeconds
        : config.tempoSpontaneousStayModifierSeconds;
    seconds += switch (comfort) {
      'IDEAL' || 'GOOD' => config.perfectZoneStayModifierSeconds,
      'BAD' => config.badZoneStayModifierSeconds,
      'EXTREME' => config.extremeZoneStayModifierSeconds,
      _ => 0,
    };
    return max(config.minStaySeconds, seconds);
  }

  /// Rolls a decorative affinity once from the persistent individual seed.
  /// Similarity adds a single capped +20 bonus, never a bonus per object.
  static ElevageSave persistDecorPreference(ElevageSave source,
      String individualId, ElevageInstallationDefinition definition) {
    final state = source.copy();
    final individual = _individual(state, individualId);
    final category = definition.decorCategory;
    if (definition.category != 'DECORATION' || category == null) return state;
    final preferences = individual.putIfAbsent(
        'decorPreferences', () => <String, dynamic>{}) as Map;
    // Each decorative instance is evaluated once. Keeping the group alongside
    // the instance lets a second decoration from the same family inherit one
    // bounded similarity bonus without ever rerolling the first result.
    if (preferences[definition.id] != null) return state;
    final family = individual['family'] as String? ?? 'MINERAL';
    var chance = switch (family) {
      'VEGETAL' when category == 'VEGETAL' || category == 'MOSS' => 70,
      'FUNGAL' when category == 'MOSS' || category == 'VEGETAL' => 70,
      'MINERAL' when category == 'CRYSTAL' => 80,
      'MINERAL' when category == 'MINERAL' => 70,
      _ => 50,
    };
    final tempo = personalityValue(individual, 'tempo');
    if (category == 'MUSIC_SOFT' && tempo >= .5) chance += 15;
    if (category == 'MUSIC_ENERGETIC' && tempo < .5) chance += 15;
    if (category == 'MUSIC_ENERGETIC' && tempo >= .5) chance -= 15;
    if (preferences.values
        .whereType<Map>()
        .any((entry) => entry['liked'] == true && entry['group'] == category)) {
      chance += 20;
    }
    chance = chance.clamp(0, 100);
    final seed = '${individual['individualSeed']}:decor:${definition.id}';
    preferences[definition.id] = <String, dynamic>{
      'liked': _hash(seed).abs() % 100 < chance,
      'chance': chance,
      'group': category,
    };
    return state;
  }

  static ElevageSave interactDecoration(ElevageSave source, String individualId,
      String alcoveId, String instanceId, int now, ElevageConfig config) {
    final state = source.copy();
    final all = state.data['habitatItemsByAlcoveId'] as Map;
    final entries = all[alcoveId] as List? ?? <dynamic>[];
    Map? item;
    for (final entry in entries.whereType<Map>()) {
      if (entry['instanceId'] == instanceId) {
        item = entry;
        break;
      }
    }
    if (item == null) throw StateError('Décoration introuvable.');
    final definition = config.installation(item['definitionId'] as String);
    if (definition?.category != 'DECORATION') return state;
    final preferred = persistDecorPreference(state, individualId, definition!);
    final individual = _individual(preferred, individualId);
    final preference =
        (individual['decorPreferences'] as Map)[definition.id] as Map;
    final persistedItems =
        (preferred.data['habitatItemsByAlcoveId'] as Map)[alcoveId] as List;
    final persistedItem = persistedItems
        .whereType<Map>()
        .firstWhere((entry) => entry['instanceId'] == instanceId);
    persistedItem['interactionCount'] =
        (persistedItem['interactionCount'] as num? ?? 0).toInt() + 1;
    if (preference['liked'] == true) {
      _adjustWellbeing(individual, definition.wellbeingImpact, now);
    }
    return preferred;
  }

  static ElevageSave resonateFormation(ElevageSave source, String individualId,
      String alcoveId, String instanceId, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, individualId);
    if (!canResonate(individual, config)) {
      throw StateError('La résonance demande un stade plus avancé.');
    }
    Map? slot;
    for (final entry
        in (_alcove(state, alcoveId)['slots'] as List).whereType<Map>()) {
      if (entry['instanceId'] == instanceId) {
        slot = entry;
        break;
      }
    }
    final definition = slot == null
        ? null
        : config.installation(slot['definitionId'] as String);
    final supportedFamily = definition?.resonanceFamily ??
        (definition?.resonanceMaterial == null ? null : 'MINERAL');
    if (supportedFamily == null ||
        supportedFamily != (individual['family'] as String? ?? 'MINERAL')) {
      throw StateError('Cette structure ne soutient pas la résonance.');
    }
    final care = individual['care'] as Map;
    final structural = care['structuralIntake'] as Map;
    structural['total'] =
        (structural['total'] as num).toInt() + config.resonanceGainPerUse;
    final byMaterial = structural['byMaterial'] as Map;
    final material = definition!.resonanceMaterial ??
        switch (supportedFamily) {
          'VEGETAL' => 'VEGETAL_RESONANCE',
          'FUNGAL' => 'FUNGAL_RESONANCE',
          _ => 'MINERAL_RESONANCE',
        };
    byMaterial[material] = (byMaterial[material] as num? ?? 0).toInt() +
        config.resonanceGainPerUse;
    _adjustWellbeing(individual, 1, now);
    _interaction(individual, 'RESONATE', initiative: 1, tempo: 1);
    return state;
  }

  /// Moves a compatible item out of the player inventory and into one physical
  /// zone of an Alcôve. A zone holds at most one item in the V0 prototype.
  static ElevageSave placeSceneItem(ElevageSave source, String alcoveId,
      String item, String zoneId, int now, ElevageConfig config) {
    if (!placeableSceneItems.contains(item)) {
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
      // Stable target carried through NEW_ITEM → APPROACH → INSPECT.
      'placedItemInstanceId': 'scene-$now-${placed.length}-$item',
      'itemId': item,
      'zoneId': zoneId,
      'placedAt': now,
      'source': 'PLAYER',
      'interactionCount': 0,
    });
    return state;
  }

  static ElevageSave placeCookedMeal(ElevageSave source, String alcoveId,
      String mealId, String zoneId, int now, ElevageConfig config) {
    if (config.sceneZone(zoneId) == null) throw StateError('Zone invalide.');
    final state = source.copy();
    _alcove(state, alcoveId);
    final portions = state.data['cookedMealInventory'] as Map<String, dynamic>;
    final portion = portions.remove(mealId);
    if (portion is! Map) throw StateError('Portion cuisinée indisponible.');
    final placed = _sceneItems(state, alcoveId);
    if (placed.any((entry) => entry['zoneId'] == zoneId)) {
      portions[mealId] = portion;
      throw StateError('Cette zone contient déjà un objet.');
    }
    final instanceId = 'scene-meal-$now-${placed.length}-$mealId';
    placed.add(<String, dynamic>{
      'instanceId': instanceId,
      'placedItemInstanceId': instanceId,
      'itemId': 'COOKED_MEAL',
      'cookedMealId': mealId,
      'recipeKey': portion['recipeKey'],
      'recipeName': portion['recipeName'],
      'ingredientIds': List<dynamic>.from(
          portion['ingredientIds'] as List? ?? const <dynamic>[]),
      'usedWater': portion['usedWater'] == true,
      'satietyValue': portion['satietyValue'],
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
    final entry = placed.removeAt(index);
    final item = entry['itemId'] as String;
    if (item == 'COOKED_MEAL') {
      final mealId = entry['cookedMealId'] as String? ?? instanceId;
      (state.data['cookedMealInventory'] as Map<String, dynamic>)[mealId] =
          <String, dynamic>{
        'instanceId': mealId,
        'itemId': 'COOKED_MEAL',
        'recipeKey': entry['recipeKey'],
        'recipeName': entry['recipeName'],
        'ingredientIds': List<dynamic>.from(
            entry['ingredientIds'] as List? ?? const <dynamic>[]),
        'usedWater': entry['usedWater'] == true,
        'satietyValue': entry['satietyValue'],
        'createdAt': entry['placedAt'],
        'batchId': entry['batchId'],
      };
      return state;
    }
    final special = _special(state);
    special[item] = (special[item] ?? 0) + 1;
    return state;
  }

  /// Les installations et structures ne sont jamais des objets de scène : la
  /// préhension ne concerne que les unités libres déposées par le joueur.
  static bool canCarrySceneItem(Map individual, String itemId) {
    final stage = individual['lifecycle']['stage'] as String;
    if (stage == 'BABY') return false;
    if (stage == 'MATURE') return placeableSceneItems.contains(itemId);
    return foodItems.contains(itemId) ||
        treatItems.contains(itemId) ||
        structuralItems.contains(itemId) ||
        itemId == 'FRUIT';
  }

  static ElevageSave relocateSceneItem(ElevageSave source, String alcoveId,
      String instanceId, String targetZoneId, ElevageConfig config) {
    if (config.sceneZone(targetZoneId) == null) {
      throw StateError('Zone invalide.');
    }
    final state = source.copy();
    final placed = _sceneItems(state, alcoveId);
    final index =
        placed.indexWhere((entry) => entry['instanceId'] == instanceId);
    if (index < 0) return state; // objet récupéré : annulation propre de queue
    if (placed.any((entry) =>
        entry['instanceId'] != instanceId && entry['zoneId'] == targetZoneId)) {
      return state;
    }
    placed[index]['zoneId'] = targetZoneId;
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
    final rawEnvironment = zoneEnvironment(
        state, alcoveId, item['zoneId'] as String, config,
        now: now, phaseOverride: phaseOverride);
    final effective = environmentExperiencedByPtipote(
        state, individualId, item['zoneId'] as String, rawEnvironment, config);
    final favorite = individual['generatedProfile']['foodPreference'] as String;
    final cookedIngredients = itemId == 'COOKED_MEAL'
        ? (item['ingredientIds'] as List? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false)
        : const <String>[];
    final cookedCompatible = itemId == 'COOKED_MEAL' &&
        cookedIngredients.isNotEmpty &&
        cookedIngredients
            .every((ingredient) => canEat(individual, ingredient, config));
    final isInteresting = itemId == 'COOKED_MEAL' ||
        itemId == favorite ||
        treatItems.contains(itemId) ||
        structuralItems.contains(itemId);
    final comfort = localComfort(effective, config, individual: individual);

    // Un objet pertinent dans une zone défavorable est d'abord saisi, puis
    // emporté vers la meilleure zone sûre. BABY observe mais ne transporte
    // jamais ; les installations ne sont pas des objets de cette chaîne.
    if (isInteresting &&
        canCarrySceneItem(individual, itemId) &&
        (comfort == 'BAD' || comfort == 'EXTREME')) {
      return ElevageSceneItemOutcome(
        behavior: 'FLEE_WITH_ITEM',
        targetZoneId: findBestSafeZone(state, alcoveId, config, now,
            phaseOverride: phaseOverride,
            excludingZoneId: item['zoneId'] as String,
            individual: individual),
        observationCount:
            _observationCount(individual, 'HUMIDITY_AVOIDANCE:$itemId') + 1,
      );
    }
    if (treatItems.contains(itemId)) {
      return const ElevageSceneItemOutcome(
          behavior: 'RUSH_SHAKE', observationCount: 0, consumed: true);
    }
    if (itemId == 'COOKED_MEAL') {
      if (!cookedCompatible) {
        return const ElevageSceneItemOutcome(
            behavior: 'SNIFF', observationCount: 0);
      }
      if (!canOfferNormalFood(state, individualId, now, config)) {
        return const ElevageSceneItemOutcome(
            behavior: 'OBSERVE', observationCount: 0);
      }
      return const ElevageSceneItemOutcome(
          behavior: 'APPROACH', observationCount: 0, consumed: true);
    }
    if (foodItems.contains(itemId) ||
        isFutureCompatibleFood(individual, itemId, config) ||
        canEat(individual, itemId, config)) {
      // A locked, later-compatible food is curiosity only. It must neither
      // consume the object nor leak the individual food preference early.
      if (!canEat(individual, itemId, config)) {
        return const ElevageSceneItemOutcome(
            behavior: 'SNIFF', observationCount: 0);
      }
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
    if (structuralItems.contains(itemId)) {
      if (!canAbsorb(individual, itemId, config)) {
        final interesting = structuralResourcesForFamily(
                individual['family'] as String? ?? 'MINERAL')
            .contains(itemId);
        return ElevageSceneItemOutcome(
            behavior: interesting ? 'STRUCTURAL_INTEREST' : 'OBSERVE',
            observationCount: 0);
      }
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

    if (item == 'COOKED_MEAL' && outcome.consumed) {
      final ingredients = (entry['ingredientIds'] as List? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false);
      if (ingredients.isEmpty ||
          ingredients
              .any((ingredient) => !canEat(individual, ingredient, config))) {
        throw StateError(
            'Cette préparation contient un aliment non accessible à ce stade.');
      }
      if (!canOfferNormalFood(state, individualId, now, config)) {
        throw StateError('P’TIPOTE n’a pas faim.');
      }
      final satiety = (entry['satietyValue'] as num?)?.toDouble() ?? 0;
      setSatiety(
          individual, refreshSatiety(individual, now, config) + satiety, now);
      _interaction(individual, 'FOOD', contact: 1);
      _adjustWellbeing(individual, 1, now);
      _sceneItems(state, alcoveId)
          .removeWhere((sceneItem) => sceneItem['instanceId'] == instanceId);
      return state;
    }

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
    // Some resources (notably LIMESTONE for a Vegetal) can be food for one
    // Type and structural matter for another. Access is decided by the active
    // stage/type pool before falling back to structural absorption.
    final consumed = canEat(individual, item, config)
        ? offerFood(state, individualId, item, now, config)
        : structuralItems.contains(item)
            ? offerStructural(state, individualId, item, now, config)
            : offerFood(state, individualId, item, now, config);
    final consumedItems = _sceneItems(consumed, alcoveId);
    consumedItems
        .removeWhere((sceneItem) => sceneItem['instanceId'] == instanceId);
    return consumed;
  }

  static int weatherBlockStart(int now, ElevageConfig config) {
    final local = DateTime.fromMillisecondsSinceEpoch(now).toLocal();
    final blockHour =
        local.hour - local.hour.remainder(config.weatherBlockHours);
    return DateTime(local.year, local.month, local.day, blockHour)
        .millisecondsSinceEpoch;
  }

  static String weatherTypeAt(int now, ElevageConfig config) {
    final block = weatherBlockStart(now, config);
    final weights = <String, int>{
      'CLEAR': config.weatherClearWeight,
      'LIGHT_RAIN': config.weatherLightRainWeight,
      'HEAVY_RAIN': config.weatherHeavyRainWeight,
    }..removeWhere((_, weight) => weight <= 0);
    final total = weights.values.fold<int>(0, (sum, weight) => sum + weight);
    if (total <= 0) return 'CLEAR';
    var roll = _hash('weather-$block') % total;
    for (final entry in weights.entries) {
      if (roll < entry.value) return entry.key;
      roll -= entry.value;
    }
    return 'CLEAR';
  }

  static Map<String, int> weatherEffectsAt(int now, ElevageConfig config) {
    final type = weatherTypeAt(now, config);
    final elapsedInBlock = now - weatherBlockStart(now, config);
    final raining = switch (type) {
      'HEAVY_RAIN' => true,
      'LIGHT_RAIN' => elapsedInBlock <
          config.lightRainDurationHours *
              const Duration(hours: 1).inMilliseconds,
      _ => false,
    };
    if (!raining) return const <String, int>{'light': 0, 'temperature': 0};
    return switch (type) {
      'HEAVY_RAIN' => <String, int>{
          'light': config.heavyRainLightDelta,
          'temperature': config.heavyRainTemperatureDelta
        },
      'LIGHT_RAIN' => <String, int>{
          'light': config.lightRainLightDelta,
          'temperature': config.lightRainTemperatureDelta
        },
      _ => const <String, int>{'light': 0, 'temperature': 0},
    };
  }

  static bool _isRainingAt(int now, ElevageConfig config) {
    final type = weatherTypeAt(now, config);
    if (type == 'HEAVY_RAIN') return true;
    return type == 'LIGHT_RAIN' &&
        now - weatherBlockStart(now, config) <
            config.lightRainDurationHours *
                const Duration(hours: 1).inMilliseconds;
  }

  static ElevageSave refreshWeather(
      ElevageSave source, int now, ElevageConfig config) {
    final state = source.copy();
    final weather = Map<String, dynamic>.from(state.data['weather'] as Map)
      ..['weatherBlockStart'] = weatherBlockStart(now, config)
      ..['weatherType'] = weatherTypeAt(now, config);
    var last = (weather['lastUpdatedAt'] as num?)?.toInt() ?? now;
    if (last <= 0 || last > now) last = now;
    var collected = 0.0;
    final hourMs = const Duration(hours: 1).inMilliseconds;
    var cursor = last;
    while (cursor < now) {
      final blockEnd =
          weatherBlockStart(cursor, config) + config.weatherBlockHours * hourMs;
      final rainEnd = weatherTypeAt(cursor, config) == 'LIGHT_RAIN'
          ? weatherBlockStart(cursor, config) +
              config.lightRainDurationHours * hourMs
          : blockEnd;
      final segmentEnd =
          min(now, min(blockEnd, cursor < rainEnd ? rainEnd : blockEnd));
      if (_isRainingAt(cursor, config)) {
        collected += (segmentEnd - cursor) / hourMs * config.rainWaterPerHour;
      }
      cursor = segmentEnd;
    }
    state.data['waterTank'] = (waterTank(state) + collected)
        .clamp(0, config.waterTankCapacity)
        .toDouble();
    weather['lastUpdatedAt'] = now;
    state.data['weather'] = weather;
    return state;
  }

  static Map<String, int> zoneEnvironment(
      ElevageSave state, String alcoveId, String zoneId, ElevageConfig config,
      {int? now, String? phaseOverride}) {
    final zone = config.sceneZone(zoneId);
    if (zone == null) throw StateError('Zone invalide.');
    final phase = phaseOverride ??
        dayNightPhase(now ?? DateTime.now().millisecondsSinceEpoch, config);
    final nightOffset = phase == 'NIGHT' ? config.nightLightOffset(zoneId) : 0;
    // Les valeurs de base sont indépendantes des labels décoratifs des zones.
    // Le reliquat historique « Coin humide +2 » est ainsi éliminé : seule une
    // installation peut désormais faire monter l'humidité locale.
    final result = <String, int>{
      'light': zone.light + nightOffset,
      'temperature': config.baseTemperature +
          (phase == 'DAY' ? config.dayTemperatureDelta : 0) +
          zone.temperature,
      'humidity': config.baseHumidity + zone.humidity,
    };
    final weather =
        weatherEffectsAt(now ?? DateTime.now().millisecondsSinceEpoch, config);
    result['light'] = result['light']! + weather['light']!;
    result['temperature'] = result['temperature']! + weather['temperature']!;
    final slots = _alcove(state, alcoveId)['slots'] as List;
    for (var index = 0; index < slots.length; index++) {
      final raw = slots[index];
      if (raw is! Map) continue;
      // Les anciennes sauvegardes n'avaient pas encore la position spatiale
      // des installations : leur slot reste une position de repli stable.
      final installedZone = raw['zoneId'] as String? ?? 'ZONE_${index + 1}';
      final definition = config.installation(raw['definitionId'] as String);
      if (definition == null) continue;
      if (!structureIsActive(raw, config)) continue;
      final effects = _effectiveEnvironmentEffects(raw, definition, config);
      if (installedZone == zoneId) {
        result['light'] = result['light']! + effects['light']!;
      }
      result['temperature'] = result['temperature']! +
          _localOrAdjacentContribution(
              effects['temperature']!, installedZone, zoneId, config);
      result['humidity'] = result['humidity']! +
          _localOrAdjacentContribution(
              effects['humidity']!, installedZone, zoneId, config);
    }
    // Une zone naturellement très ombragée refroidit localement. Cette règle
    // reste dans le domaine et utilise la lumière effective, pas la vue.
    // La nuit n'est pas une « ombre » additionnelle : seul le niveau lumineux
    // local hors offset nocturne peut refroidir la zone.
    final lightWithoutNight = result['light']! - nightOffset;
    if (lightWithoutNight.clamp(0, 5) <= 2) {
      result['temperature'] =
          result['temperature']! + config.strongShadeTemperatureDelta;
    }
    // L’environnement est désormais une donnée métier 0–5, jamais une
    // valeur relative négative masquée uniquement par l’interface.
    return result.map((key, value) => MapEntry(key, value.clamp(0, 5)));
  }

  /// Applies a comfort item only to its current user. Raw zone values and
  /// their HUD/diffusion are never altered by a nest.
  static Map<String, int> experiencedEnvironment(
      Map<String, int> raw, ElevageInstallationDefinition? furniture) {
    if (furniture?.category != 'MEUBLE') return Map<String, int>.from(raw);
    return <String, int>{
      'light': ((raw['light'] ?? 0) + furniture!.experiencedLightDelta)
          .clamp(0, 5)
          .toInt(),
      'temperature':
          ((raw['temperature'] ?? 0) + furniture.experiencedTemperatureDelta)
              .clamp(0, 5)
              .toInt(),
      'humidity': ((raw['humidity'] ?? 0) + furniture.experiencedHumidityDelta)
          .clamp(0, 5)
          .toInt(),
    };
  }

  static Map<String, int> environmentExperiencedByPtipote(
      ElevageSave state,
      String individualId,
      String currentZoneId,
      Map<String, int> raw,
      ElevageConfig config) {
    final individual = _individual(state, individualId);
    final active = individual['activeComfortFurniture'] as Map?;
    if (active == null || active['zoneId'] != currentZoneId) {
      return Map<String, int>.from(raw);
    }
    final alcoveId = individual['alcoveId'] as String?;
    final stillUsing = alcoveId != null &&
        habitatItems(state, alcoveId).any((item) =>
            item['instanceId'] == active['instanceId'] &&
            item['zoneId'] == currentZoneId);
    if (!stillUsing) return Map<String, int>.from(raw);
    return experiencedEnvironment(
        raw, config.installation(active['definitionId'] as String? ?? ''));
  }

  /// Les effets ±1 sont strictement locaux. Les effets de magnitude ≥2
  /// conservent leur valeur au centre et diffusent ±1 vers les deux voisins.
  static int _localOrAdjacentContribution(int magnitude, String originZoneId,
      String targetZoneId, ElevageConfig config) {
    if (magnitude == 0) return 0;
    if (originZoneId == targetZoneId) return magnitude;
    if (magnitude.abs() < 2) return 0;
    final originIndex =
        config.sceneZones.indexWhere((z) => z.id == originZoneId);
    final targetIndex =
        config.sceneZones.indexWhere((z) => z.id == targetZoneId);
    if (originIndex < 0 ||
        targetIndex < 0 ||
        (originIndex - targetIndex).abs() != 1) {
      return 0;
    }
    return magnitude.isNegative ? -1 : 1;
  }

  /// Donne l'origine de chaque terme pour les diagnostics dev. La valeur
  /// finale est toujours calculée par [zoneEnvironment], sans double compte.
  static Map<String, int> environmentDiagnostics(
      ElevageSave state, String alcoveId, String zoneId, ElevageConfig config,
      {required int now, String? phaseOverride}) {
    final phase = phaseOverride ?? dayNightPhase(now, config);
    final zone = config.sceneZone(zoneId)!;
    final result = <String, int>{
      'baseHumidity': config.baseHumidity,
      'zoneHumidity': zone.humidity,
      'baseTemperature': config.baseTemperature,
      'dayTemperature': phase == 'DAY' ? config.dayTemperatureDelta : 0,
    };
    var localHumidity = 0;
    var diffusionHumidity = 0;
    var localTemperature = 0;
    var diffusionTemperature = 0;
    for (var index = 0;
        index < (_alcove(state, alcoveId)['slots'] as List).length;
        index++) {
      final raw = (_alcove(state, alcoveId)['slots'] as List)[index];
      if (raw is! Map) continue;
      final definition = config.installation(raw['definitionId'] as String);
      if (definition == null || !structureIsActive(raw, config)) continue;
      final origin = raw['zoneId'] as String? ?? 'ZONE_${index + 1}';
      final effects = effectiveEnvironmentalEffects(raw, definition, config);
      final humidity = _localOrAdjacentContribution(
          effects['humidity']!, origin, zoneId, config);
      final temperature = _localOrAdjacentContribution(
          effects['temperature']!, origin, zoneId, config);
      if (origin == zoneId) {
        localHumidity += humidity;
        localTemperature += temperature;
      } else {
        diffusionHumidity += humidity;
        diffusionTemperature += temperature;
      }
    }
    result.addAll(<String, int>{
      'localHumidity': localHumidity,
      'diffusionHumidity': diffusionHumidity,
      'localTemperature': localTemperature,
      'diffusionTemperature': diffusionTemperature,
      'finalHumidity': zoneEnvironment(state, alcoveId, zoneId, config,
          now: now, phaseOverride: phaseOverride)['humidity']!,
      'finalTemperature': zoneEnvironment(state, alcoveId, zoneId, config,
          now: now, phaseOverride: phaseOverride)['temperature']!,
    });
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

  /// Every Nature evaluates the three local axes through its own configured
  /// ecological curve. The worst axis wins: a favourable average can never
  /// conceal one extreme condition.
  static String localComfort(Map<String, int> environment, ElevageConfig config,
      {Map? individual, String? family, String? nature}) {
    const severity = <String, int>{
      'IDEAL': 0,
      'GOOD': 1,
      'NEUTRAL': 2,
      'BAD': 3,
      'EXTREME': 4,
    };
    final profile = individual == null
        ? config.natureProfile(family ?? 'MINERAL', nature ?? 'RESONANCE')
        : config.profileForIndividual(individual);
    final axes = <String>['light', 'temperature', 'humidity']
        .map((axis) =>
            profile.axisComfort(axis, (environment[axis] ?? 0).clamp(0, 5)))
        .toList()
      ..sort((left, right) => severity[right]!.compareTo(severity[left]!));
    // Le pire axe l’emporte : aucun extrême ne peut être masqué par une
    // moyenne favorable sur les deux autres axes.
    return axes.first;
  }

  /// One expressive environmental need.  The result intentionally names an
  /// axis only once the individual is intermediate; Babies communicate it via
  /// body language and configured onomatopoeia.
  static Map<String, String>? environmentalSignal(
      Map<String, int> environment, Map individual, ElevageConfig config) {
    final profile = config.profileForIndividual(individual);
    const axes = <String>['temperature', 'light', 'humidity'];
    const severity = <String, int>{
      'IDEAL': 0,
      'GOOD': 1,
      'NEUTRAL': 2,
      'BAD': 3,
      'EXTREME': 4,
    };
    final candidates = axes.map((axis) {
      final value = (environment[axis] ?? 0).clamp(0, 5);
      return <String, Object>{
        'axis': axis,
        'value': value,
        'comfort': profile.axisComfort(axis, value),
        'direction': value < profile.preferredForAxis(axis) ? 'LOW' : 'HIGH',
      };
    }).toList()
      ..sort(
          (a, b) => severity[b['comfort']]!.compareTo(severity[a['comfort']]!));
    final leading = candidates.first;
    // A non-perfect but still tolerable axis can be expressed as a direction
    // of search (e.g. Résonance at 3/3/2 asks for more heat). Perfect local
    // alignment remains silent.
    if (candidates.every((candidate) =>
        candidate['value'] ==
        profile.preferredForAxis(candidate['axis'] as String))) {
      return null;
    }
    final stage = (individual['lifecycle'] as Map)['stage'] as String;
    final axis = leading['axis'] as String;
    final low = leading['direction'] == 'LOW';
    final icon = switch ('$axis:$low') {
      'temperature:true' => 'COLD',
      'temperature:false' => 'HOT',
      'light:true' => 'MORE_LIGHT',
      'light:false' => 'LESS_LIGHT',
      'humidity:true' => 'DRY',
      _ => 'WET',
    };
    return <String, String>{
      'axis': axis,
      'direction': low ? 'TOO_LOW' : 'TOO_HIGH',
      'comfort': leading['comfort'] as String,
      'icon': stage == 'BABY' ? 'DISCOMFORT' : icon,
      'vocalization': config.vocalizations['DISCOMFORT'] ?? 'Nnh…',
      if (stage != 'BABY') 'label': axis,
    };
  }

  /// Ambient feedback is deliberately independent from any scene item or
  /// current action. It stays visible while a Baby has exhausted every
  /// possible safe zone, making the discomfort an actual persistent state.
  static Map<String, String>? ambientEnvironmentalFeedback(
      Map<String, int> environment, Map individual, ElevageConfig config) {
    final signal = environmentalSignal(environment, individual, config);
    if (signal == null) return null;
    final comfort = signal['comfort'];
    if (comfort != 'BAD' && comfort != 'EXTREME') return null;
    final icon = signal['icon'];
    return <String, String>{
      ...signal,
      // The body layer is independent from the action machine. Cold is
      // therefore visible while the P'TIPOTE is idle, moving or waiting.
      'body':
          signal['axis'] == 'temperature' && signal['direction'] == 'TOO_LOW'
              ? 'SHIVER'
              : icon == 'HOT'
                  ? 'SWEAT'
                  : icon == 'DRY'
                      ? 'DRY'
                      : 'DISCOMFORT',
    };
  }

  /// What can be asked for is not what is felt: a cold individual asks for
  /// heat, while their [ambientEnvironmentalFeedback] still says "cold".
  static Map<String, String>? expressedEnvironmentalNeed(
      Map<String, int> environment, Map individual, ElevageConfig config) {
    // A need is a preference, not an emergency-only symptom: Intermediate
    // and Mature P’TIPOTES can ask for a better axis from a GOOD zone too.
    final signal = environmentalSignal(environment, individual, config);
    if (signal == null ||
        ((individual['lifecycle'] as Map?)?['stage'] as String?) == 'BABY') {
      return null;
    }
    final axis = signal['axis'];
    final direction = signal['direction'];
    final need = switch ('$axis:$direction') {
      'temperature:TOO_LOW' => 'HEAT',
      'temperature:TOO_HIGH' => 'COOL',
      'light:TOO_LOW' => 'LIGHT',
      'light:TOO_HIGH' => 'SHADE',
      'humidity:TOO_LOW' => 'HUMIDITY',
      _ => 'DRYNESS',
    };
    return <String, String>{'need': need, 'axis': axis ?? ''};
  }

  static int environmentalNeedCooldownSeconds(
      Map individual, ElevageConfig config) {
    final multiplier = personalityValue(individual, 'tempo') >= .5
        ? config.posedNeedCooldownMultiplier
        : config.spontaneousNeedCooldownMultiplier;
    return max(
        1, (config.juvenileEnvironmentalNeedCooldownBase * multiplier).round());
  }

  static String environmentalNeedExpression(
      Map individual, String need, ElevageConfig config) {
    final stage =
        ((individual['lifecycle'] as Map?)?['stage'] as String?) ?? 'BABY';
    final details = switch (need) {
      'HEAT' => <String>['chaleur', '🔥'],
      'COOL' => <String>['fraîcheur', '💧'],
      'LIGHT' => <String>['lumière', '☀️'],
      'SHADE' => <String>['ombre', '🌑'],
      'HUMIDITY' => <String>['humidité', '💦'],
      _ => <String>['sec', '🍂'],
    };
    if (stage == 'MATURE') {
      return '${config.communicationText(need, 'MATURE', 'Je voudrais ${details.first}.')} ${details.last}';
    }
    final exposure = ((individual['conceptExposures'] as Map?)?[need] as Map?);
    final total = (exposure?['total'] as num?)?.toInt() ?? 0;
    final baby = (exposure?['baby'] as num?)?.toInt() ?? 0;
    final threshold = baby > 0
        ? config.juvenileBabyKnownConceptWordThreshold
        : config.juvenileNewConceptWordThreshold;
    return total >= threshold
        ? '${config.communicationText(need, 'JUVENILE', 'veux ${details.first}')} ${details.last}'
        : 'Pti ! ${details.last}';
  }

  static Map<String, dynamic> trackerProfession(
      Map individual, ElevageConfig config) {
    final professions =
        individual.putIfAbsent('professions', () => <String, dynamic>{}) as Map;
    final tracker = professions.putIfAbsent(
        'TRACKER',
        () => <String, dynamic>{
              'professionId': 'TRACKER',
              'xp': 0,
              'level': 0,
            }) as Map;
    final xp = (tracker['xp'] as num?)?.toInt() ?? 0;
    var level = 0;
    for (var candidate = 1; candidate <= 3; candidate++) {
      if (xp >= config.trackerThreshold(candidate)) level = candidate;
    }
    tracker['professionId'] = 'TRACKER';
    tracker['xp'] = max(0, xp);
    tracker['level'] = level;
    return Map<String, dynamic>.from(tracker);
  }

  static int trackerCarryBonus(Map individual, ElevageConfig config) =>
      config.trackerCarryBonus(
          (trackerProfession(individual, config)['level'] as num).toInt());

  static ElevageSave addTrackerXp(ElevageSave source, String individualId,
      int amount, ElevageConfig config) {
    if (amount <= 0) return source.copy();
    final state = source.copy();
    final individual = _individual(state, individualId);
    final tracker = trackerProfession(individual, config);
    tracker['xp'] = ((tracker['xp'] as num).toInt() + amount).clamp(0, 999999);
    (individual['professions'] as Map)['TRACKER'] = tracker;
    trackerProfession(individual, config);
    return state;
  }

  /// Development-only counterpart of [addTrackerXp]. The ordinary UI never
  /// calls this: Pisteur XP is earned by completed escorted explorations.
  static ElevageSave setTrackerXp(ElevageSave source, String individualId,
      int amount, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, individualId);
    final tracker = trackerProfession(individual, config);
    final xp = max(0, amount);
    tracker['xp'] = xp;
    (individual['professions'] as Map)['TRACKER'] = tracker;
    trackerProfession(individual, config);
    return state;
  }

  static ElevageSave forceTrackerLevel(ElevageSave source, String individualId,
      int level, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, individualId);
    final clamped = level.clamp(0, 3);
    final tracker = trackerProfession(individual, config);
    tracker['xp'] = clamped == 0 ? 0 : config.trackerThreshold(clamped);
    (individual['professions'] as Map)['TRACKER'] = tracker;
    trackerProfession(individual, config);
    return state;
  }

  /// Exploration endurance belongs to the individual, never to wellbeing,
  /// hunger or sleep. It is refreshed from timestamps for online and offline
  /// returns alike.
  static Map<String, dynamic> explorationEndurance(
      Map individual, int now, ElevageConfig config) {
    final maxStamina = config.explorationInt('ptipoteStaminaMax', 10);
    final regenMinutes =
        max(1, config.explorationInt('ptipoteStaminaRegenMinutes', 5));
    final endurance = individual.putIfAbsent(
        'explorationStamina',
        () => <String, dynamic>{
              'current': maxStamina,
              'lastUpdatedAt': now
            }) as Map;
    final last = (endurance['lastUpdatedAt'] as num?)?.toInt() ?? now;
    final interval = Duration(minutes: regenMinutes).inMilliseconds;
    final cycles = max(0, (now - last) ~/ interval);
    if (cycles > 0) {
      endurance['current'] = min(maxStamina,
          ((endurance['current'] as num?)?.toInt() ?? maxStamina) + cycles);
      endurance['lastUpdatedAt'] = last + cycles * interval;
    }
    endurance['current'] =
        ((endurance['current'] as num?)?.toInt() ?? maxStamina)
            .clamp(0, maxStamina);
    return Map<String, dynamic>.from(endurance);
  }

  static bool canAccompanyExploration(
      Map individual, int now, ElevageConfig config) {
    final stage =
        ((individual['lifecycle'] as Map?)?['stage'] as String?) ?? 'BABY';
    return stage != 'BABY' &&
        (explorationEndurance(individual, now, config)['current'] as num)
                .toInt() >=
            config.explorationInt('ptipoteStaminaCostPerRun', 1);
  }

  static List<Map<String, dynamic>> eligibleExplorationCompanions(
      ElevageSave state, int now, ElevageConfig config) {
    final active =
        state.data['activeIndividualIds'] as List? ?? const <dynamic>[];
    final individuals =
        state.data['individuals'] as Map? ?? const <dynamic, dynamic>{};
    return active
        .whereType<String>()
        .map((id) => individuals[id])
        .whereType<Map>()
        .where((individual) => canAccompanyExploration(individual, now, config))
        .map((individual) => Map<String, dynamic>.from(individual))
        .toList(growable: false);
  }

  /// Baby searches one adjacent zone at a time and never receives a perfect
  /// global GPS target outside an emergency. Intermediate keeps the same
  /// exploratory principle but evaluates the available local candidates faster.
  static String exploratoryZoneTarget(ElevageSave state, String alcoveId,
      String currentZoneId, Map individual, ElevageConfig config, int now,
      {String? phaseOverride}) {
    final current = zoneEnvironment(state, alcoveId, currentZoneId, config,
        now: now, phaseOverride: phaseOverride);
    final comfort = localComfort(current, config, individual: individual);
    final memory = individual['environmentalMemory'] as Map?;
    final rejected = (memory?['temporaryRejectedZones'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    if (comfort == 'BAD' || comfort == 'EXTREME') {
      rejected.add(currentZoneId);
      memory?['temporaryRejectedZones'] = rejected.toList(growable: false);
    }
    if (comfort == 'EXTREME') {
      final favorite = memory?['favoriteZone'] as String?;
      final knownSafe = memory?['lastKnownSafeZone'] as String?;
      for (final candidate in <String?>[favorite, knownSafe]) {
        if (candidate == null || candidate == currentZoneId) continue;
        final candidateComfort = localComfort(
            zoneEnvironment(state, alcoveId, candidate, config,
                now: now, phaseOverride: phaseOverride),
            config,
            individual: individual);
        if (candidateComfort != 'EXTREME') return candidate;
      }
      return findBestSafeZone(state, alcoveId, config, now,
          phaseOverride: phaseOverride,
          excludingZoneId: currentZoneId,
          individual: individual);
    }
    final index =
        config.sceneZones.indexWhere((zone) => zone.id == currentZoneId);
    final adjacent = <String>[
      if (index > 0) config.sceneZones[index - 1].id,
      if (index >= 0 && index + 1 < config.sceneZones.length)
        config.sceneZones[index + 1].id,
    ].where((zone) => !rejected.contains(zone)).toList();
    if (adjacent.isEmpty) {
      return findBestSafeZone(state, alcoveId, config, now,
          phaseOverride: phaseOverride,
          excludingZoneId: currentZoneId,
          individual: individual);
    }
    // Deterministic alternation gives the Baby a visible left/right trial
    // without relying on a process-local random generator.
    return adjacent[(now ~/ 1000 + index).abs() % adjacent.length];
  }

  static String bestComfortZone(
      ElevageSave state, String alcoveId, ElevageConfig config, int now,
      {String? phaseOverride, String? excludingZoneId, Map? individual}) {
    return findBestSafeZone(state, alcoveId, config, now,
        phaseOverride: phaseOverride,
        excludingZoneId: excludingZoneId,
        individual: individual);
  }

  /// Choisit une destination sûre parmi toutes les zones accessibles, sans se
  /// rabattre mécaniquement sur la zone précédente. Le tri est stable par
  /// confort puis par ordre spatial afin que la décision reste déterministe.
  static String bestZoneFromEnvironment(
      Map<String, Map<String, int>> environments, ElevageConfig config,
      {String? excludingZoneId,
      Map? individual,
      String? family,
      String? nature}) {
    const severity = <String, int>{
      'IDEAL': 0,
      'GOOD': 1,
      'NEUTRAL': 2,
      'BAD': 3,
      'EXTREME': 4,
    };
    final candidates = environments.entries
        .where((entry) => entry.key != excludingZoneId)
        .toList();
    final available =
        candidates.isEmpty ? environments.entries.toList() : candidates;
    available.sort((left, right) {
      final leftComfort = localComfort(left.value, config,
          individual: individual, family: family, nature: nature);
      final rightComfort = localComfort(right.value, config,
          individual: individual, family: family, nature: nature);
      final comparison =
          severity[leftComfort]!.compareTo(severity[rightComfort]!);
      return comparison != 0 ? comparison : left.key.compareTo(right.key);
    });
    return available.first.key;
  }

  static String findBestSafeZone(
      ElevageSave state, String alcoveId, ElevageConfig config, int now,
      {String? phaseOverride, String? excludingZoneId, Map? individual}) {
    return bestZoneFromEnvironment(<String, Map<String, int>>{
      for (final zone in config.sceneZones)
        zone.id: _bestExperiencedEnvironmentForZone(
            state,
            alcoveId,
            zone.id,
            zoneEnvironment(state, alcoveId, zone.id, config,
                now: now, phaseOverride: phaseOverride),
            individual,
            config),
    }, config, excludingZoneId: excludingZoneId, individual: individual);
  }

  /// A nest never changes a zone's displayed environment. It can however be
  /// a better destination for rest/sleep because the resident experiences its
  /// single comfort delta while using it.
  static Map<String, int> _bestExperiencedEnvironmentForZone(
      ElevageSave state,
      String alcoveId,
      String zoneId,
      Map<String, int> raw,
      Map? individual,
      ElevageConfig config) {
    if (individual == null) return raw;
    const severity = <String, int>{
      'IDEAL': 0,
      'GOOD': 1,
      'NEUTRAL': 2,
      'BAD': 3,
      'EXTREME': 4,
    };
    var best = Map<String, int>.from(raw);
    var bestScore =
        severity[localComfort(best, config, individual: individual)]!;
    for (final item in habitatItems(state, alcoveId)) {
      if (item['zoneId'] != zoneId) continue;
      final definition =
          config.installation(item['definitionId'] as String? ?? '');
      if (definition == null ||
          (definition.experiencedLightDelta == 0 &&
              definition.experiencedTemperatureDelta == 0 &&
              definition.experiencedHumidityDelta == 0)) {
        continue;
      }
      final experienced = experiencedEnvironment(raw, definition);
      final score =
          severity[localComfort(experienced, config, individual: individual)]!;
      if (score < bestScore) {
        best = experienced;
        bestScore = score;
      }
    }
    return best;
  }

  static String dayNightPhase(int now, ElevageConfig config) {
    final hour = DateTime.fromMillisecondsSinceEpoch(now).toLocal().hour;
    final night = config.nightStartHour <= config.nightEndHour
        ? hour >= config.nightStartHour && hour < config.nightEndHour
        : hour >= config.nightStartHour || hour < config.nightEndHour;
    return night ? 'NIGHT' : 'DAY';
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
    final local = DateTime.fromMillisecondsSinceEpoch(now).toLocal();
    final endHour =
        phase == 'NIGHT' ? config.nightEndHour : config.nightStartHour;
    var end = DateTime(local.year, local.month, local.day, endHour);
    if (!end.isAfter(local)) end = end.add(const Duration(days: 1));
    return end.millisecondsSinceEpoch - local.millisecondsSinceEpoch;
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

  static Map<String, dynamic> initialExplorationState(int now,
          [ElevageConfig? config]) =>
      <String, dynamic>{
        'stamina': 10,
        'lastStaminaAt': now,
        'activeRun': null,
        'sectors': <String, dynamic>{
          for (final base in explorationSectors)
            (config == null
                    ? base
                    : resolvedExplorationSector(base, config))['id'] as String:
                <String, dynamic>{
              'discovered': false,
              'organic': (config == null
                  ? base
                  : resolvedExplorationSector(base, config))['organic'],
              'mineral': (config == null
                  ? base
                  : resolvedExplorationSector(base, config))['mineral'],
              'lastOrganicAt': now,
            },
        },
      };

  /// Non-destructive migration from the retired Mini-Lisière. Its historical
  /// runs remain readable, but only this one global Exploration run is active.
  static void normalizeExplorationState(Map<String, dynamic> data, int now) {
    final existing = data['exploration'];
    final initial = initialExplorationState(now);
    if (existing is! Map) {
      data['exploration'] = initial;
      return;
    }
    existing.putIfAbsent('stamina', () => initial['stamina']);
    existing.putIfAbsent('lastStaminaAt', () => now);
    existing.putIfAbsent('activeRun', () => null);
    final sectors =
        existing.putIfAbsent('sectors', () => <String, dynamic>{}) as Map;
    for (final definition in explorationSectors) {
      final id = definition['id'] as String;
      final sector = sectors.putIfAbsent(id, () => <String, dynamic>{}) as Map;
      sector.putIfAbsent('discovered', () => false);
      sector.putIfAbsent('organic', () => definition['organic']);
      sector.putIfAbsent('mineral', () => definition['mineral']);
      sector.putIfAbsent('lastOrganicAt', () => now);
    }
  }

  static Map explorationState(ElevageSave state) =>
      state.data['exploration'] as Map;

  static Map<String, dynamic>? explorationSectorDefinition(String sectorId) =>
      explorationSectors
          .where((sector) => sector['id'] == sectorId)
          .cast<Map<String, dynamic>?>()
          .firstOrNull;

  static Map<String, dynamic> resolvedExplorationSector(
      Map<String, dynamic> definition, ElevageConfig config) {
    final override =
        config.explorationSectorOverride(definition['id'] as String);
    final resolved = <String, dynamic>{...definition, ...override};
    if (override.containsKey('initialOrganic')) {
      resolved['organic'] = override['initialOrganic'];
    }
    if (override.containsKey('initialMineral')) {
      resolved['mineral'] = override['initialMineral'];
    }
    resolved['maxOrganic'] = (override['maxOrganic'] as num?)?.toInt() ?? 100;
    return resolved;
  }

  static List<Map<String, dynamic>> explorationSectorsForBiome(String biomeId,
          [ElevageConfig? config]) =>
      explorationSectors
          .where((sector) => sector['biomeId'] == biomeId)
          .map((sector) => config == null
              ? Map<String, dynamic>.from(sector)
              : resolvedExplorationSector(sector, config))
          .toList(growable: false);

  static ElevageSave refreshExploration(
      ElevageSave source, int now, ElevageConfig config) {
    final state = source.copy();
    normalizeExplorationState(state.data, now);
    final exploration = explorationState(state);
    final maxStamina = config.explorationInt(
        'playerStaminaMax', config.explorationInt('staminaMax', 10));
    final regenMinutes = max(
        1,
        config.explorationInt('playerStaminaRegenMinutes',
            config.explorationInt('staminaRegenPerMinute', 1)));
    final lastStamina = (exploration['lastStaminaAt'] as num?)?.toInt() ?? now;
    final staminaInterval = Duration(minutes: regenMinutes).inMilliseconds;
    final staminaCycles = max(0, (now - lastStamina) ~/ staminaInterval);
    if (staminaCycles > 0) {
      exploration['stamina'] = min(
          maxStamina,
          ((exploration['stamina'] as num?)?.toInt() ?? maxStamina) +
              staminaCycles);
      exploration['lastStaminaAt'] =
          lastStamina + staminaCycles * staminaInterval;
    }
    for (final individual
        in (state.data['individuals'] as Map? ?? const <dynamic, dynamic>{})
            .values
            .whereType<Map>()) {
      explorationEndurance(individual, now, config);
    }
    final organicRegen = config.explorationInt('organicRegenPerHour', 5);
    final sectors = exploration['sectors'] as Map;
    for (final definition in explorationSectors) {
      final sector = sectors[definition['id']] as Map;
      final last = (sector['lastOrganicAt'] as num?)?.toInt() ?? now;
      final cycles =
          max(0, (now - last) ~/ const Duration(hours: 1).inMilliseconds);
      if (cycles > 0) {
        final maxOrganic =
            (resolvedExplorationSector(definition, config)['maxOrganic'] as num)
                .toInt();
        sector['organic'] = min(
            maxOrganic,
            ((sector['organic'] as num?)?.toInt() ?? 0) +
                cycles * organicRegen);
        sector['lastOrganicAt'] =
            last + cycles * const Duration(hours: 1).inMilliseconds;
      }
    }
    final run = exploration['activeRun'];
    if (run is Map &&
        run['status'] == 'IN_PROGRESS' &&
        now >= (run['endsAt'] as num).toInt()) {
      run['status'] = 'READY';
    }
    return state;
  }

  static String explorationStatus(
      ElevageSave state, int now, ElevageConfig config) {
    final refreshed = refreshExploration(state, now, config);
    final run = explorationState(refreshed)['activeRun'];
    return run is Map ? run['status'] as String? ?? 'NONE' : 'NONE';
  }

  static ElevageSave startExploration(
      ElevageSave source, String sectorId, int now, ElevageConfig config,
      {String? companionPtipoteId,
      int outingCount = 1,
      String? specificSearchType}) {
    if (!config.explorationEnabled) {
      throw StateError('Exploration indisponible.');
    }
    var state = refreshExploration(source, now, config);
    final exploration = explorationState(state);
    final previous = exploration['activeRun'];
    if (previous is Map && previous['status'] != 'CLAIMED') {
      throw StateError('Une exploration est déjà en cours ou à récupérer.');
    }
    final baseDefinition = explorationSectorDefinition(sectorId);
    final definition = baseDefinition == null
        ? null
        : resolvedExplorationSector(baseDefinition, config);
    if (definition == null || definition['enabled'] == false) {
      throw StateError('Secteur inconnu.');
    }
    if (outingCount < 1) {
      throw StateError('Le nombre de sorties doit être positif.');
    }
    if (specificSearchType != null &&
        specificSearchType != 'MINERAL' &&
        specificSearchType != 'ORGANIC') {
      throw StateError('Recherche spécifique inconnue.');
    }
    final stamina = (exploration['stamina'] as num?)?.toInt() ?? 0;
    final staminaCostPerOuting = config.explorationInt(
        'playerStaminaCost', config.explorationInt('staminaCostPerRun', 1));
    final staminaCost = staminaCostPerOuting * outingCount;
    if (stamina < staminaCost) throw StateError('Endurance insuffisante.');
    Map? companion;
    var trackerBonus = 0;
    String? typeBias;
    var companionStaminaCost = 0;
    if (companionPtipoteId != null) {
      companion = _individual(state, companionPtipoteId);
      if (!canAccompanyExploration(companion, now, config)) {
        throw StateError(
            'Ce P’TIPOTE ne peut pas accompagner cette exploration.');
      }
      final endurance = companion['explorationStamina'] as Map;
      companionStaminaCost =
          config.explorationInt('ptipoteStaminaCostPerRun', 1) * outingCount;
      if ((endurance['current'] as num).toInt() < companionStaminaCost) {
        throw StateError('Endurance du compagnon insuffisante.');
      }
      endurance['current'] =
          (endurance['current'] as num).toInt() - companionStaminaCost;
      trackerBonus = trackerCarryBonus(companion, config);
      typeBias = companion['family'] as String?;
    }
    final sector = (exploration['sectors'] as Map)[sectorId] as Map;
    exploration['stamina'] = stamina - staminaCost;
    sector['discovered'] = true;
    final slots = config.explorationInt('baseCarrySlots', 3) + trackerBonus;
    final results = <Map<String, dynamic>>[];
    final cycleResults = <Map<String, dynamic>>[];
    for (var outing = 0; outing < outingCount; outing++) {
      final outingLoot = <Map<String, dynamic>>[];
      for (var slot = 0; slot < slots; slot++) {
        final loot = _rollExplorationLoot(
            sector, definition, config, now + outing * 1009 + slot,
            typeBias: typeBias, specificSearchType: specificSearchType);
        final result = loot ?? <String, dynamic>{'resourceId': 'EMPTY'};
        outingLoot.add(result);
        results.add(result);
      }
      cycleResults.add(<String, dynamic>{
        'outingIndex': outing + 1,
        'results': outingLoot,
      });
    }
    final durationPerOuting = config.explorationInt(
        'explorationDurationPerOuting',
        config.explorationInt('durationSeconds', 25));
    exploration['activeRun'] = <String, dynamic>{
      'id': 'exploration-$now-$sectorId',
      'sectorId': sectorId,
      'startedAt': now,
      'endsAt': now + durationPerOuting * outingCount * 1000,
      'status': 'IN_PROGRESS',
      'results': results,
      'cycleResults': cycleResults,
      'outingCount': outingCount,
      'durationPerOuting': durationPerOuting,
      'totalDuration': durationPerOuting * outingCount,
      'specificSearchEnabled': specificSearchType != null,
      'specificSearchType': specificSearchType,
      'companionPtipoteId': companionPtipoteId,
      'trackerCarryBonus': trackerBonus,
      'typeLootBias': typeBias,
      'slots': slots,
      'playerStaminaCost': staminaCost,
      'companionStaminaCost': companionStaminaCost,
      'trackerXpAwarded': false,
    };
    return state;
  }

  static Map<String, dynamic>? _rollExplorationLoot(Map sector,
      Map<String, dynamic> definition, ElevageConfig config, int seed,
      {String? typeBias, String? specificSearchType}) {
    final table =
        (definition['lootTable'] as List).whereType<Map>().where((entry) {
      if (entry['enabled'] == false) return false;
      if (!_isExplorationFamily(entry, specificSearchType)) return false;
      final costs = _explorationLootCosts(entry, config,
          specificSearchType: specificSearchType);
      return ((sector['organic'] as num?)?.toInt() ?? 0) >= costs['organic']! &&
          ((sector['mineral'] as num?)?.toInt() ?? 0) >= costs['mineral']!;
    }).toList(growable: false);
    if (table.isEmpty) return null;
    final total = table.fold<int>(0,
        (sum, entry) => sum + _explorationLootWeight(entry, typeBias, config));
    if (total <= 0) return null;
    var cursor = Random(seed).nextInt(total);
    final selected = table.firstWhere((entry) {
      cursor -= _explorationLootWeight(entry, typeBias, config);
      return cursor < 0;
    });
    final costs = _explorationLootCosts(selected, config,
        specificSearchType: specificSearchType);
    sector['organic'] =
        max(0, ((sector['organic'] as num?)?.toInt() ?? 0) - costs['organic']!);
    sector['mineral'] =
        max(0, ((sector['mineral'] as num?)?.toInt() ?? 0) - costs['mineral']!);
    return <String, dynamic>{
      'resourceId': selected['resourceId'],
      'resourceCategory': selected['resourceCategory'],
    };
  }

  static int _explorationLootWeight(
      Map entry, String? typeBias, ElevageConfig config) {
    final base = (entry['weight'] as num?)?.toInt() ?? 0;
    if (base <= 0 || typeBias == null) return base;
    final resource = entry['resourceId'] as String? ?? '';
    final compatible = switch (typeBias) {
      'VEGETAL' => const <String>{
          'LEAF',
          'ROOT',
          'FRUIT',
          'MOSS',
          'ALGAE',
          'SEED'
        }.contains(resource),
      'MINERAL' => const <String>{
          'MINERAL',
          'IRON',
          'LIMESTONE',
          'QUARTZ',
          'SALT'
        }.contains(resource),
      'FUNGAL' => const <String>{'MUSHROOM', 'SPORE', 'MOSS', 'ORGANIC'}
          .contains(resource),
      _ => false,
    };
    if (!compatible) return base;
    final multipliers =
        config.explorationConfig['typeLootBiasMultipliers'] as Map?;
    final multiplier = (multipliers?[typeBias] as num?)?.toDouble() ?? 1.5;
    return max(1, (base * multiplier).round());
  }

  static Map<String, int> _explorationLootCosts(Map entry, ElevageConfig config,
      {String? specificSearchType}) {
    if (specificSearchType == 'ORGANIC') {
      return <String, int>{
        'organic': config.explorationInt('specificOrganicStockCostPercent',
            config.explorationInt('specificOrganicCost', 5)),
        'mineral': 0,
      };
    }
    if (specificSearchType == 'MINERAL') {
      return <String, int>{
        'organic': 0,
        'mineral': config.explorationInt('specificMineralStockCost',
            config.explorationInt('specificMineralCost', 3)),
      };
    }
    // Multi-sorties en recherche générale ne distinguent plus la rareté de
    // l'objet pour son prélèvement écologique : le coût dépend de la famille
    // choisie par le joueur. L'ancienne lecture déclarative reste disponible
    // via explorationLootCostsFor pour les diagnostics du Dashboard.
    final category = entry['resourceCategory'] as String? ?? 'SPECIAL';
    if (category == 'GENERIC_ORGANIC' || category == 'ORGANIC_SPECIFIC') {
      return <String, int>{
        'organic': config.explorationInt('genericOrganicStockCostPercent',
            config.explorationInt('genericOrganicCost', 1)),
        'mineral': 0,
      };
    }
    if (category == 'GENERIC_MINERAL' || category == 'MINERAL_SPECIFIC') {
      return <String, int>{
        'organic': 0,
        'mineral': config.explorationInt('genericMineralStockCost',
            config.explorationInt('genericMineralCost', 1)),
      };
    }
    return <String, int>{'organic': 0, 'mineral': 0};
  }

  static bool _isExplorationFamily(Map entry, String? specificSearchType) {
    if (specificSearchType == null) return true;
    final category = entry['resourceCategory'] as String? ?? 'SPECIAL';
    return switch (specificSearchType) {
      'ORGANIC' =>
        category == 'GENERIC_ORGANIC' || category == 'ORGANIC_SPECIFIC',
      'MINERAL' =>
        category == 'GENERIC_MINERAL' || category == 'MINERAL_SPECIFIC',
      _ => false,
    };
  }

  static Map<String, int> _legacyExplorationLootCosts(
      Map entry, ElevageConfig config) {
    final category = entry['resourceCategory'] as String? ?? 'SPECIAL';
    final organic = entry['organicCost'] as num?;
    final mineral = entry['mineralCost'] as num?;
    if (organic != null || mineral != null) {
      return <String, int>{
        'organic': organic?.toInt() ?? 0,
        'mineral': mineral?.toInt() ?? 0
      };
    }
    return switch (category) {
      'GENERIC_ORGANIC' => <String, int>{
          'organic': config.explorationInt('genericOrganicCost', 1),
          'mineral': 0
        },
      'ORGANIC_SPECIFIC' => <String, int>{
          'organic': config.explorationInt('specificOrganicCost', 5),
          'mineral': 0
        },
      'GENERIC_MINERAL' => <String, int>{
          'organic': 0,
          'mineral': config.explorationInt('genericMineralCost', 1)
        },
      'MINERAL_SPECIFIC' => <String, int>{
          'organic': 0,
          'mineral': config.explorationInt('specificMineralCost', 3)
        },
      _ => <String, int>{'organic': 0, 'mineral': 0},
    };
  }

  /// Shared by the exploration resolver and dashboard/test diagnostics. The
  /// loot table remains declarative: no widget needs to duplicate its ecology
  /// cost rules.
  static Map<String, int> explorationLootCostsFor(
          Map<String, dynamic> entry, ElevageConfig config) =>
      _legacyExplorationLootCosts(entry, config);

  static ElevageSave claimExploration(
      ElevageSave source, int now, ElevageConfig config) {
    final state = refreshExploration(source, now, config);
    final exploration = explorationState(state);
    final run = exploration['activeRun'];
    if (run is! Map || run['status'] != 'READY') {
      throw StateError('Aucun résultat d’exploration à récupérer.');
    }
    final generic = _generic(state);
    final special = _special(state);
    for (final result in (run['results'] as List).whereType<Map>()) {
      final resource = result['resourceId'] as String?;
      if (resource == null || resource == 'EMPTY') continue;
      if (resource == 'ORGANIC' || resource == 'MINERAL') {
        final key = resource.toLowerCase();
        generic[key] = (generic[key] ?? 0) + 1;
      } else {
        special[resource] = (special[resource] ?? 0) + 1;
        final discovered = state.data['discoveredItemIds'] as List;
        if (!discovered.contains(resource)) discovered.add(resource);
      }
    }
    final companionId = run['companionPtipoteId'] as String?;
    if (companionId != null && run['trackerXpAwarded'] != true) {
      final individual = _individual(state, companionId);
      final before = trackerProfession(individual, config);
      final beforeLevel = (before['level'] as num).toInt();
      final outingCount = max(1, (run['outingCount'] as num?)?.toInt() ?? 1);
      final amount =
          config.explorationInt('trackerXpPerExploration', 10) * outingCount;
      before['xp'] = ((before['xp'] as num).toInt() + amount).clamp(0, 999999);
      (individual['professions'] as Map)['TRACKER'] = before;
      final after = trackerProfession(individual, config);
      run['trackerXpAwarded'] = true;
      run['trackerXpGained'] = amount;
      run['trackerLevelBefore'] = beforeLevel;
      run['trackerLevelAfter'] = (after['level'] as num).toInt();
      run['trackerXpAfter'] = (after['xp'] as num).toInt();
    }
    run['status'] = 'CLAIMED';
    run['claimedAt'] = now;
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

  static ElevageSave craftModule(ElevageSave source,
      ElevageModuleDefinition definition, int now, ElevageConfig config) {
    if (!definition.enabled) throw StateError('Module indisponible.');
    final state = source.copy();
    final generic = _generic(state);
    if ((generic['organic'] ?? 0) < definition.organicCost ||
        (generic['mineral'] ?? 0) < definition.mineralCost) {
      throw StateError('Ressources insuffisantes.');
    }
    generic['organic'] = generic['organic']! - definition.organicCost;
    generic['mineral'] = generic['mineral']! - definition.mineralCost;
    final instanceId = 'module-$now-${definition.id}';
    _moduleInventory(state)[instanceId] = <String, dynamic>{
      'instanceId': instanceId,
      'moduleId': definition.id,
      'craftedAt': now,
    };
    return state;
  }

  static List<Map<String, dynamic>> installedModules(
      Map structure, ElevageConfig config) {
    final raw = structure['installedModules'] as List? ?? const <dynamic>[];
    return raw.whereType<Map>().map((entry) {
      final copy = Map<String, dynamic>.from(entry);
      copy['definition'] = config.module(copy['moduleId'] as String? ?? '');
      return copy;
    }).toList(growable: false);
  }

  static ElevageSave installModule(ElevageSave source, String alcoveId,
      int slot, String moduleInstanceId, ElevageConfig config) {
    final state = source.copy();
    final structure = (_alcove(state, alcoveId)['slots'] as List)[slot];
    if (structure is! Map) throw StateError('Structure indisponible.');
    final profile = config.modulesFor(structure['definitionId'] as String);
    final inventory = _moduleInventory(state);
    final moduleInstance = inventory[moduleInstanceId] as Map?;
    if (moduleInstance == null) throw StateError('Module indisponible.');
    final module = config.module(moduleInstance['moduleId'] as String? ?? '');
    if (module == null ||
        !module.enabled ||
        !profile.allowedModuleIds.contains(module.id) ||
        !module.compatibleStructures
            .contains(structure['definitionId'] as String)) {
      throw StateError('Module incompatible.');
    }
    final installed =
        structure.putIfAbsent('installedModules', () => <dynamic>[]) as List;
    if (installed.length >= profile.moduleSlots) {
      throw StateError('Aucun emplacement de module libre.');
    }
    final count = installed
        .whereType<Map>()
        .where((entry) => entry['moduleId'] == module.id)
        .length;
    if ((!module.stackable && count > 0) ||
        count >= module.maxStacksPerStructure) {
      throw StateError('Ce module ne peut plus être cumulé.');
    }
    installed.add(Map<String, dynamic>.from(moduleInstance));
    inventory.remove(moduleInstanceId);
    return state;
  }

  static ElevageSave removeModule(
      ElevageSave source, String alcoveId, int slot, String moduleInstanceId) {
    final state = source.copy();
    final structure = (_alcove(state, alcoveId)['slots'] as List)[slot];
    if (structure is! Map) throw StateError('Structure indisponible.');
    final installed = structure['installedModules'] as List?;
    final index = installed?.indexWhere((entry) =>
            entry is Map && entry['instanceId'] == moduleInstanceId) ??
        -1;
    if (index < 0) throw StateError('Module absent.');
    final module = Map<String, dynamic>.from(installed!.removeAt(index) as Map);
    _moduleInventory(state)[moduleInstanceId] = module;
    return state;
  }

  /// Shared by zone simulation, diagnostics and the structure preview so a
  /// POWER module can never be cosmetic in one of those representations.
  static Map<String, int> effectiveEnvironmentalEffects(
      Map raw, ElevageInstallationDefinition definition, ElevageConfig config) {
    final result = <String, int>{
      'light': definition.light,
      'temperature': definition.temperature,
      'humidity': definition.humidity,
    };
    final axis = config.modulesFor(definition.id).primaryEnvironmentAxis;
    if (axis == null) return result;
    final delta = installedModules(raw, config).fold<num>(
        0,
        (sum, module) =>
            sum +
            (((module['definition'] as ElevageModuleDefinition?)
                    ?.effects['environmentMagnitudeDelta']) ??
                0));
    if (delta == 0 || result[axis] == 0) return result;
    result[axis] = result[axis]! + result[axis]!.sign * delta.round();
    return result;
  }

  static Map<String, int> _effectiveEnvironmentEffects(Map raw,
          ElevageInstallationDefinition definition, ElevageConfig config) =>
      effectiveEnvironmentalEffects(raw, definition, config);

  static ElevageStructureConsumption _effectiveConsumption(
      Map raw, ElevageStructureConsumption base, ElevageConfig config) {
    final multiplier = installedModules(raw, config).fold<num>(
        1,
        (value, module) =>
            value *
            (((module['definition'] as ElevageModuleDefinition?)
                    ?.effects['consumptionIntervalMultiplier']) ??
                1));
    if (multiplier == 1) return base;
    return base.copyWith(
        consumptionIntervalSeconds:
            max(1, (base.consumptionIntervalSeconds * multiplier).round()));
  }

  static ElevageProductionOutput _effectiveOutput(
      Map raw, ElevageProductionOutput base, ElevageConfig config) {
    final capacityDelta = installedModules(raw, config).fold<num>(
        0,
        (sum, module) =>
            sum +
            (((module['definition'] as ElevageModuleDefinition?)
                    ?.effects['stockCapacityDelta']) ??
                0));
    return base.copyWith(
        maxLocalStock: max(1, base.maxLocalStock + capacityDelta.round()));
  }

  /// Resolves output caps from the precise placed producer instance. This is
  /// shared by ticking and UI, so a Capacity module can never display a stale
  /// cap (for example 3/6 while the actual cap is 9).
  static List<ElevageProductionOutput> effectiveProducerOutputs(
      Map raw, String installationId, ElevageConfig config) {
    return config
        .outputsFor(installationId)
        .where((output) => output.enabled)
        .map((output) => _effectiveOutput(raw, output, config))
        .toList(growable: false);
  }

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
    final definition = config.installation(recipe.installationId);
    if (definition == null) throw StateError('Définition d’habitat inconnue.');
    final instanceId = '${definition.category.toLowerCase()}-$now-${recipe.id}';
    final inventory = definition.category == 'STRUCTURE'
        ? state.data['installationInventory'] as Map<String, dynamic>
        : state.data['habitatInventory'] as Map<String, dynamic>;
    inventory[instanceId] = <String, dynamic>{
      'instanceId': instanceId,
      'definitionId': recipe.installationId,
      'category': definition.category,
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
      'maintenanceState': <String, dynamic>{
        'status': 'ACTIVE',
        'reason': null,
        'lastResolvedAt': now,
      },
      'installedModules': <dynamic>[],
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
    instance['alcoveId'] = alcoveId;
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
      if (!structureIsActive(raw, config)) continue;
      final effects = _effectiveEnvironmentEffects(raw, definition, config);
      result['light'] = result['light']! + effects['light']!;
      result['temperature'] = result['temperature']! + effects['temperature']!;
      result['humidity'] = result['humidity']! + effects['humidity']!;
    }
    return result;
  }

  /// State exposed to the UI and deliberately shared with the future Mature
  /// maintenance API. A passive structure has no hidden fuel state.
  static bool structureIsActive(Map raw, ElevageConfig config) {
    final specification =
        config.consumptionFor(raw['definitionId'] as String? ?? '');
    if (!specification.enabled || specification.mode == 'NONE') return true;
    final maintenance = raw['maintenanceState'] as Map?;
    return maintenance?['status'] != 'INACTIVE_NO_RESOURCE';
  }

  static Map<String, int> getMissingResources(
      ElevageSave state, Map raw, ElevageConfig config) {
    final specification =
        config.consumptionFor(raw['definitionId'] as String? ?? '');
    if (!specification.enabled || specification.mode == 'NONE') {
      return const <String, int>{};
    }
    final generic = _generic(state);
    if (specification.mode == 'ENERGY') {
      final alcoveId = raw['alcoveId'] as String?;
      final alcove = alcoveId == null ? null : _alcove(state, alcoveId);
      final battery = alcove?['batterySlot'];
      final available = ((alcove?['localEnergy'] as num?)?.toInt() ?? 0) +
          ((battery is Map ? battery['currentEnergy'] : 0) as num? ?? 0)
              .toInt();
      final missingEnergy =
          max(0, specification.energyCost - available.toInt());
      return missingEnergy == 0
          ? const <String, int>{}
          : <String, int>{'ENERGY': missingEnergy};
    }
    final missing = <String, int>{};
    specification.resourceCosts.forEach((itemId, quantity) {
      final key = itemId.toLowerCase();
      final available = generic[key] ?? 0;
      if (available < quantity) missing[itemId] = quantity - available;
    });
    return missing;
  }

  static void _refreshStructureMaintenance(
      ElevageSave state, int now, ElevageConfig config) {
    for (final alcove in state.data['alcoves'] as List) {
      final slots = (alcove as Map)['slots'] as List? ?? const <dynamic>[];
      for (final raw in slots.whereType<Map>()) {
        final specification = _effectiveConsumption(
            raw,
            config.consumptionFor(raw['definitionId'] as String? ?? ''),
            config);
        if (!specification.enabled || specification.mode == 'NONE') {
          continue;
        }
        final intervalMs = specification.consumptionIntervalSeconds * 1000;
        if (intervalMs <= 0) continue;
        final maintenance = raw.putIfAbsent(
            'maintenanceState',
            () => <String, dynamic>{
                  'status': 'ACTIVE',
                  'reason': null,
                  'lastResolvedAt': now,
                }) as Map;
        final last = (maintenance['lastResolvedAt'] as num?)?.toInt() ?? now;
        if (maintenance['status'] == 'INACTIVE_NO_RESOURCE') {
          // A refill never back-bills the time spent paused. One successful
          // cycle restarts the structure, then its normal clock resumes.
          if (_consumeMaintenanceCost(state, alcove, specification, config)) {
            maintenance['status'] = 'ACTIVE';
            maintenance['reason'] = null;
            maintenance['lastResolvedAt'] = now;
          }
          continue;
        }
        final cycles = max(0, (now - last) ~/ intervalMs);
        if (cycles == 0) continue;
        var consumedCycles = 0;
        while (consumedCycles < cycles &&
            _consumeMaintenanceCost(state, alcove, specification, config)) {
          consumedCycles++;
        }
        if (consumedCycles < cycles) {
          maintenance['status'] = 'INACTIVE_NO_RESOURCE';
          maintenance['reason'] = _maintenanceReason(specification);
          // Stop precisely at depletion; later offline time is paused.
          maintenance['lastResolvedAt'] = now;
        } else {
          maintenance['status'] = 'ACTIVE';
          maintenance['reason'] = null;
          maintenance['lastResolvedAt'] = last + consumedCycles * intervalMs;
        }
      }
    }
  }

  /// Advances every installed durable generator from persisted timestamps.
  /// Each completed interval consumes one tank recipe and fills local Energy;
  /// bounded loops make offline refresh deterministic and cap-safe.
  static void _refreshBiogenerators(
      ElevageSave state, int now, ElevageConfig config) {
    final cycleMs =
        Duration(seconds: config.biogeneratorCycleSeconds).inMilliseconds;
    for (final rawAlcove in state.data['alcoves'] as List) {
      final alcove = rawAlcove as Map;
      final generator = alcove['biogeneratorSlot'];
      if (generator is! Map) continue;
      alcove['localEnergy'] = ((alcove['localEnergy'] as num?)?.toInt() ?? 0)
          .clamp(0, config.energyStorageMax);
      // A pre-22.3 generator had no cycle timestamp. Start one due cycle on
      // migration so already-filled tanks remain useful without backfilling
      // unlimited historical energy.
      final startedAt =
          (generator['cycleStartedAt'] as num?)?.toInt() ?? now - cycleMs;
      generator['cycleStartedAt'] = startedAt;
      final dueCycles = max(0, (now - startedAt) ~/ cycleMs);
      var produced = 0;
      while (produced < dueCycles &&
          _runBiogeneratorCycle(generator, alcove, config)) {
        produced++;
      }
      if (produced < dueCycles) {
        // The first unavailable cycle waits for a fresh interval after tanks
        // are refilled or capacity is freed; it never accrues hidden debt.
        generator['cycleStartedAt'] = now;
      } else if (produced > 0) {
        generator['cycleStartedAt'] = startedAt + produced * cycleMs;
      }
    }
  }

  static bool _consumeMaintenanceCost(ElevageSave state, Map alcove,
      ElevageStructureConsumption specification, ElevageConfig config) {
    final generic = _generic(state);
    if (specification.mode == 'ENERGY') {
      // The generator fills the shared local store asynchronously. Maintenance
      // never converts tank matter on demand: a structure pauses until a
      // completed production cycle (or its backup battery) can cover its cost.
      final initialLocal = (alcove['localEnergy'] as num?)?.toInt() ?? 0;
      final initialBattery = alcove['batterySlot'];
      final batteryPotential = initialBattery is Map
          ? (initialBattery['currentEnergy'] as num?)?.toInt() ?? 0
          : 0;
      if (initialLocal + batteryPotential < specification.energyCost) {
        return false;
      }
      var remaining = specification.energyCost;
      final localEnergy = initialLocal;
      final consumedLocal = min(localEnergy, remaining);
      alcove['localEnergy'] = localEnergy - consumedLocal;
      remaining -= consumedLocal;
      final battery = alcove['batterySlot'];
      if (remaining > 0 && battery is Map) {
        final charge = (battery['currentEnergy'] as num?)?.toInt() ?? 0;
        final consumedBattery = min(charge, remaining);
        battery['currentEnergy'] = charge - consumedBattery;
        remaining -= consumedBattery;
        if ((battery['currentEnergy'] as num).toInt() <= 0) {
          alcove['batterySlot'] = null;
        }
      }
      return remaining == 0;
    }
    if (specification.mode == 'DIRECT_RESOURCE' ||
        specification.mode == 'MULTI_RESOURCE') {
      if (specification.resourceCosts.entries.any(
          (entry) => (generic[entry.key.toLowerCase()] ?? 0) < entry.value)) {
        return false;
      }
      specification.resourceCosts.forEach((itemId, quantity) {
        final key = itemId.toLowerCase();
        generic[key] = generic[key]! - quantity;
      });
    }
    return true;
  }

  static String _maintenanceReason(ElevageStructureConsumption specification) {
    if (specification.mode == 'ENERGY') return 'Manque d’Énergie';
    if (specification.resourceCosts.length == 1) {
      final item = specification.resourceCosts.keys.single;
      return 'Manque d’${item == 'ORGANIC' ? 'Organique' : item}';
    }
    return 'Ressources insuffisantes';
  }

  static ElevageSave refreshAlcove(
      ElevageSave source, String alcoveId, int now, ElevageConfig config) {
    final state = source.copy();
    _refreshBiogenerators(state, now, config);
    _refreshStructureMaintenance(state, now, config);
    final alcove = _alcove(state, alcoveId);
    for (final raw in alcove['slots'] as List) {
      if (raw is! Map) continue;
      final definition = config.installation(raw['definitionId'] as String);
      if (definition == null) continue;
      if (!structureIsActive(raw, config)) continue;
      if (!definition.productive) {
        raw.remove('productionState');
        continue;
      }
      final production = raw.putIfAbsent(
          'productionState',
          () => <String, dynamic>{
                'lastResolvedAt': now,
                'availableByItemId': <String, int>{}
              }) as Map;
      final configuredOutputs = config.outputsFor(definition.id);
      final stock = production['availableByItemId'] as Map;
      if (configuredOutputs.isNotEmpty) {
        final lastByItem = production.putIfAbsent(
            'lastResolvedAtByItemId', () => <String, int>{}) as Map;
        for (final output in configuredOutputs
            .where((entry) => entry.enabled)
            .map((entry) => _effectiveOutput(raw, entry, config))) {
          // Existing saves carry one timestamp for the whole producer. Use it
          // exactly once as the seed for the new per-output clocks.
          final last = (lastByItem[output.resourceId] as num?)?.toInt() ??
              (production['lastResolvedAt'] as num?)?.toInt() ??
              now;
          final cycles =
              max(0, (now - last) ~/ (output.productionSeconds * 1000));
          if (cycles == 0) continue;
          final current = (stock[output.resourceId] as num?)?.toInt() ?? 0;
          // Removing Capacity must never delete an already harvested/grown
          // stock. Above the new cap, production simply remains paused.
          if (current < output.maxLocalStock) {
            stock[output.resourceId] = min(output.maxLocalStock,
                current + cycles * output.quantityPerCycle);
          }
          lastByItem[output.resourceId] =
              last + cycles * output.productionSeconds * 1000;
        }
      } else {
        final last = production['lastResolvedAt'] as int? ?? now;
        final cycles =
            max(0, (now - last) ~/ (config.productionIntervalSeconds * 1000));
        if (cycles > 0) {
          definition.outputs.forEach((item, quantity) {
            final current = (stock[item] as num?)?.toInt() ?? 0;
            stock[item] =
                min(config.productionMaxStock, current + cycles * quantity);
          });
          production['lastResolvedAt'] =
              last + cycles * config.productionIntervalSeconds * 1000;
        }
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
      final candidates = <String>[
        favorite,
        favorite == 'ROOT' ? 'LEAF' : 'ROOT',
        if (individual['family'] == 'FUNGAL') ...<String>[
          'MUSHROOM',
          'FRUIT',
          'MOSS',
          'LEAF',
          'ROOT',
        ],
        'ALGAE',
        'MOSS',
        'MUSHROOM'
      ].where((item) => canEat(individual, item, config)).toList();
      final food = _consumeLocal(alcove, candidates);
      if (food != null) {
        final current = refreshSatiety(individual, now, config);
        setSatiety(individual, current + config.foodSatietyValue(food), now);
        care['lastMealAt'] = now;
        care['autonomousMealCount'] = (care['autonomousMealCount'] as int) + 1;
        care['lastAutonomousAt'] = now;
        _memory(state, residentId, 'FIRST_AUTONOMOUS_MEAL', now);
        _interaction(individual, 'AUTONOMOUS_MEAL', initiative: 1);
        _adjustWellbeing(individual, initiative >= .5 ? 3 : 1, now);
      }
    }
    final structural = mayActAutonomously
        ? _consumeLocal(
            alcove,
            structuralResourcesForFamily(
                    individual['family'] as String? ?? 'MINERAL')
                .where((item) => canAbsorb(individual, item, config))
                .toList())
        : null;
    if (structural != null) {
      final intake =
          individual['care']['structuralIntake'] as Map<String, dynamic>;
      final gain = structural == 'IRON' ? 2 : 1;
      intake['total'] = (intake['total'] as int) + gain;
      final byMaterial = intake['byMaterial'] as Map;
      byMaterial[structural] =
          ((byMaterial[structural] as num?)?.toInt() ?? 0) + gain;
      care['lastAutonomousAt'] = now;
      _interaction(individual, 'AUTONOMOUS_STRUCTURE', initiative: 1);
      _adjustWellbeing(individual, initiative >= .5 ? 2 : 1, now);
    }
    return state;
  }

  static ElevageSave harvestLocal(ElevageSave source, String alcoveId, int slot,
      String itemId, int now, ElevageConfig config) {
    final state = source.copy();
    final slots = _alcove(state, alcoveId)['slots'] as List;
    if (slot < 0 || slot >= slots.length || slots[slot] is! Map) {
      throw StateError('Installation indisponible.');
    }
    final definition =
        config.installation((slots[slot] as Map)['definitionId'] as String);
    if (definition == null || !definition.productive) {
      throw StateError('Cette structure ne produit pas de ressource.');
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

  /// Atomic Recycler V1 transaction. Only specific reserve resources can be
  /// reduced; Organic and Mineral are terminal outputs and have no rule.
  static ElevageSave recycle(
      ElevageSave source, String itemId, int quantity, ElevageConfig config) {
    final rule = config.recycleRule(itemId);
    if (quantity <= 0 ||
        rule == null ||
        !rule.recyclable ||
        rule.recycleOutputType == null ||
        rule.recycleOutputQuantity <= 0) {
      throw StateError('Cette ressource ne peut pas être recyclée.');
    }
    final state = source.copy();
    final special = _special(state);
    if ((special[itemId] ?? 0) < quantity) {
      throw StateError('Quantité insuffisante dans la Réserve.');
    }
    final outputKey = rule.recycleOutputType!.toLowerCase();
    if (outputKey != 'organic' && outputKey != 'mineral') {
      throw StateError('Sortie de recyclage invalide.');
    }
    final generic = _generic(state);
    special[itemId] = special[itemId]! - quantity;
    generic[outputKey] =
        (generic[outputKey] ?? 0) + quantity * rule.recycleOutputQuantity;
    return state;
  }

  /// Évalue les besoins sans les confondre avec une sollicitation. Une Request
  /// n'existe que lorsque l'individu choisit réellement de communiquer.
  static ElevageSave refreshRequest(
      ElevageSave source, String id, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, id);
    refreshSatiety(individual, now, config);
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
    final signal = switch (stage) {
      // Hunger is a body need, not a request for the current favourite food.
      // Detailed food requests remain a later feature.
      'BABY' || 'INTERMEDIATE' || 'MATURE' => 'HUNGER',
      _ => 'HUNGER',
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
    // Repeated experiences, including Baby experiences, are what make the
    // HUNGER word learnable after metamorphosis.
    _recordConceptExposure(individual, 'HUNGER');
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
    // Free furniture and decorations are Alcôve-bound too. They do not leak
    // into a fresh Alcôve after a move-out.
    (state.data['habitatItemsByAlcoveId'] as Map).remove(alcoveId);
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
    if (stage == 'BABY') {
      final knowledge = knowledgeEntries(individual);
      final totalObservations = knowledge.fold<int>(
          0,
          (sum, entry) =>
              sum + ((entry['observationCount'] as num?)?.toInt() ?? 0));
      final hypotheses = knowledge
          .where((entry) =>
              entry['status'] == 'HYPOTHESIS' || entry['status'] == 'CONFIRMED')
          .length;
      final confirmations = knowledge
          .where((entry) =>
              entry['status'] == 'CONFIRMED' &&
              (entry['conceptId'] as String?)?.isNotEmpty == true)
          .length;
      return totalObservations >= config.maturationObservationRequirement &&
          hypotheses >= config.maturationHypothesisRequirement &&
          confirmations >= config.maturationConfirmationRequirement;
    }
    return discovery['status'] == 'CONFIRMED' &&
        (care['metabolicMeals'] as int) >= 5 &&
        ((care['structuralIntake'] as Map)['total'] as int) >= 6 &&
        (care['autonomousMealCount'] as int) > 0 &&
        (evidence['personalityEvents'] as int) >= 5;
  }

  /// Shared source of truth for the Tam Tam animation and touch validation.
  /// A beat target is at `(index + 1) × interval` from the same start stamp
  /// used by the UI, so rapid taps outside a target window cannot succeed.
  static int tamTamBeatTargetMs(int beatIndex, ElevageConfig config) =>
      (beatIndex + 1) * config.tamTamBeatIntervalMs;

  static String tamTamTapGrade(
      int elapsedMs, int beatIndex, ElevageConfig config) {
    final delta = (elapsedMs - tamTamBeatTargetMs(beatIndex, config)).abs();
    if (delta <= config.tamTamPerfectWindowMs) return 'PERFECT';
    if (delta <= config.tamTamGoodWindowMs) return 'GOOD';
    return 'MISS';
  }

  static bool tamTamSucceeded(Iterable<String> grades, ElevageConfig config) =>
      grades.where((grade) => grade == 'PERFECT' || grade == 'GOOD').length >=
      config.tamTamRequiredSuccessfulBeats;

  static ElevageSave metamorphose(
      ElevageSave source, String id, int now, ElevageConfig config) {
    if (!metamorphosisAvailable(source, id, now, config)) {
      throw StateError('Les prérequis de métamorphose ne sont pas remplis.');
    }
    final state = source.copy();
    final individual = _individual(state, id);
    refreshSatiety(individual, now, config);
    final lifecycle = individual['lifecycle'] as Map;
    final next = lifecycle['stage'] == 'BABY' ? 'INTERMEDIATE' : 'MATURE';
    lifecycle['stage'] = next;
    lifecycle['stageEnteredAt'] = now;
    if (next == 'INTERMEDIATE') {
      individual['loanOffer'] = <String, dynamic>{
        'offeredAt': now,
        'choices': _loanChoicesFor(individual),
        'selectedStructureId': null,
      };
    } else {
      final loan = individual['loan'] as Map?;
      if (loan != null && loan['returnDueAt'] == null) {
        loan['returnDueAt'] = now +
            config.loanReturnDelayDays * const Duration(days: 1).inMilliseconds;
        (state.data['pendingNotifications'] as List).add(<String, dynamic>{
          'id': 'loan-return-$id',
          'type': 'LOAN_RETURN_SCHEDULED',
          'name': individual['name'],
          'createdAt': now,
          'acknowledgedAt': null,
        });
      }
    }
    _applyTrustChange(state,
        amount: next == 'INTERMEDIATE'
            ? config.trustGainIntermediate
            : config.trustGainMature,
        now: now,
        reasonType: next == 'INTERMEDIATE'
            ? 'INTERMEDIATE_EVOLUTION'
            : 'MATURE_EVOLUTION',
        ptipoteId: id,
        text: _trustText(
            next == 'INTERMEDIATE'
                ? 'INTERMEDIATE_EVOLUTION'
                : 'MATURE_EVOLUTION',
            individual['name'] as String?),
        eventId: 'evolution-$id-$next');
    _memory(
        state,
        id,
        next == 'INTERMEDIATE' ? 'FIRST_METAMORPHOSIS' : 'SECOND_METAMORPHOSIS',
        now);
    return state;
  }

  static List<String> _loanChoicesFor(Map individual) =>
      switch ('${individual['family']}_${individual['nature']}') {
        'VEGETAL_PHOTOSYNTHESIS' => <String>[
            'CULTURE_POTAGERE',
            'BOSQUET_SYMBIOTIQUE'
          ],
        'FUNGAL_DECOMPOSITION' => <String>[
            'SUPPORT_FONGIQUE',
            'COLONIE_MYCELIENNE'
          ],
        _ => <String>['FOUR_BIO_ORGANIQUE', 'FORMATION_METALLIQUE'],
      };

  static ElevageSave chooseJuvenileLoan(ElevageSave source, String id,
      String structureId, int now, ElevageConfig config) {
    final state = source.copy();
    final individual = _individual(state, id);
    final offer = individual['loanOffer'] as Map?;
    if (offer == null ||
        offer['selectedStructureId'] != null ||
        !(offer['choices'] as List).contains(structureId)) {
      throw StateError('Ce prêt n’est pas disponible.');
    }
    final definition = config.installation(structureId);
    if (definition == null || definition.category != 'STRUCTURE') {
      throw StateError('Structure de prêt invalide.');
    }
    final instanceId = 'loan-$id-$now';
    (state.data['installationInventory'] as Map<String, dynamic>)[instanceId] =
        <String, dynamic>{
      'instanceId': instanceId,
      'definitionId': structureId,
      'category': 'STRUCTURE',
      'acquisitionMode': 'LOANED_FROM_REFUGE',
      'loanedFromRefuge': true,
      'loanOwnerIndividualId': id,
      'craftedAt': now,
      'installedModules': <dynamic>[],
      'maintenanceState': <String, dynamic>{
        'status': 'ACTIVE',
        'reason': null,
        'lastResolvedAt': now,
      },
    };
    offer['selectedStructureId'] = structureId;
    individual['loan'] = <String, dynamic>{
      'instanceId': instanceId,
      'structureId': structureId,
      'selectedAt': now,
      'returnDueAt': null,
    };
    return state;
  }

  static String? communication(
      ElevageSave state, String id, int now, ElevageConfig config) {
    final individual = _individual(state, id);
    final stage = individual['lifecycle']['stage'] as String;
    if (stage == 'BABY') return null;
    if (hunger(state, id, now, config) == 'HUNGRY' ||
        hunger(state, id, now, config) == 'VERY_HUNGRY') {
      return 'HUNGER';
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
  static Map<String, dynamic> _moduleInventory(ElevageSave state) =>
      Map<String, dynamic>.from(state.data['moduleInventory'] as Map)
        ..also((map) => state.data['moduleInventory'] = map);

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

  static String knowledgeConceptId(String type,
      {String? relatedItemId, String? relatedEnvironmentAxis}) {
    return switch (type) {
      'STRUCTURAL_REACTION' when relatedItemId == 'IRON' => 'IRON_AFFINITY',
      'STRUCTURAL_REACTION' =>
        '${relatedItemId ?? 'MINERAL'}_STRUCTURE_AFFINITY',
      'STRUCTURAL_AVOIDED' => '${relatedItemId ?? 'MINERAL'}_AVOIDANCE',
      'FOOD_FAVORITE' => '${relatedItemId ?? 'FOOD'}_FOOD_PREFERENCE',
      'FOOD_ACCEPTED' => '${relatedItemId ?? 'FOOD'}_FOOD_ACCEPTANCE',
      'LIGHT_SHADE' => 'LIGHT_PREFERENCE',
      'HUMIDITY_AVOIDANCE' => 'HUMIDITY_PREFERENCE',
      'FOLLOW' || 'CUDDLE' || 'CUDDLE_SPACE' => 'PLAYER_CONTACT',
      'REQUEST_FOOD' => 'FOOD_NEED',
      _ when relatedEnvironmentAxis != null =>
        '${relatedEnvironmentAxis.toUpperCase()}_PREFERENCE',
      _ => type,
    };
  }

  static List<Map<String, dynamic>> knowledgeEntries(Map individual) {
    final journal = individual['observationJournal'] as Map?;
    final knowledge =
        journal?['knowledge'] as Map? ?? const <dynamic, dynamic>{};
    return knowledge.values
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  static ElevageSave recordKnowledgeObservation(ElevageSave source,
      String individualId, String conceptId, int now, ElevageConfig config) {
    final state = source.copy();
    _recordKnowledgeObservation(
        _individual(state, individualId), conceptId, now, config);
    return state;
  }

  static void _recordConceptExposure(Map individual, String conceptId) {
    final exposures = individual.putIfAbsent(
        'conceptExposures', () => <String, dynamic>{}) as Map;
    final entry = exposures.putIfAbsent(
        conceptId,
        () => <String, dynamic>{
              'conceptId': conceptId,
              'total': 0,
              'baby': 0,
              'juvenile': 0,
            }) as Map;
    entry['total'] = ((entry['total'] as num?)?.toInt() ?? 0) + 1;
    final stage =
        ((individual['lifecycle'] as Map?)?['stage'] as String?) ?? 'BABY';
    final key = stage == 'BABY' ? 'baby' : 'juvenile';
    entry[key] = ((entry[key] as num?)?.toInt() ?? 0) + 1;
  }

  static void _recordKnowledgeObservation(
      Map individual, String conceptId, int now, ElevageConfig config) {
    final journal = individual['observationJournal'] as Map;
    final knowledge = journal.putIfAbsent(
        'knowledge', () => <String, dynamic>{}) as Map<String, dynamic>;
    final entry = knowledge.putIfAbsent(
        conceptId,
        () => <String, dynamic>{
              'conceptId': conceptId,
              'firstObservedAt': now,
              'lastObservedAt': now,
              'observationCount': 0,
              'hypothesisEvidence': 0,
              'status': 'OBSERVED',
            }) as Map;
    entry['lastObservedAt'] = now;
    if (entry['status'] == 'CONFIRMED') return;
    entry['observationCount'] =
        ((entry['observationCount'] as num?)?.toInt() ?? 0) + 1;
    final observationNumber = (entry['observationCount'] as num).toInt();
    _queueTrustEvent(individual,
        reasonType: 'OBSERVATION',
        eventId:
            'observation-${individual['id']}-$conceptId-$observationNumber',
        timestamp: now,
        conceptId: conceptId);
    if (entry['status'] == 'HYPOTHESIS') {
      entry['hypothesisEvidence'] =
          ((entry['hypothesisEvidence'] as num?)?.toInt() ?? 0) + 1;
      if ((entry['hypothesisEvidence'] as int) >=
          config.evidenceForConfirmation) {
        entry['status'] = 'CONFIRMED';
        entry['confirmedAt'] = now;
        _queueTrustEvent(individual,
            reasonType: 'DISCOVERY',
            eventId: 'discovery-${individual['id']}-$conceptId',
            timestamp: now,
            conceptId: conceptId);
      }
      return;
    }
    if ((entry['observationCount'] as int) >=
        config.observationsForHypothesis) {
      entry['status'] = 'HYPOTHESIS';
      entry['hypothesisCreatedAt'] = now;
      entry['hypothesisEvidence'] = 0;
      _queueTrustEvent(individual,
          reasonType: 'HYPOTHESIS',
          eventId: 'hypothesis-${individual['id']}-$conceptId',
          timestamp: now,
          conceptId: conceptId);
    }
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
    if (evidence != existing) {
      final concept = knowledgeConceptId(type,
          relatedItemId: relatedItemId,
          relatedEnvironmentAxis: relatedEnvironmentAxis);
      _recordConceptExposure(individual, concept);
      _recordKnowledgeObservation(individual, concept, now, rules);
    }
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

  static void _appendTrustHistory(Map<String, dynamic> progress,
      {required int timestamp,
      required int delta,
      required String reasonType,
      String? ptipoteId,
      String? text,
      String? eventId}) {
    final history =
        progress.putIfAbsent('trustHistory', () => <dynamic>[]) as List;
    history.add(<String, dynamic>{
      'id': eventId ?? 'trust-$timestamp-${history.length}',
      'timestamp': timestamp,
      'delta': delta,
      'reasonType': reasonType,
      if (ptipoteId != null) 'ptipoteId': ptipoteId,
      if (text != null) 'text': text,
    });
    // A compact audit trail is sufficient for the prototype and avoids an
    // unbounded save growth from ordinary observations.
    const maxEntries = 120;
    if (history.length > maxEntries) {
      history.removeRange(0, history.length - maxEntries);
    }
  }

  static bool _applyTrustChange(ElevageSave state,
      {required int amount,
      required int now,
      required String reasonType,
      String? ptipoteId,
      String? text,
      String? eventId}) {
    final progress = _refugeProgress(state);
    final eventIds = Map<String, dynamic>.from(progress.putIfAbsent(
        'trustEventIds', () => <String, dynamic>{}) as Map);
    if (eventId != null && eventIds.containsKey(eventId)) return false;
    final before = trust(state);
    final after = max(0, before + amount);
    final effectiveDelta = after - before;
    if (eventId != null) {
      eventIds[eventId] = now;
      progress['trustEventIds'] = eventIds;
    }
    progress['trust'] = after;
    progress['contribution'] = after;
    if (effectiveDelta != 0) {
      _appendTrustHistory(progress,
          timestamp: now,
          delta: effectiveDelta,
          reasonType: reasonType,
          ptipoteId: ptipoteId,
          text: text,
          eventId: eventId);
    }
    return effectiveDelta != 0;
  }

  static void _queueTrustEvent(Map individual,
      {required String reasonType,
      required String eventId,
      required int timestamp,
      required String conceptId}) {
    final events =
        individual.putIfAbsent('pendingTrustEvents', () => <dynamic>[]) as List;
    if (events.whereType<Map>().any((event) => event['eventId'] == eventId)) {
      return;
    }
    events.add(<String, dynamic>{
      'reasonType': reasonType,
      'eventId': eventId,
      'timestamp': timestamp,
      'conceptId': conceptId,
    });
  }

  static void _flushPendingTrustEvents(
      ElevageSave state, int now, ElevageConfig config) {
    final individuals = state.data['individuals'] as Map<String, dynamic>;
    for (final raw in individuals.values.whereType<Map>()) {
      final individual = Map<String, dynamic>.from(raw);
      final id = individual['id'] as String? ?? '';
      final events = individual['pendingTrustEvents'] as List?;
      if (events == null || events.isEmpty) continue;
      for (final rawEvent in events.whereType<Map>()) {
        final reason = rawEvent['reasonType'] as String? ?? 'OBSERVATION';
        final gain = switch (reason) {
          'OBSERVATION' => config.trustGainObservation,
          'HYPOTHESIS' => config.trustGainHypothesis,
          'DISCOVERY' => config.trustGainDiscovery,
          _ => 0,
        };
        _applyTrustChange(state,
            amount: gain,
            now: (rawEvent['timestamp'] as num?)?.toInt() ?? now,
            reasonType: reason,
            ptipoteId: id,
            text: _trustText(reason, individual['name'] as String?),
            eventId: rawEvent['eventId'] as String?);
      }
      individual['pendingTrustEvents'] = <dynamic>[];
      individuals[id] = individual;
    }
  }

  static void _applyCriticalWellbeingTrustPenalties(
      ElevageSave state, int now, ElevageConfig config) {
    final periodMs = config.criticalWellbeingPenaltyHours *
        const Duration(hours: 1).inMilliseconds;
    final individuals = state.data['individuals'] as Map<String, dynamic>;
    for (final raw in individuals.values.whereType<Map>()) {
      final individual = Map<String, dynamic>.from(raw);
      final id = individual['id'] as String? ?? '';
      final wellbeing = individual['wellbeing'] as Map?;
      final value = (wellbeing?['value'] as num?)?.toInt() ?? 60;
      if (value >= config.criticalWellbeingThreshold) {
        individual.remove('criticalWellbeingSince');
        individuals[id] = individual;
        continue;
      }
      final criticalSince =
          (individual['criticalWellbeingSince'] as num?)?.toInt() ?? now;
      individual['criticalWellbeingSince'] = criticalSince;
      var lastPenalty =
          (individual['lastCriticalWellbeingTrustPenaltyAt'] as num?)
                  ?.toInt() ??
              criticalSince;
      while (now - lastPenalty >= periodMs) {
        lastPenalty += periodMs;
        _applyTrustChange(state,
            amount: -config.criticalWellbeingTrustPenalty,
            now: lastPenalty,
            reasonType: 'CRITICAL_WELLBEING',
            ptipoteId: id,
            text:
                'Bien-être critique de ${individual['name'] ?? 'ce P’TIPOTE'} pendant 24 h.',
            eventId: 'critical-wellbeing-$id-$lastPenalty');
      }
      individual['lastCriticalWellbeingTrustPenaltyAt'] = lastPenalty;
      individuals[id] = individual;
    }
  }

  static String _trustText(String reasonType, String? name) =>
      switch (reasonType) {
        'ADOPTION' => 'Adoption de ${name ?? 'ce P’TIPOTE'}',
        'OBSERVATION' => 'Nouvelle observation',
        'HYPOTHESIS' => 'Nouvelle hypothèse',
        'DISCOVERY' => 'Découverte confirmée',
        'INTERMEDIATE_EVOLUTION' =>
          '${name ?? 'Ce P’TIPOTE'} est devenu Juvénile',
        'MATURE_EVOLUTION' => '${name ?? 'Ce P’TIPOTE'} est devenu Mature',
        _ => 'Mise à jour de Confiance',
      };

  static Map<String, dynamic> _refugeProgress(ElevageSave state) =>
      Map<String, dynamic>.from(state.data['refugeProgress'] as Map)
        ..also((map) => state.data['refugeProgress'] = map);

  static Map<String, dynamic> _batteryInventory(ElevageSave state) =>
      Map<String, dynamic>.from(state.data['batteryInventory'] as Map)
        ..also((map) => state.data['batteryInventory'] = map);

  static Map<String, dynamic> _biogeneratorInventory(ElevageSave state) =>
      Map<String, dynamic>.from(state.data['biogeneratorInventory'] as Map)
        ..also((map) => state.data['biogeneratorInventory'] = map);

  static Map<String, dynamic> _newBiogenerator(String id, int now) =>
      <String, dynamic>{
        'instanceId': id,
        'definitionId': 'BIOGENERATOR',
        'installedAt': now,
        'cycleStartedAt': now,
        'tanks': <String, int>{'organic': 0, 'mineral': 0},
        'installedModules': <dynamic>[],
      };

  static Map<String, int> _generatorTanks(Map generator) =>
      Map<String, int>.from((generator.putIfAbsent(
              'tanks', () => <String, int>{'organic': 0, 'mineral': 0}) as Map)
          .map((key, value) => MapEntry('$key', (value as num).toInt())))
        ..also((tanks) => generator['tanks'] = tanks);

  static bool _runBiogeneratorCycle(
      Map generator, Map alcove, ElevageConfig config) {
    final tanks = _generatorTanks(generator);
    final profile = biogeneratorCycleProfile(generator, config);
    if ((tanks['organic'] ?? 0) < profile['organic']! ||
        (tanks['mineral'] ?? 0) < profile['mineral']!) {
      return false;
    }
    final stored = (alcove['localEnergy'] as num?)?.toInt() ?? 0;
    if (stored >= config.energyStorageMax) return false;
    tanks['organic'] = tanks['organic']! - profile['organic']!;
    tanks['mineral'] = tanks['mineral']! - profile['mineral']!;
    alcove['localEnergy'] =
        min(config.energyStorageMax, stored + profile['energy']!);
    return true;
  }

  static void _processLoanReturns(ElevageSave state, int now) {
    final inventory =
        state.data['installationInventory'] as Map<String, dynamic>;
    for (final individual
        in (state.data['individuals'] as Map).values.whereType<Map>()) {
      final loan = individual['loan'] as Map?;
      final due = (loan?['returnDueAt'] as num?)?.toInt();
      if (due == null || now < due || loan?['returnedAt'] != null) continue;
      final instanceId = loan?['instanceId'] as String?;
      Map? found = inventory[instanceId] as Map?;
      if (found == null && instanceId != null) {
        for (final alcove in state.data['alcoves'] as List) {
          final slots = (alcove as Map)['slots'] as List;
          final index = slots.indexWhere(
              (raw) => raw is Map && raw['instanceId'] == instanceId);
          if (index >= 0) {
            found = slots[index] as Map;
            slots[index] = null;
            break;
          }
        }
      } else if (instanceId != null) {
        inventory.remove(instanceId);
      }
      if (found != null) {
        for (final module
            in (found['installedModules'] as List? ?? const <dynamic>[])
                .whereType<Map>()) {
          _moduleInventory(state)[module['instanceId'] as String] =
              Map<String, dynamic>.from(module);
        }
      }
      loan!['returnedAt'] = now;
      (state.data['pendingNotifications'] as List).add(<String, dynamic>{
        'id': 'loan-returned-${loan['instanceId']}',
        'type': 'LOAN_RETURNED',
        'name': individual['name'],
        'createdAt': now,
        'acknowledgedAt': null,
      });
    }
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
          'MUSHROOM',
          'SPORE'
        ],
      'COAST' => <String>['ALGAE', 'LIMESTONE'],
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
