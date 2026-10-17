import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'elevage_config.dart';
import 'elevage_engine.dart';

/// Élevage stays locally persisted, but its elapsed-time calculations are
/// calibrated against the signed-in player's Firestore server clock whenever
/// it is available. A cached offset is retained for offline launches.
class ElevageRepository {
  static const String saveKey = 'ptipote:elevage:save';
  static const String backupKey = 'ptipote:elevage:save:backup';
  static const String configKey = 'ptipote:elevage:config';
  static const String clockOffsetKey = 'ptipote:elevage:serverClockOffsetMs';

  ElevageRepository(this._preferences);

  final SharedPreferencesAsync _preferences;
  int _serverClockOffsetMs = 0;
  bool serverClockSynchronized = false;

  static Future<ElevageRepository> create() async {
    final repository = ElevageRepository(SharedPreferencesAsync());
    await repository._restoreClockOffset();
    await repository.synchronizeServerClock();
    return repository;
  }

  int get now => DateTime.now().millisecondsSinceEpoch + _serverClockOffsetMs;

  Future<void> _restoreClockOffset() async {
    _serverClockOffsetMs =
        await _preferences.getInt(clockOffsetKey) ?? _serverClockOffsetMs;
  }

  /// The sampled timestamp is written by Firestore, then read from the server
  /// to derive a local offset. Network/auth failures deliberately retain the
  /// last verified offset instead of freezing the biological clock.
  Future<void> synchronizeServerClock() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final clock = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('elevageMeta')
          .doc('clock');
      await clock.set(<String, Object?>{
        'sampledAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final snapshot = await clock.get(const GetOptions(source: Source.server));
      final timestamp = snapshot.data()?['sampledAt'] as Timestamp?;
      if (timestamp == null) return;
      _serverClockOffsetMs = timestamp.millisecondsSinceEpoch -
          DateTime.now().millisecondsSinceEpoch;
      await _preferences.setInt(clockOffsetKey, _serverClockOffsetMs);
      serverClockSynchronized = true;
    } catch (_) {
      // The local save remains usable offline; [now] still advances normally.
    }
  }

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
      final schemaVersion = (record['schemaVersion'] as num?)?.toInt();
      // Configuration additive: older Dashboard records keep every known
      // setting and receive safe defaults for newly introduced fields (such as
      // sleep windows and Recycler rules). Only an unknown future schema is
      // rejected so an app downgrade cannot silently reinterpret it.
      if (schemaVersion == null ||
          schemaVersion > elevageConfigSchemaVersion ||
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
