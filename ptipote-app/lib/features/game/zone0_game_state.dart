import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_stats_config.dart';
import 'craft_config.dart';
import 'fablab_config.dart';
import 'kernel_config.dart';
import 'lisiere_forage_config.dart';
import 'security_tower_config.dart';

class Zone0GameState extends ChangeNotifier {
  Zone0GameState._();

  static final Zone0GameState instance = Zone0GameState._();
  final math.Random _random = math.Random();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, int> vitalityOverrides = <String, int>{};
  final Map<String, int> hungerOverrides = <String, int>{};
  final Map<String, int> restOverrides = <String, int>{};
  final Map<String, int> xpOverrides = <String, int>{};
  final Map<String, int> levelOverrides = <String, int>{};
  final Map<String, DateTime> lastCuddleAt = <String, DateTime>{};
  final Set<String> manualRestingIds = <String>{};
  final Map<String, PtipoteAutoAssignmentPreference> autoPreferenceOverrides =
      <String, PtipoteAutoAssignmentPreference>{};
  final List<Zone0InventoryStack> inventory = <Zone0InventoryStack>[];
  final List<ForageMission> missions = <ForageMission>[];
  final List<PtipoteMissionReport> reports = <PtipoteMissionReport>[];
  final Set<String> completedKernelMissionIds = <String>{};

  int refugeSafety = lisiereForageConfig.refugeSafetyFallback;
  int fablabLevel = 0;
  int securityTowerLevel = 0;
  int currentPopulation = kernelConfig.startingPopulation;
  int bioBatteries = kernelConfig.startingBioBatteries;
  int campWellbeing = kernelConfig.startingWellbeing;
  int mealsPrepared = 0;
  int plaineMissionsCompleted = 0;
  final Set<String> towerAssignedIds = <String>{};
  DateTime? lastFirebaseSyncAt;
  DateTime? lastSimulationAt;
  String? lastFirebaseError;
  String firebaseSyncLabel = 'Non synchronisé';
  bool isFirebaseSyncing = false;
  bool _loadedFromFirebase = false;

  bool get isFablabBuilt => fablabLevel >= fablabConfig.cuisineUnlockLevel;
  bool get isSecurityTowerBuilt => securityTowerLevel >= 1;
  int get securityTowerSlots =>
      securityTowerConfig.slotsForLevel(securityTowerLevel);

  bool isAssignedToTower(String figurineId) {
    return towerAssignedIds.contains(figurineId);
  }

  int get globalStockCapacity {
    return fablabConfig.baseGlobalStockCapacity +
        fablabLevel * fablabConfig.stockCapacityBonusPerFablabLevel;
  }

  int get inventorySlotLimit {
    return (globalStockCapacity / lisiereForageConfig.inventoryStackLimit)
        .floor();
  }

  int get inventoryUsedAmount {
    return inventory.fold(0, (total, stack) => total + stack.amount);
  }

  int populationCapacityForCampHeartLevel(int campHeartLevel) {
    return kernelConfig.populationCapacityForCampHeartLevel(campHeartLevel);
  }

  String wellbeingColorLabel() {
    if (campWellbeing < kernelConfig.wellbeingRedThreshold) return 'Rouge';
    if (campWellbeing < kernelConfig.wellbeingOrangeThreshold) return 'Orange';
    return 'Vert';
  }

  List<KernelMissionProgress> kernelMissionsForCampHeartLevel(
    int campHeartLevel,
  ) {
    return kernelConfig.missions
        .map(
          (mission) => KernelMissionProgress(
            config: mission,
            progress: _kernelMissionProgress(mission),
            status: completedKernelMissionIds.contains(mission.id)
                ? KernelMissionStatus.completed
                : KernelMissionStatus.active,
          ),
        )
        .toList();
  }

  KernelMissionProgress? mainKernelMission(int campHeartLevel) {
    final missions = kernelMissionsForCampHeartLevel(campHeartLevel)
        .where((mission) => mission.config.type == KernelMissionType.main)
        .toList();
    for (final mission in missions) {
      if (mission.status != KernelMissionStatus.completed) return mission;
    }
    return missions.isEmpty ? null : missions.last;
  }

  List<KernelMissionProgress> refugeRequests(int campHeartLevel) {
    return kernelMissionsForCampHeartLevel(campHeartLevel)
        .where(
            (mission) => mission.config.type == KernelMissionType.refugeRequest)
        .take(kernelConfig.maxRefugeRequests)
        .toList();
  }

  int vitalityFor(PtipoteFigurine figurine) {
    return vitalityOverrides[figurine.id] ?? figurine.vitality;
  }

  int hungerFor(PtipoteFigurine figurine) {
    return hungerOverrides[figurine.id] ?? ptipoteStatsConfig.baseHunger;
  }

  int restFor(PtipoteFigurine figurine) {
    return restOverrides[figurine.id] ?? ptipoteStatsConfig.maxRest;
  }

  int xpFor(PtipoteFigurine figurine) {
    return xpOverrides[figurine.id] ?? figurine.xpValue;
  }

  int levelFor(PtipoteFigurine figurine) {
    return levelOverrides[figurine.id] ?? figurine.levelValue;
  }

  PtipoteAutoAssignmentPreference autoPreferenceFor(PtipoteFigurine figurine) {
    return autoPreferenceOverrides[figurine.id] ??
        figurine.autoAssignmentPreference;
  }

  bool get hasUnreadReports => unreadReportCount > 0;

  int get unreadReportCount {
    return reports.where((report) => !report.read).length;
  }

  bool isOnMission(String figurineId) {
    return missions.any(
      (mission) =>
          mission.memberIds.contains(figurineId) &&
          mission.status == ForageMissionStatus.active,
    );
  }

  bool isResting(PtipoteFigurine figurine) {
    return !isOnMission(figurine.id) &&
        (manualRestingIds.contains(figurine.id) ||
            vitalityFor(figurine) <=
                ptipoteStatsConfig.minVitalityBeforeAutoRest);
  }

  bool isBusy(PtipoteFigurine figurine) {
    return isOnMission(figurine.id) ||
        isResting(figurine) ||
        towerAssignedIds.contains(figurine.id);
  }

  bool isUnavailableForTower(PtipoteFigurine figurine) {
    return isOnMission(figurine.id) || towerAssignedIds.contains(figurine.id);
  }

  bool isHappy(PtipoteFigurine figurine) {
    return moodFor(figurine) == PtipoteMood.happy;
  }

  bool isFed(PtipoteFigurine figurine) {
    return hungerFor(figurine) > ptipoteStatsConfig.happyHungerThreshold;
  }

  bool isRested(PtipoteFigurine figurine) {
    final state = restStateFor(figurine);
    return state == PtipoteRestState.wellRested ||
        state == PtipoteRestState.rested;
  }

  bool hasIndigestion(PtipoteFigurine figurine) {
    return hungerFor(figurine) > ptipoteStatsConfig.indigestionHungerThreshold;
  }

  PtipoteRestState restStateFor(PtipoteFigurine figurine) {
    return ptipoteStatsConfig.restStateFor(restFor(figurine));
  }

  String restStateLabelFor(PtipoteFigurine figurine) {
    return switch (restStateFor(figurine)) {
      PtipoteRestState.wellRested => 'Bien reposé',
      PtipoteRestState.rested => 'Reposé',
      PtipoteRestState.tired => 'Fatigué',
      PtipoteRestState.exhausted => 'Exténué',
    };
  }

  bool isCuddleCareActive(PtipoteFigurine figurine) {
    final cuddleAt = lastCuddleAt[figurine.id];
    if (cuddleAt == null) return false;
    return DateTime.now().difference(cuddleAt) <=
        Duration(minutes: ptipoteStatsConfig.cuddleCareDurationMinutes);
  }

  int satisfiedNeedCount(PtipoteFigurine figurine) {
    return <bool>[
      isFed(figurine),
      isRested(figurine),
      isCuddleCareActive(figurine),
    ].where((satisfied) => satisfied).length;
  }

