import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'figurine_service.dart';
import 'user_profile_service.dart';

class FriendInvite {
  const FriendInvite({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.toUid,
    required this.status,
  });

  final String id;
  final String fromUid;
  final String fromName;
  final String toUid;
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

  Future<List<FriendProfile>> searchUsers(String query) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const <FriendProfile>[];

    final byUsername = await _firestore
        .collection('users')
        .where('usernameLower', isEqualTo: needle)
        .limit(8)
        .get(const GetOptions(source: Source.server));
    final byName = await _firestore
        .collection('users')
        .where('displayNameLower', isEqualTo: needle)
        .limit(8)
        .get(const GetOptions(source: Source.server));

    final found = <String, FriendProfile>{};
    for (final doc in [...byUsername.docs, ...byName.docs]) {
      if (doc.id == user.uid) continue;
      found[doc.id] = _friendFromUserDoc(doc);
    }
    return found.values.toList()
      ..sort((a, b) => a.ownerName.compareTo(b.ownerName));
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
      toUid: '${data['toUid'] ?? ''}',
      status: '${data['status'] ?? ''}',
    );
  }
}
