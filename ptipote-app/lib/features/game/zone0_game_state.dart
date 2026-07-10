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
  final Map<String, PtipoteAutoAssignmentPreference> autoPreferenceOverrides =
      <String, PtipoteAutoAssignmentPreference>{};
  final List<Zone0InventoryStack> inventory = <Zone0InventoryStack>[];
  final List<ForageMission> missions = <ForageMission>[];
  final List<PtipoteMissionReport> reports = <PtipoteMissionReport>[];

  int refugeSafety = lisiereForageConfig.refugeSafetyFallback;

  int vitalityFor(PtipoteFigurine figurine) {
    return vitalityOverrides[figurine.id] ?? figurine.vitality;
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

  ForageMission startForageMission({
    required PtipoteFigurine figurine,
    required ForageBiome biome,
    required ForageDuration duration,
    required ForageIntensity intensity,
    required Map<String, int> expectedRewards,
    required int vitalityCost,
    required int riskPercent,
    required String riskLabel,
  }) {
    final start = DateTime.now();
    final durationConfig = lisiereForageConfig.durations[duration]!;
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
        vitalityRemaining: vitality,
        completedAt: completedAt,
        inventoryFull: inventoryResult.hasPending,
      ),
    );
    mission.status = ForageMissionStatus.completed;
  }
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
  final int vitalityRemaining;
  final DateTime completedAt;
  final bool inventoryFull;
  bool read = false;
}