  PtipoteMood moodFor(PtipoteFigurine figurine) {
    final count = satisfiedNeedCount(figurine);
    if (count >= ptipoteStatsConfig.happyNeedsRequired) {
      return PtipoteMood.happy;
    }
    if (count >= ptipoteStatsConfig.okayNeedsRequired) {
      return PtipoteMood.okay;
    }
    return PtipoteMood.unwell;
  }

  String moodLabelFor(PtipoteFigurine figurine) {
    return switch (moodFor(figurine)) {
      PtipoteMood.happy => 'Heureux',
      PtipoteMood.okay => 'Bien',
      PtipoteMood.unwell => 'Mal',
    };
  }

  bool canCuddle(PtipoteFigurine figurine) {
    final cuddleAt = lastCuddleAt[figurine.id];
    if (cuddleAt == null) return true;
    return DateTime.now().difference(cuddleAt) >=
        Duration(minutes: ptipoteStatsConfig.cuddleCooldownMinutes);
  }

  double cuddleCooldownProgress(PtipoteFigurine figurine) {
    final cuddleAt = lastCuddleAt[figurine.id];
    if (cuddleAt == null) return 1;
    final cooldown =
        Duration(minutes: ptipoteStatsConfig.cuddleCooldownMinutes);
    final elapsed = DateTime.now().difference(cuddleAt);
    return (elapsed.inSeconds / cooldown.inSeconds).clamp(0.0, 1.0);
  }

  Duration vitalityRecoveryRemaining(PtipoteFigurine figurine) {
    final missing =
        math.max(0, ptipoteStatsConfig.maxVitality - vitalityFor(figurine));
    if (missing == 0) return Duration.zero;
    if (isResting(figurine)) {
      return Duration(
        minutes: (missing / ptipoteStatsConfig.alcoveVitalityRecoveryPerMinute)
            .ceil(),
      );
    }
    if (isHappy(figurine)) {
      return Duration(
        minutes: (missing / ptipoteStatsConfig.happyVitalityRecoveryPerMinute)
            .ceil(),
      );
    }
    return Duration(
      minutes: missing * ptipoteStatsConfig.naturalVitalityRecoveryMinutes,
    );
  }

  Duration restRecoveryRemaining(PtipoteFigurine figurine) {
    final missing = math.max(0, ptipoteStatsConfig.maxRest - restFor(figurine));
    if (missing == 0) return Duration.zero;
    return Duration(
      minutes: (missing / ptipoteStatsConfig.sleepRestRecoveryPerMinute).ceil(),
    );
  }

