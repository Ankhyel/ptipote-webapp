import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'elevage_config.dart';
import 'elevage_engine.dart';

/// Local V0 persistence. It deliberately does not read Zone 0 nor Firestore.
class ElevageRepository {
  static const String saveKey = 'ptipote:elevage:save';
  static const String backupKey = 'ptipote:elevage:save:backup';
  static const String configKey = 'ptipote:elevage:config';

  ElevageRepository(this._preferences);

  final SharedPreferencesAsync _preferences;

  static Future<ElevageRepository> create() async =>
      ElevageRepository(SharedPreferencesAsync());

  Future<ElevageSave?> loadSave() async {
    final raw = await _preferences.getString(saveKey);
    if (raw == null) return null;
    try {
      return ElevageSave.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      // The raw payload is intentionally preserved for a later recovery UI.
      return null;
    }
  }

  Future<void> save(ElevageSave state) async {
    final payload = state.toJson()
      ..['savedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _preferences.setString(saveKey, jsonEncode(payload));
  }

  Future<void> backupRawSave() async {
    final raw = await _preferences.getString(saveKey);
    if (raw != null) await _preferences.setString(backupKey, raw);
  }

  Future<ElevageConfig> loadConfig() async {
    final raw = await _preferences.getString(configKey);
    if (raw == null) return defaultElevageConfig;
    try {
      final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (record['schemaVersion'] != elevageConfigSchemaVersion ||
          record['overrides'] is! Map) {
        return defaultElevageConfig;
      }
      return ElevageConfig.fromJson(
        Map<String, dynamic>.from(record['overrides'] as Map),
      );
    } catch (_) {
      return defaultElevageConfig;
    }
  }

  Future<void> saveConfig(ElevageConfig config) async {
    final revision = 'local:${DateTime.now().millisecondsSinceEpoch}';
    final updated = config.copyWith(revision: revision);
    validateElevageConfig(updated);
    await _preferences.setString(
      configKey,
      jsonEncode(<String, dynamic>{
        'schemaVersion': elevageConfigSchemaVersion,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'revision': revision,
        'overrides': updated.toJson(),
      }),
    );
  }

  Future<void> resetConfig() => _preferences.remove(configKey);
}
