import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/figurines/ptipote_figurine.dart';
import 'user_profile_service.dart';

class FigurineService {
  FigurineService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collectionFor(String uid) {
    return _firestore.collection('users').doc(uid).collection('figurines');
  }

  Stream<List<PtipoteFigurine>> watchMyFigurines() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<List<PtipoteFigurine>>.value(const <PtipoteFigurine>[]);
    }

    return _collectionFor(user.uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  Future<PtipoteFigurine?> getMyFigurineByTagUid(String tagUid) async {
    final user = _auth.currentUser;
    if (user == null || tagUid.trim().isEmpty) return null;

    final snapshot = await _collectionFor(user.uid).doc(_safeId(tagUid)).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    return _fromSnapshot(snapshot.id, snapshot.data()!);
  }

  Future<void> saveScannedFigurine({
    required String tagUid,
    required String nickname,
    required String rawSource,
    required String decodedText,
    required Map<String, String> fields,
    required UserProfile ownerProfile,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour enregistrer une figurine.');
    }

    final doc = _collectionFor(user.uid).doc(_safeId(tagUid));
    final now = FieldValue.serverTimestamp();
    final normalizedFields = Map<String, String>.from(fields);
    normalizedFields['s'] = nickname;
    normalizedFields['o'] = ownerProfile.ownerName;
    normalizedFields['on'] = ownerProfile.breederNumber;

    await doc.set(
      <String, dynamic>{
        'ownerUid': user.uid,
        'tagUid': tagUid,
        'species': fields['e'] ?? '',
        'type': fields['t'] ?? '',
        'nickname': nickname,
        'ownerName': ownerProfile.ownerName,
        'breederNumber': ownerProfile.breederNumber,
        'rawSource': rawSource,
        'decodedText': decodedText,
        'fields': normalizedFields,
        'updatedAt': now,
        'createdAt': now,
      },
      SetOptions(merge: true),
    );
  }

  String _safeId(String value) {
    final normalized =
        value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
    final trimmed = normalized.replaceAll(RegExp(r'^-+|-+$'), '');
    if (trimmed.isEmpty) {
      return DateTime.now().microsecondsSinceEpoch.toString();
    }
    return trimmed.length <= 120 ? trimmed : trimmed.substring(0, 120);
  }

  PtipoteFigurine _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    return _fromSnapshot(doc.id, doc.data());
  }

  PtipoteFigurine _fromSnapshot(String id, Map<String, dynamic> data) {
    final fieldsData =
        data['fields'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final fields = fieldsData.map((key, value) => MapEntry(key, '$value'));
    fields['o'] = '${data['ownerName'] ?? fields['o'] ?? ''}';
    fields['on'] = '${data['breederNumber'] ?? fields['on'] ?? ''}';

    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];

    return PtipoteFigurine(
      id: id,
      fields: fields,
      tagUid: data['tagUid'] as String? ?? id,
      nickname: '${data['nickname'] ?? fields['s'] ?? ''}',
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAt is Timestamp
          ? updatedAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
