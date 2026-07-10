import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../figurines/ptipote_figurine.dart';
import '../figurines/ptipote_stats_config.dart';
import 'lisiere_forage_config.dart';

class Zone0GameState extends ChangeNotifier {
  Zone0GameState._();

  static final Zone0GameState instance = Zone0GameState._();
  final math.Random _random = math.Random();

  final Map<String, int> vitalityOverrides = <String, int>{};
  final Map<String, int> xpOverrides = <String, int>{};
  final Map<String, int> levelOverrides = <String, int>{};
  final Map<String, PtipoteAutoAssignmentPreference> autoPreferenceOverrides =
      <String, PtipoteAutoAssignmentPreference>{};
  final List<Zone0InventoryStack> inventory = <Zone0InventoryStack>[];
  final List<ForageMission> missions = <ForageMission>[];
  final List<PtipoteMissionReport> reports = <PtipoteMissionReport>[];

  int refugeSafety = lisiereForageConfig.refugeSafetyFallback;

  int vitalityFor(PtipoteFigurine figurine) {
    return vitalityOverrides[figurine.id] ?? figurine.vitality;
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
          mission.figurineId == figurineId &&
          mission.status == ForageMissionStatus.active,
    );
  }

  int resourceAmount(String resource) {
    return inventory
        .where((stack) => stack.resource == resource)
        .fold(0, (total, stack) => total + stack.amount);
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
    if (removed > 0) notifyListeners();
    return removed;
  }

  ForageMission startForageMission({
    required PtipoteFigurine figurine,
    required ForageBiome biome,
    required ForageDuration duration,
    required ForageIntensity intensity,
    required Map<String, int> expectedRewards,
    required int vitalityCost,
    required int riskPercent,
    required String riskLabel,
    required int xpGain,
  }) {
    final start = DateTime.now();
    final durationConfig = lisiereForageConfig.durations[duration]!;
    levelOverrides.putIfAbsent(figurine.id, () => figurine.levelValue);
    xpOverrides.putIfAbsent(figurine.id, () => figurine.xpValue);
    final mission = ForageMission(
      id: 'mission-${start.microsecondsSinceEpoch}',
      figurineId: figurine.id,
      figurineName: figurine.displayName,
      biome: biome,
      duration: duration,
      intensity: intensity,
      startTime: start,
      endTime: start.add(
        durationConfig.realDuration(lisiereForageConfig.forageTimeScale),
      ),
      expectedRewards: expectedRewards,
      vitalityCost: vitalityCost,
      riskPercent: riskPercent,
      riskLabel: riskLabel,
      xpGain: xpGain,
    );
    missions.add(mission);
    vitalityOverrides[figurine.id] = math.max(
      0,
      vitalityFor(figurine) - vitalityCost,
    );
    notifyListeners();
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
    if (resolvedAny) notifyListeners();
    return resolvedAny;
  }

  int freeInventorySlots() {
    return lisiereForageConfig.inventorySlotLimit - inventory.length;
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

      while (remaining > 0 &&
          inventory.length < lisiereForageConfig.inventorySlotLimit) {
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

    return InventoryAddResult(addedAny: addedAny, pending: pending);
  }

  void markReportsRead() {
    var changed = false;
    for (final report in reports) {
      if (!report.read) changed = true;
      report.read = true;
    }
    if (changed) notifyListeners();
  }

  void _resolveMission(
    ForageMission mission, {
    required DateTime completedAt,
  }) {
    final biome = lisiereForageConfig.biomes[mission.biome]!;
    final duration = lisiereForageConfig.durations[mission.duration]!;
    final intensity = lisiereForageConfig.intensities[mission.intensity]!;
    var rewards = Map<String, int>.from(mission.expectedRewards);
    var incident = 'aucun';

    if (_random.nextInt(100) < mission.riskPercent) {
      final hazards =
          ForageHazard.values.where((h) => h != ForageHazard.none).toList();
      final hazard = hazards[_random.nextInt(hazards.length)];
      switch (hazard) {
        case ForageHazard.pollution:
          rewards['Organique'] = ((rewards['Organique'] ?? 0) * 0.8).round();
          incident = 'pollution légère, gains organiques réduits';
        case ForageHazard.droneErrant:
          rewards = rewards
              .map((key, value) => MapEntry(key, (value * 0.75).round()));
          incident = 'drone errant, retour anticipé';
        case ForageHazard.climatDifficile:
          rewards = rewards
              .map((key, value) => MapEntry(key, (value * 0.85).round()));
          incident = 'climat difficile, récolte ralentie';
        case ForageHazard.none:
          break;
      }
    }

    final inventoryResult = addResources(rewards);
    final xpResult = addMissionXp(mission.figurineId, mission.xpGain);
    final vitality = vitalityOverrides[mission.figurineId] ?? 0;
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
        leveledUp: xpResult.leveledUp,
        levelAfter: xpResult.level,
        vitalityRemaining: vitality,
        completedAt: completedAt,
        inventoryFull: inventoryResult.hasPending,
      ),
    );
    mission.status = ForageMissionStatus.completed;
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
    return PtipoteXpGainResult(
      xp: xp,
      level: level,
      leveledUp: leveledUp,
    );
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

enum ForageMissionStatus { active, completed }

class ForageMission {
  ForageMission({
    required this.id,
    required this.figurineId,
    required this.figurineName,
    required this.biome,
    required this.duration,
    required this.intensity,
    required this.startTime,
    required this.endTime,
    required this.expectedRewards,
    required this.vitalityCost,
    required this.riskPercent,
    required this.riskLabel,
    required this.xpGain,
  });

  final String id;
  final String figurineId;
  final String figurineName;
  final ForageBiome biome;
  final ForageDuration duration;
  final ForageIntensity intensity;
  final DateTime startTime;
  final DateTime endTime;
  final Map<String, int> expectedRewards;
  final int vitalityCost;
  final int riskPercent;
  final String riskLabel;
  final int xpGain;
  ForageMissionStatus status = ForageMissionStatus.active;
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
    required this.completedAt,
    required this.inventoryFull,
  });

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
  final DateTime completedAt;
  final bool inventoryFull;
  bool read = false;
}
