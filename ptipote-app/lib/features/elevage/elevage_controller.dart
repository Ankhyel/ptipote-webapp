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
  Future<void> offerStructural(String id, String item) => _mutate(
      (current) => ElevageDomain.offerStructural(current, id, item, _now));
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
