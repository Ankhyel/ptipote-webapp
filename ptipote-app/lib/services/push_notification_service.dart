import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class PushNotificationService {
  PushNotificationService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;

  Future<void> start() async {
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _authSubscription ??= _auth.authStateChanges().listen((user) {
      if (user == null) return;
      unawaited(_registerCurrentToken(user));
    });

    _tokenSubscription ??= _messaging.onTokenRefresh.listen((token) {
      final user = _auth.currentUser;
      if (user == null) return;
      unawaited(_saveToken(user, token));
    });

    final user = _auth.currentUser;
    if (user != null) {
      await _registerCurrentToken(user);
    }
  }

  Future<void> _registerCurrentToken(User user) async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await _messaging.getToken();
    if (token == null || token.trim().isEmpty) return;
    await _saveToken(user, token);
  }

  Future<void> _saveToken(User user, String token) async {
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('fcmTokens')
        .doc(token)
        .set(
      <String, dynamic>{
        'token': token,
        'platform': 'ios',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _authSubscription = null;
    _tokenSubscription = null;
  }
}
