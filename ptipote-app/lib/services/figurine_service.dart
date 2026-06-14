import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/figurines/ptipote_figurine.dart';

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

  Future<void> saveScannedFigurine({
    required String tagUid,
    required String nickname,
    required String rawSource,
    required String decodedText,
    required Map<String, String> fields,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour enregistrer une figurine.');
    }

    final doc = _collectionFor(user.uid).doc(_safeId(tagUid));
    final now = FieldValue.serverTimestamp();
    final normalizedFields = Map<String, String>.from(fields);
    normalizedFields['s'] = nickname;

    await doc.set(
      <String, dynamic>{
        'ownerUid': user.uid,
        'tagUid': tagUid,
        'species': fields['e'] ?? '',
        'type': fields['t'] ?? '',
        'nickname': nickname,
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
    final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
    final trimmed = normalized.replaceAll(RegExp(r'^-+|-+$'), '');
    if (trimmed.isEmpty) return DateTime.now().microsecondsSinceEpoch.toString();
    return trimmed.length <= 120 ? trimmed : trimmed.substring(0, 120);
  }

  PtipoteFigurine _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final fieldsData = data['fields'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];

    return PtipoteFigurine(
      id: doc.id,
      fields: fieldsData.map((key, value) => MapEntry(key, '$value')),
      tagUid: data['tagUid'] as String? ?? doc.id,
      nickname: "${data['nickname'] ?? fieldsData['s'] ?? ''}",
      rawSource: data['rawSource'] as String? ?? '',
      decodedText: data['decodedText'] as String? ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