  void sendToSleep(PtipoteFigurine figurine) {
    if (isOnMission(figurine.id)) return;
    manualRestingIds.add(figurine.id);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void cuddle(PtipoteFigurine figurine) {
    if (isOnMission(figurine.id)) return;
    if (!canCuddle(figurine)) return;
    lastCuddleAt[figurine.id] = DateTime.now();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void wakeFromRest(PtipoteFigurine figurine) {
    if (isOnMission(figurine.id)) return;
    manualRestingIds.remove(figurine.id);
    final wakeVitality = math.min(
      ptipoteStatsConfig.maxVitality,
      ptipoteStatsConfig.minVitalityBeforeAutoRest + 1,
    );
    vitalityOverrides[figurine.id] =
        math.max(vitalityFor(figurine), wakeVitality);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
  }

  void recoverFigurineNeeds({
    required List<PtipoteFigurine> figurines,
    required int tick,
  }) {
    var changed = false;
    if (_applyElapsedSimulation(figurines)) {
      changed = true;
    }
    final hungerDecayTick =
        math.max(1, ptipoteStatsConfig.hungerDecayMinutes * 2);
    final restLossTick =
        math.max(1, ptipoteStatsConfig.awakeRestLossMinutes * 2);
    final naturalVitalityTick =
        math.max(1, ptipoteStatsConfig.naturalVitalityRecoveryMinutes * 2);
    for (final figurine in figurines) {
      if (isOnMission(figurine.id)) continue;
      if (towerAssignedIds.contains(figurine.id)) {
        if (tick % math.max(1, securityTowerConfig.tickMinutes * 2) == 0) {
          final currentVitality = vitalityFor(figurine);
          final nextVitality = math.max(
            0,
            currentVitality - securityTowerConfig.vitalityCostPerTick,
          );
          vitalityOverrides[figurine.id] = nextVitality;
          refugeSafety = math.min(
            securityTowerConfig.maxSecurity,
            refugeSafety + securityTowerConfig.securityGainPerTick,
          );
          if (nextVitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
            towerAssignedIds.remove(figurine.id);
            manualRestingIds.add(figurine.id);
          }
          changed = true;
        }
        continue;
      }
      final currentVitality = vitalityFor(figurine);
      final resting = isResting(figurine);
      final happy = isHappy(figurine);
      final hunger = hungerFor(figurine);
      var vitalityGain = 0;
      if (resting && tick.isEven) {
        vitalityGain = ptipoteStatsConfig.vitalityRecoveryPerMinute;
      } else if (happy && tick.isEven) {
        vitalityGain = ptipoteStatsConfig.happyVitalityRecoveryPerMinute;
      } else if (!resting &&
          hunger >= ptipoteStatsConfig.wellFedHungerThreshold &&
          hunger <= ptipoteStatsConfig.indigestionHungerThreshold &&
          tick % math.max(1, (naturalVitalityTick * 0.75).round()) == 0) {
        vitalityGain = 1;
      } else if (tick % naturalVitalityTick == 0) {
        vitalityGain = 1;
      }

      if (vitalityGain > 0) {
        if (hunger >= ptipoteStatsConfig.wellFedHungerThreshold &&
            hunger <= ptipoteStatsConfig.indigestionHungerThreshold) {
          vitalityGain = math.max(
            1,
            (vitalityGain *
                    (1 + ptipoteStatsConfig.wellFedVitalityRecoveryBonus))
                .round(),
          );
        } else if (hunger > ptipoteStatsConfig.indigestionHungerThreshold) {
          vitalityGain = math.max(
            0,
            (vitalityGain *
                    (1 - ptipoteStatsConfig.indigestionVitalityRecoveryPenalty))
                .floor(),
          );
        }
      }

      if (vitalityGain > 0 &&
          currentVitality < ptipoteStatsConfig.maxVitality) {
        final nextVitality = math.min(
          ptipoteStatsConfig.maxVitality,
          currentVitality + vitalityGain,
        );
        if (nextVitality >= ptipoteStatsConfig.maxVitality &&
            restFor(figurine) >= ptipoteStatsConfig.maxRest) {
          vitalityOverrides.remove(figurine.id);
          manualRestingIds.remove(figurine.id);
        } else {
          vitalityOverrides[figurine.id] = nextVitality;
        }
        changed = true;
      }

      if (tick % hungerDecayTick == 0) {
        final currentHunger = hungerFor(figurine);
        if (currentHunger > 0) {
          hungerOverrides[figurine.id] = math.max(0, currentHunger - 1);
          changed = true;
        }
      }

      final currentRest = restFor(figurine);
      if (resting) {
        final restGain =
            math.max(1, ptipoteStatsConfig.sleepRestRecoveryPerMinute ~/ 2);
        final nextRest =
            math.min(ptipoteStatsConfig.maxRest, currentRest + restGain);
        if (nextRest != currentRest) {
          restOverrides[figurine.id] = nextRest;
          changed = true;
        }
      } else if (tick % restLossTick == 0 && currentRest > 0) {
        restOverrides[figurine.id] = math.max(0, currentRest - 1);
        changed = true;
      }
    }
    if (isSecurityTowerBuilt &&
        towerAssignedIds.isEmpty &&
        tick % math.max(1, securityTowerConfig.tickMinutes * 2) == 0 &&
        refugeSafety > 0) {
      refugeSafety = math.max(
        0,
        refugeSafety - securityTowerConfig.securityDecayPerTick,
      );
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  bool _applyElapsedSimulation(List<PtipoteFigurine> figurines) {
    final now = DateTime.now();
    final previous = lastSimulationAt;
    if (previous == null) {
      lastSimulationAt = now;
      return true;
    }
    final elapsedMinutes = now.difference(previous).inMinutes;
    if (elapsedMinutes <= 0) return false;

    var changed = false;
    final figurinesById = <String, PtipoteFigurine>{
      for (final figurine in figurines) figurine.id: figurine,
    };

    for (final figurine in figurines) {
      if (isOnMission(figurine.id)) continue;
      if (towerAssignedIds.contains(figurine.id)) continue;

      final resting = isResting(figurine);
      var currentHunger = hungerFor(figurine);
      var currentRest = restFor(figurine);
      var currentVitality = vitalityFor(figurine);

      final hungerLoss =
          elapsedMinutes ~/ math.max(1, ptipoteStatsConfig.hungerDecayMinutes);
      if (hungerLoss > 0 && currentHunger > 0) {
        currentHunger = math.max(0, currentHunger - hungerLoss);
        hungerOverrides[figurine.id] = currentHunger;
        changed = true;
      }

      if (resting) {
        final restGain =
            elapsedMinutes * ptipoteStatsConfig.sleepRestRecoveryPerMinute;
        if (restGain > 0 && currentRest < ptipoteStatsConfig.maxRest) {
          currentRest =
              math.min(ptipoteStatsConfig.maxRest, currentRest + restGain);
          restOverrides[figurine.id] = currentRest;
          changed = true;
        }
        if (currentVitality < ptipoteStatsConfig.maxVitality) {
          currentVitality = math.min(
            ptipoteStatsConfig.maxVitality,
            currentVitality +
                elapsedMinutes * ptipoteStatsConfig.vitalityRecoveryPerMinute,
          );
          vitalityOverrides[figurine.id] = currentVitality;
          changed = true;
        }
      } else {
        final restLoss = elapsedMinutes ~/
            math.max(1, ptipoteStatsConfig.awakeRestLossMinutes);
        if (restLoss > 0 && currentRest > 0) {
          currentRest = math.max(0, currentRest - restLoss);
          restOverrides[figurine.id] = currentRest;
          changed = true;
        }

        final recoveryInterval = isHappy(figurine)
            ? math.max(1,
                (1 / ptipoteStatsConfig.happyVitalityRecoveryPerMinute).ceil())
            : ptipoteStatsConfig.naturalVitalityRecoveryMinutes;
        var vitalityGain = elapsedMinutes ~/ math.max(1, recoveryInterval);
        if (currentHunger >= ptipoteStatsConfig.wellFedHungerThreshold &&
            currentHunger <= ptipoteStatsConfig.indigestionHungerThreshold) {
          vitalityGain = (vitalityGain *
                  (1 + ptipoteStatsConfig.wellFedVitalityRecoveryBonus))
              .round();
        } else if (currentHunger >
            ptipoteStatsConfig.indigestionHungerThreshold) {
          vitalityGain = (vitalityGain *
                  (1 - ptipoteStatsConfig.indigestionVitalityRecoveryPenalty))
              .floor();
        }
        if (vitalityGain > 0 &&
            currentVitality < ptipoteStatsConfig.maxVitality) {
          currentVitality = math.min(
            ptipoteStatsConfig.maxVitality,
            currentVitality + vitalityGain,
          );
          vitalityOverrides[figurine.id] = currentVitality;
          changed = true;
        }
      }
    }

    final towerTicks =
        elapsedMinutes ~/ math.max(1, securityTowerConfig.tickMinutes);
    if (towerTicks > 0) {
      if (towerAssignedIds.isNotEmpty) {
        for (final figurineId in towerAssignedIds.toList()) {
          final figurine = figurinesById[figurineId];
          if (figurine == null) continue;
          final nextVitality = math.max(
            0,
            vitalityFor(figurine) -
                towerTicks * securityTowerConfig.vitalityCostPerTick,
          );
          vitalityOverrides[figurine.id] = nextVitality;
          refugeSafety = math.min(
            securityTowerConfig.maxSecurity,
            refugeSafety + towerTicks * securityTowerConfig.securityGainPerTick,
          );
          if (nextVitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
            towerAssignedIds.remove(figurine.id);
            manualRestingIds.add(figurine.id);
          }
          changed = true;
        }
      } else if (isSecurityTowerBuilt && refugeSafety > 0) {
        refugeSafety = math.max(
          0,
          refugeSafety - towerTicks * securityTowerConfig.securityDecayPerTick,
        );
        changed = true;
      }
    }

    lastSimulationAt = now;
    return changed;
  }

  int resourceAmount(String resource) {
    return inventory
        .where((stack) => stack.resource == resource)
        .fold(0, (total, stack) => total + stack.amount);
  }

  int inventoryFreeCapacityFor(Map<String, int> rewards) {
    final simulated = inventory
        .map(
          (stack) => Zone0InventoryStack(
            resource: stack.resource,
            amount: stack.amount,
          ),
        )
        .toList();
    var freeSlots = inventorySlotLimit - simulated.length;
    var capacity = 0;

    for (final entry in rewards.entries) {
      var remaining = math.max(0, entry.value);
      for (final stack
          in simulated.where((stack) => stack.resource == entry.key)) {
        if (remaining <= 0) break;
        final room = lisiereForageConfig.inventoryStackLimit - stack.amount;
        if (room <= 0) continue;
        final add = math.min(room, remaining);
        stack.amount += add;
        remaining -= add;
        capacity += add;
      }

      while (remaining > 0 && freeSlots > 0) {
        final add =
            math.min(remaining, lisiereForageConfig.inventoryStackLimit);
        simulated.add(Zone0InventoryStack(resource: entry.key, amount: add));
        freeSlots -= 1;
        remaining -= add;
        capacity += add;
      }
    }

    return capacity;
  }

  int removeResource(String resource, int requestedAmount) {
    var remaining = math.max(0, requestedAmount);
    var removed = 0;
    for (final stack in inventory.toList()) {
      if (remaining <= 0) break;
      if (stack.resource != resource) continue;
      final take = math.min(stack.amount, remaining);
      stack.amount -= take;
      remaining -= take;
      removed += take;
      if (stack.amount <= 0) {
        inventory.remove(stack);
      }
    }
    if (removed > 0) {
      notifyListeners();
      unawaited(saveInventoryToFirebase());
    }
    return removed;
  }

  bool hasResources(Map<String, int> costs) {
    return costs.entries.every(
      (entry) => resourceAmount(entry.key) >= math.max(0, entry.value),
    );
  }

  bool hasInventoryCapacityFor(Map<String, int> rewards) {
    return inventoryFreeCapacityFor(rewards) >=
        rewards.values.fold(0, (total, amount) => total + math.max(0, amount));
  }

  bool removeResources(Map<String, int> costs) {
    final cleanCosts = Map<String, int>.from(costs)
      ..removeWhere((_, amount) => amount <= 0);
    if (!hasResources(cleanCosts)) return false;

    for (final entry in cleanCosts.entries) {
      removeResource(entry.key, entry.value);
    }
    unawaited(saveInventoryToFirebase());
    return true;
  }

  Zone0ActionResult constructFablabLevel1() {
    if (isFablabBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Fablab est déjà construit.',
      );
    }

    final cost = fablabConfig.constructionCostLevel1;
    if (!hasResources(cost)) {
      return Zone0ActionResult(
        success: false,
        message: missingResourcesLabel(cost),
      );
    }

    if (!removeResources(cost)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources insuffisantes.',
      );
    }

    fablabLevel = 1;
    reports.add(
      PtipoteMissionReport.system(
        message: 'Le Fablab est prêt. La Cuisine est maintenant disponible.',
      ),
    );
    refreshKernelMissions(campHeartLevel: 1);
    notifyListeners();
    unawaited(saveBuildingsToFirebase());
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'Le Fablab est prêt. La Cuisine peut maintenant être utilisée.',
    );
  }

  Zone0ActionResult constructSecurityTower(int campHeartLevel) {
    if (isSecurityTowerBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'La Tour est déjà construite.',
      );
    }
    if (campHeartLevel < securityTowerConfig.requiredCampHeartLevel) {
      return const Zone0ActionResult(
        success: false,
        message: 'Le Cœur du Camp doit atteindre le niveau 1.',
      );
    }
    final cost = securityTowerConfig.constructionCost;
    if (!hasResources(cost)) {
      return Zone0ActionResult(
          success: false, message: missingResourcesLabel(cost));
    }
    if (!removeResources(cost)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources insuffisantes.',
      );
    }
    securityTowerLevel = 1;
    refugeSafety = math.max(refugeSafety, securityTowerConfig.initialSecurity);
    reports.add(
      PtipoteMissionReport.system(
        message: 'La Tour de sécurité est construite.',
      ),
    );
    refreshKernelMissions(campHeartLevel: campHeartLevel);
    notifyListeners();
    unawaited(saveBuildingsToFirebase());
    unawaited(saveRuntimeToFirebase());
    return const Zone0ActionResult(
      success: true,
      message: 'La Tour surveille maintenant les abords du refuge.',
    );
  }

  Zone0ActionResult assignToTower(PtipoteFigurine figurine) {
    if (!isSecurityTowerBuilt) {
      return const Zone0ActionResult(
          success: false, message: 'Tour non construite.');
    }
    if (towerAssignedIds.length >= securityTowerSlots) {
      return const Zone0ActionResult(
          success: false, message: 'Aucun slot libre.');
    }
    if (isUnavailableForTower(figurine)) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIPOTE occupé.');
    }
    if (vitalityFor(figurine) < ptipoteStatsConfig.minimumMissionVitality) {
      return const Zone0ActionResult(
          success: false, message: 'P’TIPOTE trop fatigué.');
    }
    towerAssignedIds.add(figurine.id);
    manualRestingIds.remove(figurine.id);
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${figurine.displayName} surveille la Tour.',
    );
  }

  void removeFromTower(String figurineId) {
    if (towerAssignedIds.remove(figurineId)) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  Zone0ActionResult prepareSimpleMeal() {
    return prepareRecipe(craftConfig.simpleMealRecipe);
  }

  Zone0ActionResult prepareRecipe(CraftRecipe recipe) {
    if (!isFablabBuilt) {
      return const Zone0ActionResult(
        success: false,
        message: 'Construis le Fablab pour utiliser la Cuisine.',
      );
    }

    final cost = recipe.ingredients;
    final output = <String, int>{recipe.resultItem: recipe.resultAmount};
    if (!hasResources(cost)) {
      return Zone0ActionResult(
        success: false,
        message: missingResourcesLabel(cost),
      );
    }
    if (!hasInventoryCapacityFor(output)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Inventaire plein : libère un slot avant de cuisiner.',
      );
    }
    if (!removeResources(cost)) {
      return const Zone0ActionResult(
        success: false,
        message: 'Ressources insuffisantes.',
      );
    }
    addResources(output);
    if (recipe.resultItem == craftConfig.simpleMealRecipe.resultItem) {
      mealsPrepared += recipe.resultAmount;
    }
    refreshKernelMissions();
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message: '${recipe.displayName} préparé.',
    );
  }

  Zone0ActionResult consumeSimpleMeal(PtipoteFigurine figurine) {
    final recipe = craftConfig.simpleMealRecipe;
    if (!recipe.isConsumable) {
      return const Zone0ActionResult(
        success: false,
        message: 'Cet objet n’est pas consommable.',
      );
    }
    if (resourceAmount(recipe.resultItem) <= 0) {
      return Zone0ActionResult(
        success: false,
        message: 'Aucun ${recipe.resultItem} disponible.',
      );
    }
    final removed = removeResource(recipe.resultItem, 1);
    if (removed <= 0) {
      return const Zone0ActionResult(
        success: false,
        message: 'Repas indisponible.',
      );
    }
    hungerOverrides[figurine.id] = math.min(
      ptipoteStatsConfig.maxOverfedHunger,
      hungerFor(figurine) + recipe.hungerRestore,
    );
    vitalityOverrides[figurine.id] = math.min(
      ptipoteStatsConfig.maxVitality,
      vitalityFor(figurine) + recipe.vitalityRestore,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          '${figurine.displayName} mange ${recipe.resultItem} (+${recipe.hungerRestore} faim, +${recipe.vitalityRestore} vitalité).',
    );
  }

  String missingResourcesLabel(Map<String, int> costs) {
    final missing = costs.entries
        .map((entry) => MapEntry(
              entry.key,
              math.max(0, entry.value - resourceAmount(entry.key)),
            ))
        .where((entry) => entry.value > 0)
        .map((entry) => '${entry.value} ${entry.key}')
        .join(', ');
    return missing.isEmpty ? 'Ressources disponibles.' : 'Il manque $missing.';
  }

  Future<void> loadFromFirebase() async {
    if (_loadedFromFirebase) return;
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Chargement Zone 0', () async {
      final snapshot = await _zone0Doc(user.uid).get();
      final data = snapshot.data();
      if (data == null) {
        _loadedFromFirebase = true;
        return;
      }

      final inventoryData = data['inventory'];
      if (inventoryData is List) {
        inventory
          ..clear()
          ..addAll(
            inventoryData
                .whereType<Map>()
                .map(
                  (item) => Zone0InventoryStack(
                    resource: '${item['resource'] ?? ''}',
                    amount: _readInt(item['amount']),
                  ),
                )
                .where(
                    (stack) => stack.resource.isNotEmpty && stack.amount > 0),
          );
      }

      final vitalityData = data['vitalityOverrides'];
      if (vitalityData is Map) {
        vitalityOverrides
          ..clear()
          ..addEntries(
            vitalityData.entries.map(
              (entry) => MapEntry('${entry.key}', _readInt(entry.value)),
            ),
          );
      }

      final hungerData = data['hungerOverrides'];
      if (hungerData is Map) {
        hungerOverrides
          ..clear()
          ..addEntries(
            hungerData.entries.map(
              (entry) => MapEntry('${entry.key}', _readInt(entry.value)),
            ),
          );
      }

      final restData = data['restOverrides'];
      if (restData is Map) {
        restOverrides
          ..clear()
          ..addEntries(
            restData.entries.map(
              (entry) => MapEntry('${entry.key}', _readInt(entry.value)),
            ),
          );
      }

      final restingData = data['manualRestingIds'];
      if (restingData is List) {
        manualRestingIds
          ..clear()
          ..addAll(restingData.map((id) => '$id'));
      }

      final cuddleData = data['lastCuddleAt'];
      if (cuddleData is Map) {
        lastCuddleAt
          ..clear()
          ..addEntries(
            cuddleData.entries.map((entry) {
              final date = _readDate(entry.value);
              if (date == null) return null;
              return MapEntry('${entry.key}', date);
            }).whereType<MapEntry<String, DateTime>>(),
          );
      }

      final missionData = data['missions'];
      if (missionData is List) {
        missions
          ..clear()
          ..addAll(
            missionData
                .whereType<Map>()
                .map(ForageMission.fromFirebase)
                .whereType<ForageMission>(),
          );
      }

      final reportData = data['reports'];
      if (reportData is List) {
        reports
          ..clear()
          ..addAll(
            reportData
                .whereType<Map>()
                .map(PtipoteMissionReport.fromFirebase)
                .whereType<PtipoteMissionReport>(),
          );
      }

      final kernelData = data['kernel'];
      if (kernelData is Map) {
        currentPopulation = _readInt(
          kernelData['currentPopulation'],
          fallback: kernelConfig.startingPopulation,
        );
        bioBatteries = _readInt(
          kernelData['bioBatteries'],
          fallback: kernelConfig.startingBioBatteries,
        );
        campWellbeing = _readInt(
          kernelData['campWellbeing'],
          fallback: kernelConfig.startingWellbeing,
        ).clamp(0, 100);
        mealsPrepared = _readInt(kernelData['mealsPrepared']);
        plaineMissionsCompleted =
            _readInt(kernelData['plaineMissionsCompleted']);
        final completedData = kernelData['completedMissionIds'];
        if (completedData is List) {
          completedKernelMissionIds
            ..clear()
            ..addAll(completedData.map((id) => '$id'));
        }
      }

      final buildingsData = data['buildings'];
      if (buildingsData is Map) {
        final fablabData = buildingsData['fablab'];
        if (fablabData is Map) {
          fablabLevel = _readInt(fablabData['currentLevel']).clamp(
            0,
            fablabConfig.fablabMaxLevel,
          );
        }
        final towerData = buildingsData['securityTower'];
        if (towerData is Map) {
          securityTowerLevel = _readInt(towerData['currentLevel']).clamp(0, 3);
        }
      }
      refugeSafety = _readInt(data['campSecurity']).clamp(
        0,
        securityTowerConfig.maxSecurity,
      );
      final towerAssignedData = data['towerAssignedIds'];
      if (towerAssignedData is List) {
        towerAssignedIds
          ..clear()
          ..addAll(towerAssignedData.map((id) => '$id'));
      }
      lastSimulationAt =
          _readDate(data['lastSimulationAt']) ?? _readDate(data['updatedAt']);

      _loadedFromFirebase = true;
    });
  }

  ForageMission startForageMission({
    required List<PtipoteFigurine> figurines,
    required ForageBiome biome,
    required ForageDuration duration,
    required ForageIntensity intensity,
    required Map<String, int> expectedRewards,
    required Map<String, int> vitalityCostByMember,
    required int riskPercent,
    required String riskLabel,
    required int baseRiskPercent,
    required int securityAtLaunch,
    required int securityReduction,
    required Map<String, int> xpGainByMember,
  }) {
    final start = DateTime.now();
    final durationConfig = lisiereForageConfig.durations[duration]!;
    for (final figurine in figurines) {
      levelOverrides.putIfAbsent(figurine.id, () => figurine.levelValue);
      xpOverrides.putIfAbsent(figurine.id, () => figurine.xpValue);
    }
    final memberIds = figurines.map((figurine) => figurine.id).toList();
    final memberNames =
        figurines.map((figurine) => figurine.displayName).toList();
    final totalVitalityCost =
        vitalityCostByMember.values.fold(0, (total, cost) => total + cost);
    final totalXpGain =
        xpGainByMember.values.fold(0, (total, xp) => total + xp);
    final mission = ForageMission(
      id: 'mission-${start.microsecondsSinceEpoch}',
      figurineId: memberIds.first,
      figurineName: memberNames.join(', '),
      memberIds: memberIds,
      memberNames: memberNames,
      biome: biome,
      duration: duration,
      intensity: intensity,
      startTime: start,
      endTime: start.add(
        durationConfig.realDuration(lisiereForageConfig.forageTimeScale),
      ),
      expectedRewards: expectedRewards,
      vitalityCost: totalVitalityCost,
      vitalityCostByMember: vitalityCostByMember,
      riskPercent: riskPercent,
      riskLabel: riskLabel,
      baseRiskPercent: baseRiskPercent,
      securityAtLaunch: securityAtLaunch,
      securityReduction: securityReduction,
      xpGain: totalXpGain,
      xpGainByMember: xpGainByMember,
    );
    missions.add(mission);
    for (final figurine in figurines) {
      final vitalityCost = vitalityCostByMember[figurine.id] ?? 0;
      vitalityOverrides[figurine.id] = math.max(
        0,
        vitalityFor(figurine) - vitalityCost,
      );
      hungerOverrides[figurine.id] = math.max(
        0,
        hungerFor(figurine) -
            (vitalityCost * ptipoteStatsConfig.missionHungerCostRatio).round(),
      );
      restOverrides[figurine.id] = math.max(
        0,
        restFor(figurine) -
            (vitalityCost * ptipoteStatsConfig.missionRestLossRatio).round(),
      );
      manualRestingIds.remove(figurine.id);
    }
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return mission;
  }

  bool resolveDueForageMissions({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    var resolvedAny = false;
    for (final mission in missions) {
      if (mission.status != ForageMissionStatus.active) continue;
      if (mission.endTime.isAfter(currentTime)) continue;
      _resolveMission(mission, completedAt: currentTime);
      resolvedAny = true;
    }
    if (resolvedAny) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
    return resolvedAny;
  }

  Zone0ActionResult emergencyReturnForageMission(String missionId) {
    ForageMission? mission;
    for (final item in missions) {
      if (item.id == missionId) {
        mission = item;
        break;
      }
    }
    if (mission == null || mission.status != ForageMissionStatus.active) {
      return const Zone0ActionResult(
        success: false,
        message: 'Mission indisponible.',
      );
    }
    final now = DateTime.now();
    final totalSeconds = math.max(
      1,
      mission.endTime.difference(mission.startTime).inSeconds,
    );
    final elapsedSeconds = now.difference(mission.startTime).inSeconds.clamp(
          0,
          totalSeconds,
        );
    final ratio = (elapsedSeconds / totalSeconds).clamp(0.05, 1.0);
    _resolveMission(
      mission,
      completedAt: now,
      rewardRatio: ratio,
      riskBonus: 5,
      emergencyReturn: true,
    );
    notifyListeners();
    unawaited(saveRuntimeToFirebase());
    return Zone0ActionResult(
      success: true,
      message:
          'Retour d’urgence lancé. Butin récupéré à ${(ratio * 100).round()}%.',
    );
  }

  int freeInventorySlots() {
    return inventorySlotLimit - inventory.length;
  }

  InventoryAddResult addResources(Map<String, int> rewards) {
    final pending = Map<String, int>.from(rewards)
      ..removeWhere((_, amount) => amount <= 0);
    var addedAny = false;

    for (final entry in pending.entries.toList()) {
      var remaining = entry.value;
      for (final stack
          in inventory.where((stack) => stack.resource == entry.key)) {
        if (remaining <= 0) break;
        final room = lisiereForageConfig.inventoryStackLimit - stack.amount;
        if (room <= 0) continue;
        final add = math.min(room, remaining);
        stack.amount += add;
        remaining -= add;
        addedAny = true;
      }

      while (remaining > 0 && inventory.length < inventorySlotLimit) {
        final add =
            math.min(remaining, lisiereForageConfig.inventoryStackLimit);
        inventory.add(Zone0InventoryStack(resource: entry.key, amount: add));
        remaining -= add;
        addedAny = true;
      }

      if (remaining <= 0) {
        pending.remove(entry.key);
      } else {
        pending[entry.key] = remaining;
      }
    }

    if (addedAny) unawaited(saveInventoryToFirebase());
    return InventoryAddResult(addedAny: addedAny, pending: pending);
  }

  void markReportsRead() {
    var changed = false;
    for (final report in reports) {
      if (!report.read) changed = true;
      report.read = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  void deleteReport(String reportId) {
    final before = reports.length;
    reports.removeWhere((report) => report.id == reportId);
    if (reports.length != before) {
      notifyListeners();
      unawaited(saveRuntimeToFirebase());
    }
  }

  int _kernelMissionProgress(KernelMissionConfig mission) {
    return switch (mission.conditionType) {
      KernelMissionConditionType.fablabBuilt => isFablabBuilt ? 1 : 0,
      KernelMissionConditionType.securityTowerBuilt =>
        isSecurityTowerBuilt ? 1 : 0,
      KernelMissionConditionType.mealsPrepared => mealsPrepared,
      KernelMissionConditionType.plaineMissionsCompleted =>
        plaineMissionsCompleted,
    };
  }

  bool refreshKernelMissions({int campHeartLevel = 1}) {
    var changed = false;
    final populationCapacity =
        populationCapacityForCampHeartLevel(campHeartLevel);
    for (final mission in kernelConfig.missions) {
      if (completedKernelMissionIds.contains(mission.id)) continue;
      if (_kernelMissionProgress(mission) < mission.requiredAmount) continue;
      completedKernelMissionIds.add(mission.id);
      currentPopulation = math.min(
        populationCapacity,
        currentPopulation + mission.populationReward,
      );
      bioBatteries += mission.bioBatteryReward;
      reports.add(PtipoteMissionReport.system(message: mission.mailMessage));
      changed = true;
    }
    if (changed) {
      unawaited(saveRuntimeToFirebase());
    }
    return changed;
  }

  void _resolveMission(
    ForageMission mission, {
    required DateTime completedAt,
    double rewardRatio = 1,
    int riskBonus = 0,
    bool emergencyReturn = false,
  }) {
    final biome = lisiereForageConfig.biomes[mission.biome]!;
    final duration = lisiereForageConfig.durations[mission.duration]!;
    final intensity = lisiereForageConfig.intensities[mission.intensity]!;
    var rewards = Map<String, int>.from(mission.expectedRewards);
    var incident = 'aucun';

    rewards = rewards.map(
      (key, value) => MapEntry(key, math.max(0, (value * rewardRatio).floor())),
    );
    final realRisk = math.min(100, mission.riskPercent + riskBonus);

    if (_random.nextInt(100) < realRisk) {
      final hazards = biome.hazards.isEmpty
          ? ForageHazard.values.where((h) => h != ForageHazard.none).toList()
          : biome.hazards;
      final hazard = hazards[_random.nextInt(hazards.length)];
      switch (hazard) {
        case ForageHazard.pollution:
          rewards['Organique'] = ((rewards['Organique'] ?? 0) * 0.8).round();
          incident = 'pollution légère, -20 % Organique';
        case ForageHazard.droneErrant:
          rewards = rewards
              .map((key, value) => MapEntry(key, (value * 0.75).round()));
          incident = 'drone errant, -25 % gains totaux';
        case ForageHazard.climatDifficile:
          rewards = rewards
              .map((key, value) => MapEntry(key, (value * 0.85).round()));
          incident = 'climat difficile, -15 % gains totaux';
        case ForageHazard.terrainInstable:
          rewards['Minéral'] = ((rewards['Minéral'] ?? 0) * 0.8).round();
          incident = 'terrain instable, -20 % Minéral';
        case ForageHazard.none:
          break;
      }
    }

    final inventoryResult = addResources(rewards);
    final xpResults = <String, PtipoteXpGainResult>{};
    for (final memberId in mission.memberIds) {
      final xpGain = mission.xpGainByMember[memberId] ??
          (mission.memberIds.isEmpty
              ? mission.xpGain
              : (mission.xpGain / mission.memberIds.length).round());
      final xpResult = addMissionXp(memberId, xpGain);
      xpResults[memberId] = xpResult;
      unawaited(persistFigurineProgress(
        figurineId: memberId,
        xp: xpResult.xp,
        level: xpResult.level,
      ));
    }
    if (mission.biome == ForageBiome.plaineRiche) {
      plaineMissionsCompleted += 1;
    }
    refreshKernelMissions();
    final memberStateLabels = <String>[];
    var lowestVitality = ptipoteStatsConfig.maxVitality;
    var lowestHunger = ptipoteStatsConfig.baseHunger;
    var leveledUp = false;
    var highestLevel = 0;
    for (var index = 0; index < mission.memberIds.length; index += 1) {
      final memberId = mission.memberIds[index];
      final memberName = index < mission.memberNames.length
          ? mission.memberNames[index]
          : mission.figurineName;
      final vitality = vitalityOverrides[memberId] ?? 0;
      final hunger = hungerOverrides[memberId] ?? ptipoteStatsConfig.baseHunger;
      final rest = restOverrides[memberId] ?? ptipoteStatsConfig.maxRest;
      lowestVitality = math.min(lowestVitality, vitality);
      lowestHunger = math.min(lowestHunger, hunger);
      final moodLabel = _moodLabelForValues(
        hunger: hunger,
        rest: rest,
        figurineId: memberId,
      );
      if (vitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
        manualRestingIds.add(memberId);
      }
      memberStateLabels.add(
        _finalMissionStateLabel(
          figurineName: memberName,
          vitality: vitality,
          hunger: hunger,
          moodLabel: moodLabel,
        ),
      );
      final xpResult = xpResults[memberId];
      if (xpResult != null) {
        leveledUp = leveledUp || xpResult.leveledUp;
        highestLevel = math.max(highestLevel, xpResult.level);
      }
    }
    final finalState = <String>[
      if (emergencyReturn)
        'Retour d’urgence : le butin est calculé au temps écoulé, avec +5% de risque événement.',
      ...memberStateLabels,
    ].join(' ');
    reports.add(
      PtipoteMissionReport(
        id: 'report-${completedAt.microsecondsSinceEpoch}',
        figurineName: mission.figurineName,
        biomeLabel: biome.label,
        durationLabel: duration.label,
        intensityLabel: intensity.label,
        rewards: rewards,
        incidentLabel: incident,
        xpGain: mission.xpGain,
        leveledUp: leveledUp,
        levelAfter: highestLevel,
        vitalityRemaining: lowestVitality,
        hungerRemaining: lowestHunger,
        moodLabel: 'Équipe',
        finalStateLabel: finalState,
        baseRiskPercent: mission.baseRiskPercent,
        securityAtLaunch: mission.securityAtLaunch,
        securityReduction: mission.securityReduction,
        realRiskPercent: realRisk,
        completedAt: completedAt,
        inventoryFull: inventoryResult.hasPending,
      ),
    );
    mission.status = ForageMissionStatus.completed;
  }

  String _moodLabelForValues({
    required int hunger,
    required int rest,
    required String figurineId,
  }) {
    var needs = 0;
    if (hunger > ptipoteStatsConfig.happyHungerThreshold) needs += 1;
    final restState = ptipoteStatsConfig.restStateFor(rest);
    if (restState == PtipoteRestState.wellRested ||
        restState == PtipoteRestState.rested) {
      needs += 1;
    }
    final cuddleAt = lastCuddleAt[figurineId];
    if (cuddleAt != null &&
        DateTime.now().difference(cuddleAt) <=
            Duration(minutes: ptipoteStatsConfig.cuddleCareDurationMinutes)) {
      needs += 1;
    }
    if (needs >= ptipoteStatsConfig.happyNeedsRequired) return 'Heureux';
    if (needs >= ptipoteStatsConfig.okayNeedsRequired) return 'Bien';
    return 'Mal';
  }

  String _finalMissionStateLabel({
    required String figurineName,
    required int vitality,
    required int hunger,
    required String moodLabel,
  }) {
    final notes = <String>[];
    if (vitality <= ptipoteStatsConfig.minVitalityBeforeAutoRest) {
      notes
          .add('$figurineName est revenu très fatigué et est allé se reposer.');
    } else if (vitality <= ptipoteStatsConfig.happyVitalityThreshold) {
      notes.add('$figurineName est revenu fatigué.');
    } else {
      notes.add('$figurineName est revenu en forme.');
    }
    if (hunger <= ptipoteStatsConfig.happyHungerThreshold) {
      notes.add('$figurineName aimerait manger.');
    }
    notes.add('État de bonheur : $moodLabel.');
    return notes.join(' ');
  }

  PtipoteXpGainResult addMissionXp(String figurineId, int xpGain) {
    var level = levelOverrides[figurineId] ?? 1;
    var xp = xpOverrides[figurineId] ?? 0;
    xp += math.max(0, xpGain);
    var leveledUp = false;

    while (xp >= ptipoteStatsConfig.xpRequiredForNextLevel(level)) {
      xp -= ptipoteStatsConfig.xpRequiredForNextLevel(level);
      level += 1;
      leveledUp = true;
    }

    levelOverrides[figurineId] = level;
    xpOverrides[figurineId] = xp;
    unawaited(saveRuntimeToFirebase());
    return PtipoteXpGainResult(
      xp: xp,
      level: level,
      leveledUp: leveledUp,
    );
  }

  Future<Map<String, dynamic>?> loadCampHeartFromFirebase() async {
    final user = await _currentUser();
    if (user == null) return null;
    Map<String, dynamic>? campHeart;
    await _runFirebaseSync('Chargement Cœur du Camp', () async {
      final snapshot = await _zone0Doc(user.uid).get();
      campHeart = snapshot.data()?['campHeart'] as Map<String, dynamic>?;
    });
    return campHeart;
  }

  Future<void> saveCampHeartToFirebase(Map<String, dynamic> campHeart) async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde Cœur du Camp', () {
      return _zone0Doc(user.uid).set(
        <String, dynamic>{
          'campHeart': campHeart,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveInventoryToFirebase() async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde inventaire', () {
      return _zone0Doc(user.uid).set(
        <String, dynamic>{
          'inventory': inventory
              .map(
                (stack) => <String, dynamic>{
                  'resource': stack.resource,
                  'amount': stack.amount,
                },
              )
              .toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveRuntimeToFirebase() async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde missions/vitalité', () {
      return _zone0Doc(user.uid).set(
        <String, dynamic>{
          'vitalityOverrides': vitalityOverrides,
          'hungerOverrides': hungerOverrides,
          'restOverrides': restOverrides,
          'manualRestingIds': manualRestingIds.toList(),
          'towerAssignedIds': towerAssignedIds.toList(),
          'campSecurity': refugeSafety,
          'kernel': <String, dynamic>{
            'currentPopulation': currentPopulation,
            'bioBatteries': bioBatteries,
            'campWellbeing': campWellbeing,
            'mealsPrepared': mealsPrepared,
            'plaineMissionsCompleted': plaineMissionsCompleted,
            'completedMissionIds': completedKernelMissionIds.toList(),
          },
          'lastSimulationAt': lastSimulationAt == null
              ? FieldValue.serverTimestamp()
              : Timestamp.fromDate(lastSimulationAt!),
          'lastCuddleAt': lastCuddleAt.map(
            (key, value) => MapEntry(key, Timestamp.fromDate(value)),
          ),
          'missions': missions.map((mission) => mission.toFirebase()).toList(),
          'reports': reports.map((report) => report.toFirebase()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> saveBuildingsToFirebase() async {
    final user = await _currentUser();
    if (user == null) return;
    await _runFirebaseSync('Sauvegarde bâtiments', () {
      return _zone0Doc(user.uid).set(
        <String, dynamic>{
          'buildings': <String, dynamic>{
            'fablab': <String, dynamic>{
              'buildingId': 'fablab',
              'buildingType': 'production',
              'displayName': 'Fablab',
              'state': isFablabBuilt ? 'built' : 'constructible',
              'currentLevel': fablabLevel,
              'maxLevel': fablabConfig.fablabMaxLevel,
              'requiredCampHeartLevel': 0,
              'stockCapacityBonusPerLevel':
                  fablabConfig.stockCapacityBonusPerFablabLevel,
              'isVisible': true,
            },
            'securityTower': <String, dynamic>{
              'buildingId': 'securityTower',
              'buildingType': 'security',
              'displayName': 'Tour de sécurité',
              'state': isSecurityTowerBuilt ? 'built' : 'constructible',
              'currentLevel': securityTowerLevel,
              'maxLevel': 3,
              'requiredCampHeartLevel':
                  securityTowerConfig.requiredCampHeartLevel,
              'isVisible': true,
            },
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> persistFigurineProgress({
    required String figurineId,
    required int xp,
    required int level,
  }) async {
    final user = await _currentUser();
    if (user == null) return;
    final ref = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('figurines')
        .doc(figurineId);
    final snapshot = await ref.get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final fields = Map<String, dynamic>.from(
      data['fields'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
    fields['x'] = '$xp';
    fields['xp'] = '$xp';
    fields['l'] = '$level';
    fields['level'] = '$level';

    await _runFirebaseSync('Sauvegarde XP P’TIPOTE', () {
      return ref.set(
        <String, dynamic>{
          'fields': fields,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  DocumentReference<Map<String, dynamic>> _zone0Doc(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('game')
        .doc('zone0');
  }

  int _readInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<User?> _currentUser() async {
    final current = _auth.currentUser;
    if (current != null) return current;
    try {
      return _auth
          .authStateChanges()
          .where((user) => user != null)
          .cast<User>()
          .first
          .timeout(const Duration(seconds: 4));
    } on Object {
      lastFirebaseError = 'Utilisateur Firebase non prêt.';
      firebaseSyncLabel = 'Synchro impossible';
      notifyListeners();
      return null;
    }
  }

  Future<void> _runFirebaseSync(
    String label,
    Future<void> Function() action,
  ) async {
    isFirebaseSyncing = true;
    firebaseSyncLabel = label;
    lastFirebaseError = null;
    notifyListeners();
    try {
      await action();
      lastFirebaseSyncAt = DateTime.now();
      firebaseSyncLabel = 'Synchronisé';
    } on FirebaseException catch (error) {
      lastFirebaseError = '${error.code}: ${error.message ?? error.plugin}';
      firebaseSyncLabel = 'Erreur Firebase';
      debugPrint('Zone0 Firebase sync failed: $label: $lastFirebaseError');
    } on Object catch (error) {
      lastFirebaseError = '$error';
      firebaseSyncLabel = 'Erreur Firebase';
      debugPrint('Zone0 Firebase sync failed: $label: $error');
    } finally {
      isFirebaseSyncing = false;
      notifyListeners();
    }
  }
}

class PtipoteXpGainResult {
  const PtipoteXpGainResult({
    required this.xp,
    required this.level,
    required this.leveledUp,
  });

  final int xp;
  final int level;
  final bool leveledUp;
}

class Zone0InventoryStack {
  Zone0InventoryStack({required this.resource, required this.amount});

  final String resource;
  int amount;
}

class InventoryAddResult {
  const InventoryAddResult({required this.addedAny, required this.pending});

  final bool addedAny;
  final Map<String, int> pending;

  bool get hasPending => pending.isNotEmpty;
}

class Zone0ActionResult {
  const Zone0ActionResult({required this.success, required this.message});

  final bool success;
  final String message;
}

enum ForageMissionStatus { active, completed }

class ForageMission {
  ForageMission({
    required this.id,
    required this.figurineId,
    required this.figurineName,
    required this.memberIds,
    required this.memberNames,
    required this.biome,
    required this.duration,
    required this.intensity,
    required this.startTime,
    required this.endTime,
    required this.expectedRewards,
    required this.vitalityCost,
    required this.vitalityCostByMember,
    required this.riskPercent,
    required this.riskLabel,
    required this.baseRiskPercent,
    required this.securityAtLaunch,
    required this.securityReduction,
    required this.xpGain,
    required this.xpGainByMember,
  });

  factory ForageMission.fromFirebase(Map<dynamic, dynamic> data) {
    final biome = _enumByName(
      ForageBiome.values,
      '${data['biome'] ?? ''}',
      ForageBiome.colline,
    );
    final duration = _enumByName(
      ForageDuration.values,
      '${data['duration'] ?? ''}',
      ForageDuration.oneHour,
    );
    final intensity = _enumByName(
      ForageIntensity.values,
      '${data['intensity'] ?? ''}',
      ForageIntensity.normal,
    );
    final mission = ForageMission(
      id: '${data['id'] ?? 'mission-${DateTime.now().microsecondsSinceEpoch}'}',
      figurineId: '${data['figurineId'] ?? ''}',
      figurineName: '${data['figurineName'] ?? 'P’TIPOTE'}',
      memberIds: _readStringList(data['memberIds']).isEmpty
          ? <String>['${data['figurineId'] ?? ''}']
          : _readStringList(data['memberIds']),
      memberNames: _readStringList(data['memberNames']).isEmpty
          ? <String>['${data['figurineName'] ?? 'P’TIPOTE'}']
          : _readStringList(data['memberNames']),
      biome: biome,
      duration: duration,
      intensity: intensity,
      startTime: _readDate(data['startTime']) ?? DateTime.now(),
      endTime: _readDate(data['endTime']) ?? DateTime.now(),
      expectedRewards: _readIntMap(data['expectedRewards']),
      vitalityCost: _readStaticInt(data['vitalityCost']),
      vitalityCostByMember: _readIntMap(data['vitalityCostByMember']),
      riskPercent: _readStaticInt(data['riskPercent']),
      riskLabel: '${data['riskLabel'] ?? 'normal'}',
      baseRiskPercent: _readStaticInt(data['baseRiskPercent']),
      securityAtLaunch: _readStaticInt(data['securityAtLaunch']),
      securityReduction: _readStaticInt(data['securityReduction']),
      xpGain: _readStaticInt(data['xpGain']),
      xpGainByMember: _readIntMap(data['xpGainByMember']),
    );
    mission.status = _enumByName(
      ForageMissionStatus.values,
      '${data['status'] ?? ''}',
      ForageMissionStatus.active,
    );
    return mission;
  }

  final String id;
  final String figurineId;
  final String figurineName;
  final List<String> memberIds;
  final List<String> memberNames;
  final ForageBiome biome;
  final ForageDuration duration;
  final ForageIntensity intensity;
  final DateTime startTime;
  final DateTime endTime;
  final Map<String, int> expectedRewards;
  final int vitalityCost;
  final Map<String, int> vitalityCostByMember;
  final int riskPercent;
  final String riskLabel;
  final int baseRiskPercent;
  final int securityAtLaunch;
  final int securityReduction;
  final int xpGain;
  final Map<String, int> xpGainByMember;
  ForageMissionStatus status = ForageMissionStatus.active;

  Map<String, dynamic> toFirebase() {
    return <String, dynamic>{
      'id': id,
      'figurineId': figurineId,
      'figurineName': figurineName,
      'memberIds': memberIds,
      'memberNames': memberNames,
      'biome': biome.name,
      'duration': duration.name,
      'intensity': intensity.name,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'expectedRewards': expectedRewards,
      'vitalityCost': vitalityCost,
      'vitalityCostByMember': vitalityCostByMember,
      'riskPercent': riskPercent,
      'riskLabel': riskLabel,
      'baseRiskPercent': baseRiskPercent,
      'securityAtLaunch': securityAtLaunch,
      'securityReduction': securityReduction,
      'xpGain': xpGain,
      'xpGainByMember': xpGainByMember,
      'status': status.name,
    };
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, int> _readIntMap(Object? value) {
    if (value is! Map) return const <String, int>{};
    return value.map(
      (key, amount) => MapEntry('$key', _readStaticInt(amount)),
    )..removeWhere((_, amount) => amount <= 0);
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static int _readStaticInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class PtipoteMissionReport {
  PtipoteMissionReport({
    required this.id,
    required this.figurineName,
    required this.biomeLabel,
    required this.durationLabel,
    required this.intensityLabel,
    required this.rewards,
    required this.incidentLabel,
    required this.xpGain,
    required this.leveledUp,
    required this.levelAfter,
    required this.vitalityRemaining,
    required this.hungerRemaining,
    required this.moodLabel,
    required this.finalStateLabel,
    required this.baseRiskPercent,
    required this.securityAtLaunch,
    required this.securityReduction,
    required this.realRiskPercent,
    required this.completedAt,
    required this.inventoryFull,
    this.read = false,
  });

  factory PtipoteMissionReport.fromFirebase(Map<dynamic, dynamic> data) {
    return PtipoteMissionReport(
      id: '${data['id'] ?? 'report-${DateTime.now().microsecondsSinceEpoch}'}',
      figurineName: '${data['figurineName'] ?? 'P’TIPOTE'}',
      biomeLabel: '${data['biomeLabel'] ?? 'Zone 0'}',
      durationLabel: '${data['durationLabel'] ?? '-'}',
      intensityLabel: '${data['intensityLabel'] ?? '-'}',
      rewards: ForageMission._readIntMap(data['rewards']),
      incidentLabel: '${data['incidentLabel'] ?? 'aucun'}',
      xpGain: ForageMission._readStaticInt(data['xpGain']),
      leveledUp: data['leveledUp'] == true,
      levelAfter: ForageMission._readStaticInt(data['levelAfter']),
      vitalityRemaining:
          ForageMission._readStaticInt(data['vitalityRemaining']),
      hungerRemaining: ForageMission._readStaticInt(data['hungerRemaining']),
      moodLabel: '${data['moodLabel'] ?? 'Bien'}',
      finalStateLabel: '${data['finalStateLabel'] ?? ''}',
      baseRiskPercent: ForageMission._readStaticInt(data['baseRiskPercent']),
      securityAtLaunch: ForageMission._readStaticInt(data['securityAtLaunch']),
      securityReduction:
          ForageMission._readStaticInt(data['securityReduction']),
      realRiskPercent: ForageMission._readStaticInt(data['realRiskPercent']),
      completedAt:
          ForageMission._readDate(data['completedAt']) ?? DateTime.now(),
      inventoryFull: data['inventoryFull'] == true,
      read: data['read'] == true,
    );
  }

  factory PtipoteMissionReport.system({required String message}) {
    final now = DateTime.now();
    return PtipoteMissionReport(
      id: 'system-${now.microsecondsSinceEpoch}',
      figurineName: 'Refuge',
      biomeLabel: 'Zone 0',
      durationLabel: 'instantané',
      intensityLabel: 'système',
      rewards: const <String, int>{},
      incidentLabel: message,
      xpGain: 0,
      leveledUp: false,
      levelAfter: 0,
      vitalityRemaining: 0,
      hungerRemaining: 0,
      moodLabel: 'Bien',
      finalStateLabel: message,
      baseRiskPercent: 0,
      securityAtLaunch: 0,
      securityReduction: 0,
      realRiskPercent: 0,
      completedAt: now,
      inventoryFull: false,
    );
  }

  final String id;
  final String figurineName;
  final String biomeLabel;
  final String durationLabel;
  final String intensityLabel;
  final Map<String, int> rewards;
  final String incidentLabel;
  final int xpGain;
  final bool leveledUp;
  final int levelAfter;
  final int vitalityRemaining;
  final int hungerRemaining;
  final String moodLabel;
  final String finalStateLabel;
  final int baseRiskPercent;
  final int securityAtLaunch;
  final int securityReduction;
  final int realRiskPercent;
  final DateTime completedAt;
  final bool inventoryFull;
  bool read;

  Map<String, dynamic> toFirebase() {
    return <String, dynamic>{
      'id': id,
      'figurineName': figurineName,
      'biomeLabel': biomeLabel,
      'durationLabel': durationLabel,
      'intensityLabel': intensityLabel,
      'rewards': rewards,
      'incidentLabel': incidentLabel,
      'xpGain': xpGain,
      'leveledUp': leveledUp,
      'levelAfter': levelAfter,
      'vitalityRemaining': vitalityRemaining,
      'hungerRemaining': hungerRemaining,
      'moodLabel': moodLabel,
      'finalStateLabel': finalStateLabel,
      'baseRiskPercent': baseRiskPercent,
      'securityAtLaunch': securityAtLaunch,
      'securityReduction': securityReduction,
      'realRiskPercent': realRiskPercent,
      'completedAt': Timestamp.fromDate(completedAt),
      'inventoryFull': inventoryFull,
      'read': read,
    };
  }
}
