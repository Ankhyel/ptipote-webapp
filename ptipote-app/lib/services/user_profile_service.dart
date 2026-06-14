import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.email,
  });

  final String uid;
  final String username;
  final String displayName;
  final String email;

  String get ownerName {
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    final user = username.trim();
    if (user.isNotEmpty) return user;
    return email.trim();
  }

  String get breederNumber {
    final user = username.trim();
    if (user.isNotEmpty) return user;
    return ownerName;
  }
}

class UserProfileService {
  UserProfileService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('users').doc(uid);

  Stream<UserProfile?> watchMyProfile() {
    final user = _auth.currentUser;
    if (user == null) return Stream<UserProfile?>.value(null);
    return _doc(user.uid)
        .snapshots()
        .map((snapshot) => _fromSnapshot(user, snapshot.data()));
  }

  Future<UserProfile> getOrCreateMyProfile() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');

    final ref = _doc(user.uid);
    final snapshot = await ref.get();
    final profile = _fromSnapshot(user, snapshot.data());
    if (snapshot.exists) return profile;

    final data = <String, dynamic>{
      'uid': user.uid,
      'email': user.email ?? '',
      'username': _defaultUsername(user),
      'displayName': user.displayName ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await ref.set(data, SetOptions(merge: true));
    return _fromSnapshot(user, data);
  }

  Future<void> saveMyProfile(
      {required String username, required String displayName}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');

    await _doc(user.uid).set(
      <String, dynamic>{
        'uid': user.uid,
        'email': user.email ?? '',
        'username': username.trim(),
        'displayName': displayName.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  UserProfile _fromSnapshot(User user, Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    return UserProfile(
      uid: user.uid,
      username: '${source['username'] ?? _defaultUsername(user)}',
      displayName: '${source['displayName'] ?? user.displayName ?? ''}',
      email: '${source['email'] ?? user.email ?? ''}',
    );
  }

  String _defaultUsername(User user) {
    final email = user.email ?? '';
    final local = email.split('@').first.trim();
    if (local.isNotEmpty) return local;
    return user.uid.substring(0, user.uid.length < 8 ? user.uid.length : 8);
  }
}
