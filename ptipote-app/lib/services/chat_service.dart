import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'figurine_service.dart';
import 'notification_service.dart';
import 'user_profile_service.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String senderUid;
  final String text;
  final DateTime? createdAt;
}

class ChatService {
  ChatService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    NotificationService? notificationService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _notificationService = notificationService ?? NotificationService();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final NotificationService _notificationService;

  String chatIdFor(String a, String b) {
    final ids = <String>[a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  Stream<List<ChatMessage>> watchMessages(FriendProfile friend) {
    final user = _auth.currentUser;
    if (user == null) return Stream<List<ChatMessage>>.value(const []);
    final chatId = chatIdFor(user.uid, friend.uid);
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  Future<void> sendMessage({
    required FriendProfile friend,
    required UserProfile fromProfile,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final chatId = chatIdFor(user.uid, friend.uid);
    final chatRef = _firestore.collection('chats').doc(chatId);
    final messageRef = chatRef.collection('messages').doc();
    final now = FieldValue.serverTimestamp();
    final batch = _firestore.batch();

    batch.set(
      chatRef,
      <String, dynamic>{
        'participantUids': <String>[user.uid, friend.uid]..sort(),
        'participantNames': <String, dynamic>{
          user.uid: fromProfile.ownerName,
          friend.uid: friend.ownerName,
        },
        'lastMessage': cleanText,
        'lastMessageAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
    batch.set(messageRef, <String, dynamic>{
      'senderUid': user.uid,
      'senderName': fromProfile.ownerName,
      'text': cleanText,
      'createdAt': now,
    });
    await _notificationService.sendToUser(
      recipientUid: friend.uid,
      type: 'chat_message',
      title: 'Nouveau message',
      body: '${fromProfile.ownerName} t’a envoyé un message.',
      data: <String, dynamic>{
        'chatId': chatId,
        'fromUid': user.uid,
        'fromName': fromProfile.ownerName,
      },
      batch: batch,
    );
    await batch.commit();
  }

  ChatMessage _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ChatMessage(
      id: doc.id,
      senderUid: '${data['senderUid'] ?? ''}',
      text: '${data['text'] ?? ''}',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
