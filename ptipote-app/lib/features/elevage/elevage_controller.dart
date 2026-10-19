import 'package:flutter/foundation.dart';

import 'elevage_config.dart';
import 'elevage_engine.dart';
import 'elevage_repository.dart';

class ElevageController extends ChangeNotifier {
  ElevageController(this._repository);

  final ElevageRepository _repository;
  ElevageConfig config = defaultElevageConfig;
  ElevageSave? state;
  bool loading = true;
  String? error;
  String? forcedDayNightPhase;

  String dayNightPhase(int now) =>
      forcedDayNightPhase ?? ElevageDomain.dayNightPhase(now, config);

  /// All Élevage elapsed-time systems use this calibrated server clock.
  int get now => _repository.now;

  void forceDayNightPhase(String? phase) {
    if (!config.devMode) return;
    forcedDayNightPhase = phase;
    notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    config = await _repository.loadConfig();
    state = await _repository.loadSave();
    if (state != null) {
      state = ElevageDomain.processReturns(state!, _now);
      state = ElevageDomain.refreshRefugeProgress(state!, _now, config);
      state = ElevageDomain.refreshSatietyState(state!, _now, config);
      state = ElevageDomain.refreshExploration(state!, _now, config);
      // Resolve every local producer and the shared maintenance ledger on
      // return from background. The domain caps consumption at depletion, so
      // an offline absence can never create an energy debt.
      for (final alcove in state!.data['alcoves'] as List) {
        state = ElevageDomain.refreshAlcove(
            state!, (alcove as Map)['id'] as String, _now, config);
      }
      await _persist();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> initialize() async {
    state = ElevageSave.initial(config, now: _now);
    await _persist();
  }

  Future<void> resetGame({bool resetConfig = false}) async {
    if (resetConfig) {
      await _repository.resetConfig();
      config = defaultElevageConfig;
    }
    state = ElevageDomain.resetGame(config, _now);
    error = null;
    await _persist();
    notifyListeners();
  }

  Future<void> resetAlcoves() =>
      _mutate((current) => ElevageDomain.resetAlcoves(current, config, _now));

  Future<void> adopt({
    required String alcoveId,
    required String name,
    required bool physical,
    String? physicalFigureRef,
    String family = 'MINERAL',
    String nature = 'RESONANCE',
  }) =>
      _mutate((current) => ElevageDomain.adopt(
            source: current,
            alcoveId: alcoveId,
            name: name,
            physical: physical,
            physicalFigureRef: physicalFigureRef,
            family: family,
            nature: nature,
            now: _now,
            config: config,
          ));

  Future<void> offerFood(String id, String item) => _mutate(
      (current) => ElevageDomain.offerFood(current, id, item, _now, config));
  Future<void> setSatiety(String id, int value) => _mutate((current) =>
      ElevageDomain.setIndividualSatiety(current, id, value, _now));
  Future<void> addSatiety(String id, int amount) => _mutate((current) =>
      ElevageDomain.addIndividualSatiety(current, id, amount, _now, config));
  Future<void> simulateSatietyElapsedHours(String id, int hours) =>
      _mutate((current) => ElevageDomain.simulateSatietyElapsedHours(
          current, id, hours, _now, config));
  Future<void> refreshSatiety() => _mutate(
      (current) => ElevageDomain.refreshSatietyState(current, _now, config));
  Future<void> offerStructural(String id, String item) => _mutate((current) =>
      ElevageDomain.offerStructural(current, id, item, _now, config));
  Future<String?> placeSceneItem(
      String alcoveId, String item, String zoneId) async {
    await _mutate((current) => ElevageDomain.placeSceneItem(
        current, alcoveId, item, zoneId, _now, config));
    if (error != null || state == null) return null;
    return ElevageDomain.sceneItems(state!, alcoveId)
        .where((entry) => entry['zoneId'] == zoneId)
        .singleOrNull?['instanceId'] as String?;
  }

  Future<void> recoverSceneItem(String alcoveId, String instanceId) =>
      _mutate((current) =>
          ElevageDomain.recoverSceneItem(current, alcoveId, instanceId));
  Future<void> relocateSceneItem(
          String alcoveId, String instanceId, String targetZoneId) =>
      _mutate((current) => ElevageDomain.relocateSceneItem(
          current, alcoveId, instanceId, targetZoneId, config));
  Future<void> placeHabitatItem(
          String alcoveId, String instanceId, String zoneId) =>
      _mutate((current) => ElevageDomain.placeHabitatItem(
          current, alcoveId, instanceId, zoneId, _now, config));
  Future<void> recoverHabitatItem(String alcoveId, String instanceId) =>
      _mutate((current) =>
          ElevageDomain.recoverHabitatItem(current, alcoveId, instanceId));
  Future<void> moveHabitatItem(String individualId, String alcoveId,
          String instanceId, String zoneId) =>
      _mutate((current) => ElevageDomain.moveHabitatItem(
          current, individualId, alcoveId, instanceId, zoneId, _now, config));
  Future<void> resonateFormation(
          String individualId, String alcoveId, String instanceId) =>
      _mutate((current) => ElevageDomain.resonateFormation(
          current, individualId, alcoveId, instanceId, _now, config));
  Future<void> interactDecoration(
          String individualId, String alcoveId, String instanceId) =>
      _mutate((current) => ElevageDomain.interactDecoration(
          current, individualId, alcoveId, instanceId, _now, config));
  Future<void> useFurniture(
          String individualId, String alcoveId, String instanceId) =>
      _mutate((current) => ElevageDomain.useFurniture(
          current, individualId, alcoveId, instanceId, _now, config));
  Future<ElevageSceneItemOutcome?> interactSceneItem(
      String individualId, String alcoveId, String instanceId) async {
    final current = state;
    if (current == null) return null;
    ElevageSceneItemOutcome? outcome;
    await _mutate((next) {
      outcome = ElevageDomain.sceneItemOutcome(
          next, individualId, alcoveId, instanceId, _now, config,
          phaseOverride: forcedDayNightPhase);
      return ElevageDomain.interactSceneItem(
          next, individualId, alcoveId, instanceId, _now, config,
          phaseOverride: forcedDayNightPhase);
    });
    return error == null ? outcome : null;
  }

  Future<void> observeShade(String id) => _mutate(
      (current) => ElevageDomain.observeShade(current, id, _now, config));
  Future<void> follow(String id, String zoneId) => _mutate(
      (current) => ElevageDomain.follow(current, id, zoneId, _now, config));
  Future<void> cuddle(String id, {int durationMs = 1000}) =>
      _mutate((current) => ElevageDomain.cuddle(current, id, _now, config,
          durationMs: durationMs));
  Future<void> recordCommunication(String id, String category,
          {String? conceptId}) =>
      _mutate((current) => ElevageDomain.recordCommunication(
          current, id, category,
          conceptId: conceptId));
  Future<void> wake(String id) =>
      _mutate((current) => ElevageDomain.wake(current, id, _now, config));
  Future<void> addDevInventory() => _mutate(ElevageDomain.addDevInventory);
  Future<void> startForaging(String id, String biome) => _mutate((current) =>
      ElevageDomain.startForaging(current, id, biome, _now, config));
  Future<void> claimForaging(String id, String pointId) => _mutate(
      (current) => ElevageDomain.claimForaging(current, id, pointId, _now));
  Future<void> startExploration(String sectorId,
          {String? companionPtipoteId}) =>
      _mutate((current) => ElevageDomain.startExploration(
          current, sectorId, _now, config,
          companionPtipoteId: companionPtipoteId));
  Future<void> claimExploration() => _mutate(
      (current) => ElevageDomain.claimExploration(current, _now, config));
  Future<void> refreshExploration() => _mutate(
      (current) => ElevageDomain.refreshExploration(current, _now, config));
  Future<void> craft(ElevageRecipe recipe) =>
      _mutate((current) => ElevageDomain.craft(current, recipe, _now, config));
  Future<void> craftModule(ElevageModuleDefinition module) => _mutate(
      (current) => ElevageDomain.craftModule(current, module, _now, config));
  Future<void> craftBioBattery() => _mutate(
      (current) => ElevageDomain.craftBioBattery(current, _now, config));

  Future<void> craftBatteryExport(String alcoveId) => _mutate((current) =>
      ElevageDomain.craftBatteryExport(current, alcoveId, _now, config));
  Future<void> insertBattery(String alcoveId, String batteryInstanceId) =>
      _mutate((current) => ElevageDomain.insertBattery(
          current, alcoveId, batteryInstanceId, _now));
  Future<void> craftBiogenerator() => _mutate(
      (current) => ElevageDomain.craftBiogenerator(current, _now, config));
  Future<void> installBiogenerator(String alcoveId, String instanceId) =>
      _mutate((current) => ElevageDomain.installBiogenerator(
          current, alcoveId, instanceId, _now));
  Future<void> transferBiogeneratorFuel(
          String alcoveId, String resourceId, int quantity) =>
      _mutate((current) => ElevageDomain.transferBiogeneratorFuel(
          current, alcoveId, resourceId, quantity, config));
  Future<void> installBiogeneratorModule(
          String alcoveId, String moduleInstanceId) =>
      _mutate((current) => ElevageDomain.installBiogeneratorModule(
          current, alcoveId, moduleInstanceId, config));
  Future<void> removeBiogeneratorModule(
          String alcoveId, String moduleInstanceId) =>
      _mutate((current) => ElevageDomain.removeBiogeneratorModule(
          current, alcoveId, moduleInstanceId));
  Future<void> addTrackerXp(String individualId, int amount) =>
      _mutate((current) =>
          ElevageDomain.addTrackerXp(current, individualId, amount, config));
  Future<void> setTrackerXp(String individualId, int amount) =>
      _mutate((current) =>
          ElevageDomain.setTrackerXp(current, individualId, amount, config));
  Future<void> forceTrackerLevel(String individualId, int level) =>
      _mutate((current) => ElevageDomain.forceTrackerLevel(
          current, individualId, level, config));
  Future<void> addTrust(int amount) => _mutate((current) =>
      ElevageDomain.addTrust(current, amount, now: _now, reasonType: 'DEBUG'));
  Future<void> setTrust(int value) =>
      _mutate((current) => ElevageDomain.setTrust(current, value, now: _now));
  Future<void> simulateCriticalWellbeingTrustPeriod(String individualId) =>
      _mutate((current) => ElevageDomain.simulateCriticalWellbeingTrustPeriod(
          current, individualId, _now, config));
  // Legacy controller aliases kept for old dashboard callers.
  Future<void> addContribution(int amount) => addTrust(amount);
  Future<void> setContribution(int value) => setTrust(value);
  Future<void> startAlcoveConstruction(String alcoveId, String route) =>
      _mutate((current) => ElevageDomain.startAlcoveConstruction(
          current, alcoveId, route, _now, config));
  Future<void> chooseJuvenileLoan(String individualId, String structureId) =>
      _mutate((current) => ElevageDomain.chooseJuvenileLoan(
          current, individualId, structureId, _now, config));
  Future<void> place(String alcoveId, int slot, String instanceId) =>
      _mutate((current) =>
          ElevageDomain.place(current, alcoveId, slot, instanceId, _now));
  Future<void> remove(String alcoveId, int slot) =>
      _mutate((current) => ElevageDomain.remove(current, alcoveId, slot));
  Future<void> installModule(
          String alcoveId, int slot, String moduleInstanceId) =>
      _mutate((current) => ElevageDomain.installModule(
          current, alcoveId, slot, moduleInstanceId, config));
  Future<void> removeModule(
          String alcoveId, int slot, String moduleInstanceId) =>
      _mutate((current) => ElevageDomain.removeModule(
          current, alcoveId, slot, moduleInstanceId));
  Future<void> refreshAlcove(String alcoveId) => _mutate((current) =>
      ElevageDomain.refreshAlcove(current, alcoveId, _now, config));
  Future<void> harvestLocal(String alcoveId, int slot, String itemId) =>
      _mutate((current) => ElevageDomain.harvestLocal(
          current, alcoveId, slot, itemId, _now, config));
  Future<void> recycle(String itemId, int quantity) => _mutate(
      (current) => ElevageDomain.recycle(current, itemId, quantity, config));
  Future<void> refreshRequest(String individualId) => _mutate((current) =>
      ElevageDomain.refreshRequest(current, individualId, _now, config));
  Future<void> buyTreat(String item) =>
      _mutate((current) => ElevageDomain.buyTreat(current, item, config));
  Future<void> sellGeneric(String item) =>
      _mutate((current) => ElevageDomain.sellGeneric(current, item, config));
  Future<void> moveOut(String alcoveId) =>
      _mutate((current) => ElevageDomain.moveOut(current, alcoveId, config));
  Future<void> metamorphose(String id) => _mutate(
      (current) => ElevageDomain.metamorphose(current, id, _now, config));

  Future<void> saveConfig(ElevageConfig next) async {
    try {
      validateElevageConfig(next);
      await _repository.saveConfig(next);
      config = (await _repository.loadConfig());
      if (state != null) {
        state!.data['activeConfigRevision'] = config.revision;
        await _persist();
      }
      error = null;
    } catch (exception) {
      error = exception.toString();
    }
    notifyListeners();
  }

  Future<void> resetConfig() async {
    await _repository.resetConfig();
    config = defaultElevageConfig;
    if (state != null) {
      state!.data['activeConfigRevision'] = config.revision;
      await _persist();
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> get notifications {
    final current = state;
    if (current == null) return const <Map<String, dynamic>>[];
    return (current.data['pendingNotifications'] as List)
        .whereType<Map>()
        .where((item) => item['acknowledgedAt'] == null)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> acknowledgeNotifications() async {
    final current = state;
    if (current == null) return;
    final next = current.copy();
    for (final item in next.data['pendingNotifications'] as List) {
      if (item is Map && item['acknowledgedAt'] == null) {
        item['acknowledgedAt'] = _now;
      }
    }
    state = next;
    await _persist();
  }

  Future<void> _mutate(ElevageSave Function(ElevageSave state) action) async {
    final current = state;
    if (current == null) return;
    try {
      state =
          ElevageDomain.refreshRefugeProgress(action(current), _now, config);
      error = null;
      await _persist();
    } catch (exception) {
      error = exception.toString();
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final current = state;
    if (current == null) return;
    current.data['activeConfigRevision'] = config.revision;
    await _repository.save(current);
  }

  int get _now => now;
}
