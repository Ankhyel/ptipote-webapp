import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'figurine_service.dart';
import 'user_profile_service.dart';

class FriendInvite {
  const FriendInvite({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.fromUsername,
    required this.toUid,
    required this.toName,
    required this.toUsername,
    required this.status,
  });

  final String id;
  final String fromUid;
  final String fromName;
  final String fromUsername;
  final String toUid;
  final String toName;
  final String toUsername;
  final String status;
}

class FriendService {
  FriendService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<List<FriendProfile>> watchFriends() {
    final user = _auth.currentUser;
    if (user == null) return Stream<List<FriendProfile>>.value(const []);
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('friends')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_friendFromDoc).toList()
          ..sort((a, b) => a.ownerName.compareTo(b.ownerName)));
  }

  Stream<List<FriendInvite>> watchIncomingInvites() {
    final user = _auth.currentUser;
    if (user == null) return Stream<List<FriendInvite>>.value(const []);
    return _firestore
        .collection('friendInvites')
        .where('toUid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_inviteFromDoc).toList());
  }

  Stream<List<FriendInvite>> watchOutgoingInvites() {
    final user = _auth.currentUser;
    if (user == null) return Stream<List<FriendInvite>>.value(const []);
    return _firestore
        .collection('friendInvites')
        .where('fromUid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_inviteFromDoc).toList());
  }

  Future<List<FriendProfile>> searchUsers(String query) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const <FriendProfile>[];

    final byUsername = await _searchProfiles('usernameLower', needle);
    final byName = await _searchProfiles('displayNameLower', needle);

    final found = <String, FriendProfile>{};
    for (final doc in [...byUsername.docs, ...byName.docs]) {
      if (doc.id == user.uid) continue;
      found[doc.id] = _friendFromUserDoc(doc);
    }
    return found.values.toList()
      ..sort((a, b) => a.ownerName.compareTo(b.ownerName));
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _searchProfiles(
    String field,
    String value,
  ) async {
    final publicResults = await _firestore
        .collection('publicProfiles')
        .where(field, isEqualTo: value)
        .limit(8)
        .get(const GetOptions(source: Source.server));
    if (publicResults.docs.isNotEmpty) return publicResults;

    return _firestore
        .collection('users')
        .where(field, isEqualTo: value)
        .limit(8)
        .get(const GetOptions(source: Source.server));
  }

  Future<void> sendInvite({
    required UserProfile fromProfile,
    required FriendProfile to,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');
    final id = _inviteId(user.uid, to.uid);
    await _firestore.collection('friendInvites').doc(id).set(
      <String, dynamic>{
        'fromUid': user.uid,
        'fromName': fromProfile.ownerName,
        'fromUsername': fromProfile.username,
        'toUid': to.uid,
        'toName': to.ownerName,
        'toUsername': to.username,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> acceptInvite(FriendInvite invite, UserProfile myProfile) async {
    final user = _auth.currentUser;
    if (user == null || invite.toUid != user.uid) {
      throw StateError('Invitation indisponible.');
    }

    final batch = _firestore.batch();
    batch.set(
      _firestore.collection('friendInvites').doc(invite.id),
      <String, dynamic>{
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('friends')
          .doc(invite.fromUid),
      <String, dynamic>{
        'uid': invite.fromUid,
        'ownerName': invite.fromName,
        'username': '',
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _firestore
          .collection('users')
          .doc(invite.fromUid)
          .collection('friends')
          .doc(user.uid),
      <String, dynamic>{
        'uid': user.uid,
        'ownerName': myProfile.ownerName,
        'username': myProfile.username,
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> rejectInvite(FriendInvite invite) async {
    final user = _auth.currentUser;
    if (user == null || invite.toUid != user.uid) {
      throw StateError('Invitation indisponible.');
    }
    await _firestore.collection('friendInvites').doc(invite.id).set(
      <String, dynamic>{
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> cancelInvite(FriendInvite invite) async {
    final user = _auth.currentUser;
    if (user == null || invite.fromUid != user.uid) {
      throw StateError('Invitation indisponible.');
    }
    await _firestore.collection('friendInvites').doc(invite.id).set(
      <String, dynamic>{
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String _inviteId(String a, String b) {
    final ids = <String>[a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  FriendProfile _friendFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return FriendProfile(
      uid: '${data['uid'] ?? doc.id}',
      username: '${data['username'] ?? ''}',
      ownerName: '${data['ownerName'] ?? data['displayName'] ?? doc.id}',
    );
  }

  FriendProfile _friendFromUserDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return FriendProfile(
      uid: doc.id,
      username: '${data['username'] ?? ''}',
      ownerName:
          '${data['displayName'] ?? data['username'] ?? data['email'] ?? doc.id}',
    );
  }

  FriendInvite _inviteFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return FriendInvite(
      id: doc.id,
      fromUid: '${data['fromUid'] ?? ''}',
      fromName: '${data['fromName'] ?? ''}',
      fromUsername: '${data['fromUsername'] ?? ''}',
      toUid: '${data['toUid'] ?? ''}',
      toName: '${data['toName'] ?? ''}',
      toUsername: '${data['toUsername'] ?? ''}',
      status: '${data['status'] ?? ''}',
    );
  }
}
