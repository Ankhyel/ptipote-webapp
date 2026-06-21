import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PtipoteNotification {
  const PtipoteNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    required this.data,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final DateTime? createdAt;
  final Map<String, dynamic> data;
}

class NotificationService {
  NotificationService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String userId) =>
      _firestore.collection('users').doc(userId).collection('notifications');

  Stream<List<PtipoteNotification>> watchMyNotifications() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<List<PtipoteNotification>>.value(
        const <PtipoteNotification>[],
      );
    }
    return _collection(user.uid)
        .orderBy('createdAt', descending: true)
        .limit(40)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  Stream<int> watchUnreadCount() {
    return watchMyNotifications().map(
      (items) => items.where((item) => !item.read).length,
    );
  }

  Future<void> sendToUser({
    required String recipientUid,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic> data = const <String, dynamic>{},
    WriteBatch? batch,
  }) async {
    final ref = _collection(recipientUid).doc();
    final payload = <String, dynamic>{
      'recipientUid': recipientUid,
      'senderUid': _auth.currentUser?.uid ?? '',
      'type': type,
      'title': title,
      'body': body,
      'read': false,
      'data': data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final existingBatch = batch;
    if (existingBatch != null) {
      existingBatch.set(ref, payload);
      return;
    }
    await ref.set(payload);
  }

  Future<void> markAsRead(PtipoteNotification notification) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _collection(user.uid).doc(notification.id).set(
      <String, dynamic>{
        'read': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> markAllAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final unread = await _collection(user.uid)
        .where('read', isEqualTo: false)
        .limit(40)
        .get();
    if (unread.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.set(
        doc.reference,
        <String, dynamic>{
          'read': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  PtipoteNotification _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return PtipoteNotification(
      id: doc.id,
      type: '${data['type'] ?? ''}',
      title: '${data['title'] ?? ''}',
      body: '${data['body'] ?? ''}',
      read: data['read'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      data: Map<String, dynamic>.from(
        data['data'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }
}
