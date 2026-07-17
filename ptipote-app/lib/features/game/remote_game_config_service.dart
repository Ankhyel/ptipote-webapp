import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../figurines/ptipote_stats_config.dart';
import 'remote_zone0_settings.dart';

/// Shared entry point for values published by the internal Dashboard.
///
/// New configuration sections can use the same `gameConfigs/zone0` document
/// without changing player save data.
class RemoteGameConfigService extends ChangeNotifier {
  RemoteGameConfigService._();

  static final RemoteGameConfigService instance = RemoteGameConfigService._();
  static const String _documentId = 'zone0';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    final user = _auth.currentUser;
    if (user == null) return;
    _started = true;
    final reference = _firestore.collection('gameConfigs').doc(_documentId);

    try {
      final initial = await reference.get();
      _apply(initial.data());
    } catch (_) {
      _apply(null);
    }
    _subscription = reference.snapshots().listen(
      (snapshot) => _apply(snapshot.data()),
      onError: (_) {
        // Default values remain available if remote configuration is offline.
      },
    );
  }

  void _apply(Map<String, dynamic>? document) {
    final rawStats = document?['ptipoteStats'];
    applyRemotePtipoteStatsConfig(
      rawStats is Map ? Map<String, dynamic>.from(rawStats) : null,
    );
    final rawZone0Settings = document?['zone0Settings'];
    applyRemoteZone0Settings(
      rawZone0Settings is Map
          ? Map<String, dynamic>.from(rawZone0Settings)
          : null,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
