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
  }) =>
      _mutate((current) => ElevageDomain.adopt(
            source: current,
            alcoveId: alcoveId,
            name: name,
            physical: physical,
            physicalFigureRef: physicalFigureRef,
            now: _now,
            config: config,
          ));

  Future<void> offerFood(String id, String item) => _mutate(
      (current) => ElevageDomain.offerFood(current, id, item, _now, config));
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
  Future<void> recordCommunication(String id, String category) => _mutate(
      (current) => ElevageDomain.recordCommunication(current, id, category));
  Future<void> wake(String id) =>
      _mutate((current) => ElevageDomain.wake(current, id, _now, config));
  Future<void> addDevInventory() => _mutate(ElevageDomain.addDevInventory);
  Future<void> startForaging(String id, String biome) => _mutate((current) =>
      ElevageDomain.startForaging(current, id, biome, _now, config));
  Future<void> claimForaging(String id, String pointId) => _mutate(
      (current) => ElevageDomain.claimForaging(current, id, pointId, _now));
  Future<void> craft(ElevageRecipe recipe) =>
      _mutate((current) => ElevageDomain.craft(current, recipe, _now, config));
  Future<void> place(String alcoveId, int slot, String instanceId) =>
      _mutate((current) =>
          ElevageDomain.place(current, alcoveId, slot, instanceId, _now));
  Future<void> remove(String alcoveId, int slot) =>
      _mutate((current) => ElevageDomain.remove(current, alcoveId, slot));
  Future<void> refreshAlcove(String alcoveId) => _mutate((current) =>
      ElevageDomain.refreshAlcove(current, alcoveId, _now, config));
  Future<void> harvestLocal(String alcoveId, int slot, String itemId) =>
      _mutate((current) =>
          ElevageDomain.harvestLocal(current, alcoveId, slot, itemId, _now));
  Future<void> refreshRequest(String individualId) => _mutate((current) =>
      ElevageDomain.refreshRequest(current, individualId, _now, config));
  Future<void> buyTreat(String item) =>
      _mutate((current) => ElevageDomain.buyTreat(current, item, config));
  Future<void> sellGeneric(String item) =>
      _mutate((current) => ElevageDomain.sellGeneric(current, item, config));
  Future<void> moveOut(String alcoveId) =>
      _mutate((current) => ElevageDomain.moveOut(current, alcoveId, config));
  Future<void> metamorphose(String id) =>
      _mutate((current) => ElevageDomain.metamorphose(current, id, _now));

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
      state = action(current);
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

  int get _now => DateTime.now().millisecondsSinceEpoch;
}
