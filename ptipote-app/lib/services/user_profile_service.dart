import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.email,
    required this.role,
  });

  final String uid;
  final String username;
  final String displayName;
  final String email;
  final String role;

  bool get isAdmin => role == 'admin';
  bool get isDev => role == 'dev';
  bool get canSeeDiagnostics => isAdmin || isDev;

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

  static const Set<String> _bootstrapAdminUids = <String>{
    'taNxWXLMh2gJx5CHgmBB8Phl4c93',
  };

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _publicDoc(String uid) =>
      _firestore.collection('publicProfiles').doc(uid);

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
    final snapshot = await _getProfileSnapshot(ref);
    final profile = _fromSnapshot(user, snapshot.data());
    if (snapshot.exists) {
      await _syncBootstrapRoleIfNeeded(user.uid, snapshot.data());
      await _publishProfile(profile);
      return profile;
    }

    final data = <String, dynamic>{
      'uid': user.uid,
      'email': user.email ?? '',
      'username': _defaultUsername(user),
      'usernameLower': _defaultUsername(user).toLowerCase(),
      'displayName': user.displayName ?? '',
      'displayNameLower': (user.displayName ?? '').toLowerCase(),
      'role': _bootstrapAdminUids.contains(user.uid) ? 'admin' : 'user',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      final batch = _firestore.batch();
      batch.set(ref, data, SetOptions(merge: true));
      batch.set(
        _publicDoc(user.uid),
        _publicProfileData(
          uid: user.uid,
          username: '${data['username'] ?? ''}',
          displayName: '${data['displayName'] ?? ''}',
        ),
        SetOptions(merge: true),
      );
      await batch.commit();
    } on FirebaseException catch (error) {
      if (error.code != 'unavailable') rethrow;
    }
    return _fromSnapshot(user, data);
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getProfileSnapshot(
    DocumentReference<Map<String, dynamic>> ref,
  ) =>
      ref.get(const GetOptions(source: Source.server));

  Future<void> saveMyProfile(
      {required String username, required String displayName}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');

    final cleanUsername = username.trim();
    final cleanDisplayName = displayName.trim();
    final batch = _firestore.batch();
    batch.set(
      _doc(user.uid),
      <String, dynamic>{
        'uid': user.uid,
        'email': user.email ?? '',
        'username': cleanUsername,
        'usernameLower': cleanUsername.toLowerCase(),
        'displayName': cleanDisplayName,
        'displayNameLower': cleanDisplayName.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _publicDoc(user.uid),
      _publicProfileData(
        uid: user.uid,
        username: cleanUsername,
        displayName: cleanDisplayName,
      ),
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> setUserRole({
    required String uid,
    required String role,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');

    final cleanRole = role.trim().toLowerCase();
    if (cleanRole != 'user' && cleanRole != 'dev') {
      throw ArgumentError('Role non autorise.');
    }

    await _doc(uid).set(
      <String, dynamic>{
        'role': cleanRole,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _publishProfile(UserProfile profile) async {
    await _publicDoc(profile.uid).set(
      _publicProfileData(
        uid: profile.uid,
        username: profile.username,
        displayName: profile.displayName,
      ),
      SetOptions(merge: true),
    );
  }

  UserProfile _fromSnapshot(User user, Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    final role = '${source['role'] ?? 'user'}'.trim().toLowerCase();
    return UserProfile(
      uid: user.uid,
      username: '${source['username'] ?? _defaultUsername(user)}',
      displayName: '${source['displayName'] ?? user.displayName ?? ''}',
      email: '${source['email'] ?? user.email ?? ''}',
      role: _bootstrapAdminUids.contains(user.uid) ? 'admin' : role,
    );
  }

  Future<void> _syncBootstrapRoleIfNeeded(
    String uid,
    Map<String, dynamic>? data,
  ) async {
    if (!_bootstrapAdminUids.contains(uid)) return;
    if ('${data?['role'] ?? ''}'.trim().toLowerCase() == 'admin') return;
    await _doc(uid).set(
      <String, dynamic>{
        'role': 'admin',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String _defaultUsername(User user) {
    final email = user.email ?? '';
    final local = email.split('@').first.trim();
    if (local.isNotEmpty) return local;
    return user.uid.substring(0, user.uid.length < 8 ? user.uid.length : 8);
  }

  Map<String, dynamic> _publicProfileData({
    required String uid,
    required String username,
    required String displayName,
  }) =>
      <String, dynamic>{
        'uid': uid,
        'username': username,
        'usernameLower': username.toLowerCase(),
        'displayName': displayName,
        'displayNameLower': displayName.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
