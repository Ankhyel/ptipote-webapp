import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/figurines/ptipote_figurine.dart';
import 'notification_service.dart';
import 'user_profile_service.dart';

class FigurineService {
  FigurineService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    NotificationService? notificationService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _notificationService = notificationService ?? NotificationService();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final NotificationService _notificationService;

  CollectionReference<Map<String, dynamic>> _collectionFor(String uid) {
    return _firestore.collection('users').doc(uid).collection('figurines');
  }

  Stream<List<PtipoteFigurine>> watchMyFigurines() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<List<PtipoteFigurine>>.value(const <PtipoteFigurine>[]);
    }

    return _collectionFor(user.uid).snapshots().map((snapshot) {
      final figurines = snapshot.docs.map(_fromDoc).toList();
      figurines.sort(_compareFigurines);
      return figurines;
    });
  }

  Stream<List<PendingTransfer>> watchIncomingTransfers() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<List<PendingTransfer>>.value(const <PendingTransfer>[]);
    }
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('incomingTransfers')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(PendingTransfer.fromDoc).toList());
  }

  Future<void> markTransferNotificationsAsRead() =>
      _notificationService.markTypesAsRead(
        <String>{'transfer_request', 'transfer_confirmed'},
      );

  Future<void> refreshMyFigurinesFromServer() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _collectionFor(user.uid).get(const GetOptions(source: Source.server));
  }

  Future<void> updateFigurineOrder(List<PtipoteFigurine> figurines) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour classer les figurines.');
    }

    final batch = _firestore.batch();
    for (var index = 0; index < figurines.length; index += 1) {
      batch.set(
        _collectionFor(user.uid).doc(figurines[index].id),
        <String, dynamic>{'sortOrder': index},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> renameMyFigurine({
    required PtipoteFigurine figurine,
    required String nickname,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour renommer une figurine.');
    }

    final cleanNickname = nickname.trim();
    if (cleanNickname.isEmpty) {
      throw ArgumentError('Le surnom ne peut pas etre vide.');
    }
    if (figurine.isTransferLocked) {
      throw StateError('Ce PTIPOTE est verrouille pendant le transfert.');
    }

    final fields = Map<String, String>.from(figurine.fields);
    fields['s'] = cleanNickname;
    final now = FieldValue.serverTimestamp();

    final batch = _firestore.batch();
    batch.set(
      _collectionFor(user.uid).doc(figurine.id),
      <String, dynamic>{
        'nickname': cleanNickname,
        'fields': fields,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    final publicKey = figurine.publicKey.trim().isNotEmpty
        ? figurine.publicKey.trim()
        : publicKeyFromSource(figurine.rawSource);
    if (publicKey.isNotEmpty) {
      batch.set(
        _firestore.collection('publicFigurines').doc(publicKey),
        <String, dynamic>{
          'ownerUid': user.uid,
          'tagUid': figurine.tagUid,
          'publicKey': publicKey,
          'species': figurine.species == '-' ? '' : figurine.species,
          'type': figurine.type == '-' ? '' : figurine.type,
          'nickname': cleanNickname,
          'ownerName': figurine.ownerName == '-' ? '' : figurine.ownerName,
          'breederNumber':
              figurine.breederNumber == '-' ? '' : figurine.breederNumber,
          'fields': fields,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<void> requestTransfer({
    required PtipoteFigurine figurine,
    required UserProfile fromProfile,
    required FriendProfile friend,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');
    if (figurine.isTransferLocked && figurine.transferConfirmed) {
      throw StateError(
          'Ce PTIPOTE vient d’être transfere et reste verrouille.');
    }

    final requestId = '${user.uid}_${figurine.id}_${friend.uid}';
    final now = FieldValue.serverTimestamp();
    final fields = Map<String, String>.from(figurine.fields);
    fields['te'] = '1';
    fields['ter'] = '0';

    final requestData = <String, dynamic>{
      'id': requestId,
      'figurineId': figurine.id,
      'tagUid': figurine.tagUid,
      'publicKey': figurine.publicKey,
      'fromUid': user.uid,
      'fromName': fromProfile.ownerName,
      'toUid': friend.uid,
      'toName': friend.ownerName,
      'status': 'pending',
      'fields': fields,
      'nickname': figurine.displayName,
      'species': figurine.species == '-' ? '' : figurine.species,
      'type': figurine.type == '-' ? '' : figurine.type,
      'requestedAt': now,
      'updatedAt': now,
    };

    final batch = _firestore.batch();
    batch.set(_firestore.collection('transferRequests').doc(requestId),
        requestData, SetOptions(merge: true));
    batch.set(
      _firestore
          .collection('users')
          .doc(friend.uid)
          .collection('incomingTransfers')
          .doc(figurine.id),
      requestData,
      SetOptions(merge: true),
    );
    batch.set(
      _collectionFor(user.uid).doc(figurine.id),
      <String, dynamic>{
        'fields': fields,
        'transfer': requestData,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
    await _writePublicTransferState(batch, figurine, fields,
        ownerUid: user.uid);
    await _notificationService.sendToUser(
      recipientUid: friend.uid,
      type: 'transfer_request',
      title: 'Demande de transfert',
      body:
          '${fromProfile.ownerName} veut te transférer ${figurine.displayName}.',
      data: <String, dynamic>{
        'transferId': requestId,
        'figurineId': figurine.id,
        'tagUid': figurine.tagUid,
        'fromUid': user.uid,
        'fromName': fromProfile.ownerName,
      },
      batch: batch,
    );
    await batch.commit();
  }

  Future<void> acceptTransferRequest(PendingTransfer transfer) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');

    final incomingRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('incomingTransfers')
        .doc(transfer.figurineId);
    final placeholderRef = _collectionFor(user.uid).doc(transfer.figurineId);
    final requestRef = _firestore.collection('transferRequests').doc(
          transfer.id,
        );
    final fields = Map<String, String>.from(transfer.fields);
    fields['te'] = '1';
    fields['ter'] = '0';

    final batch = _firestore.batch();
    batch.set(
      incomingRef,
      <String, dynamic>{
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      requestRef,
      <String, dynamic>{
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      placeholderRef,
      <String, dynamic>{
        'ownerUid': user.uid,
        'tagUid': transfer.tagUid,
        'publicKey': transfer.publicKey,
        'species': fields['e'] ?? transfer.species,
        'type': fields['t'] ?? transfer.type,
        'nickname': transfer.nickname,
        'ownerName': transfer.fromName,
        'fields': fields,
        'transfer': <String, dynamic>{
          'id': transfer.id,
          'status': 'accepted',
          'scanRequired': true,
          'fromUid': transfer.fromUid,
          'fromName': transfer.fromName,
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await _notificationService.sendToUser(
      recipientUid: transfer.fromUid,
      type: 'transfer_confirmed',
      title: 'Transfert accepté',
      body:
          'Le transfert de ${transfer.nickname.trim().isEmpty ? 'ton PTIPOTE' : transfer.nickname} a été accepté. Scan requis côté nouvel éleveur.',
      data: <String, dynamic>{
        'transferId': transfer.id,
        'figurineId': transfer.figurineId,
        'tagUid': transfer.tagUid,
        'toUid': user.uid,
      },
      batch: batch,
    );
    await batch.commit();
  }

  Future<void> rejectTransferRequest(PendingTransfer transfer) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');

    final fields = Map<String, String>.from(transfer.fields);
    fields['te'] = '0';

    final batch = _firestore.batch();
    batch.delete(_firestore
        .collection('users')
        .doc(user.uid)
        .collection('incomingTransfers')
        .doc(transfer.figurineId));
    batch.set(
      _firestore.collection('transferRequests').doc(transfer.id),
      <String, dynamic>{
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _collectionFor(transfer.fromUid).doc(transfer.figurineId),
      <String, dynamic>{
        'fields': fields,
        'transfer': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (transfer.publicKey.trim().isNotEmpty) {
      batch.set(
        _firestore.collection('publicFigurines').doc(transfer.publicKey),
        <String, dynamic>{
          'fields': fields,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> cancelTransfer(PtipoteFigurine figurine) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');

    final doc =
        await _getDocFromServer(_collectionFor(user.uid).doc(figurine.id));
    final transfer = doc.data()?['transfer'] as Map<String, dynamic>?;
    final toUid = '${transfer?['toUid'] ?? ''}'.trim();
    final requestId =
        '${transfer?['id'] ?? '${user.uid}_${figurine.id}_$toUid'}';
    final fields = Map<String, String>.from(figurine.fields);
    fields['te'] = '0';

    final batch = _firestore.batch();
    batch.set(
      _collectionFor(user.uid).doc(figurine.id),
      <String, dynamic>{
        'fields': fields,
        'transfer': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (requestId.trim().isNotEmpty) {
      batch.set(
        _firestore.collection('transferRequests').doc(requestId),
        <String, dynamic>{
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    if (toUid.isNotEmpty) {
      batch.delete(_firestore
          .collection('users')
          .doc(toUid)
          .collection('incomingTransfers')
          .doc(figurine.id));
    }
    await _writePublicTransferState(batch, figurine, fields,
        ownerUid: user.uid);
    await batch.commit();
  }

  Future<PendingTransfer?> getIncomingTransferByTagUid(String tagUid) async {
    final user = _auth.currentUser;
    if (user == null || tagUid.trim().isEmpty) return null;
    final snapshot = await _getQueryFromServer(
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('incomingTransfers')
          .where('tagUid', isEqualTo: tagUid)
          .limit(5),
    );
    if (snapshot.docs.isEmpty) return null;
    for (final doc in snapshot.docs) {
      final status = '${doc.data()['status'] ?? ''}';
      if (status == 'pending' || status == 'accepted') {
        return PendingTransfer.fromDoc(doc);
      }
    }
    return null;
  }

  Future<void> confirmIncomingTransfer({
    required PendingTransfer transfer,
    required UserProfile newOwner,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');

    final oldOwnerFigurine =
        _collectionFor(transfer.fromUid).doc(transfer.figurineId);
    final oldSnapshot = await _getDocFromServer(oldOwnerFigurine);
    final sourceData = oldSnapshot.data() ?? const <String, dynamic>{};
    final fieldsData =
        sourceData['fields'] as Map<String, dynamic>? ?? transfer.fields;
    final fields = fieldsData.map((key, value) => MapEntry(key, '$value'));
    fields['o'] = newOwner.ownerName;
    fields['on'] = newOwner.breederNumber;
    fields['te'] = '0';
    fields['ter'] = '1';
    final publicKey = '${sourceData['publicKey'] ?? transfer.publicKey}'.trim();
    final lockUntil = Timestamp.fromDate(
      DateTime.now().add(const Duration(days: 7)),
    );
    final now = FieldValue.serverTimestamp();
    final newDoc = _collectionFor(user.uid).doc(transfer.figurineId);

    final batch = _firestore.batch();
    batch.set(
      newDoc,
      <String, dynamic>{
        ...sourceData,
        'ownerUid': user.uid,
        'ownerName': newOwner.ownerName,
        'breederNumber': newOwner.breederNumber,
        'fields': fields,
        'transfer': FieldValue.delete(),
        'transferLockedUntil': lockUntil,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
    batch.delete(oldOwnerFigurine);
    batch.delete(newDoc.collection('transferMeta').doc('pending'));
    batch.delete(_firestore
        .collection('users')
        .doc(user.uid)
        .collection('incomingTransfers')
        .doc(transfer.figurineId));
    batch.set(
      _firestore.collection('transferRequests').doc(transfer.id),
      <String, dynamic>{
        'status': 'confirmed',
        'confirmedAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
    if (publicKey.isNotEmpty) {
      batch.set(
        _firestore.collection('publicFigurines').doc(publicKey),
        <String, dynamic>{
          'ownerUid': user.uid,
          'ownerName': newOwner.ownerName,
          'breederNumber': newOwner.breederNumber,
          'nickname': '${sourceData['nickname'] ?? fields['s'] ?? ''}',
          'fields': fields,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    }
    await _notificationService.sendToUser(
      recipientUid: transfer.fromUid,
      type: 'transfer_confirmed',
      title: 'Transfert confirmé',
      body: '${newOwner.ownerName} a confirmé le transfert du PTIPOTE.',
      data: <String, dynamic>{
        'transferId': transfer.id,
        'figurineId': transfer.figurineId,
        'tagUid': transfer.tagUid,
        'toUid': user.uid,
        'toName': newOwner.ownerName,
      },
      batch: batch,
    );
    await batch.commit();
  }

  Future<void> syncOwnerProfileOnMyFigurines(UserProfile profile) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour synchroniser les figurines.');
    }

    final snapshot = await _collectionFor(user.uid)
        .get(const GetOptions(source: Source.server));
    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final fieldsData =
          data['fields'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final fields = fieldsData.map((key, value) => MapEntry(key, '$value'));
      fields['o'] = profile.ownerName;
      fields['on'] = profile.breederNumber;

      batch.set(
        doc.reference,
        <String, dynamic>{
          'ownerName': profile.ownerName,
          'breederNumber': profile.breederNumber,
          'fields': fields,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final publicKey =
          '${data['publicKey'] ?? publicKeyFromSource('${data['rawSource'] ?? ''}')}'
              .trim();
      if (publicKey.isEmpty) continue;

      batch.set(
        _firestore.collection('publicFigurines').doc(publicKey),
        <String, dynamic>{
          'ownerUid': user.uid,
          'tagUid': '${data['tagUid'] ?? doc.id}',
          'publicKey': publicKey,
          'species': '${data['species'] ?? fields['e'] ?? ''}',
          'type': '${data['type'] ?? fields['t'] ?? ''}',
          'nickname': '${data['nickname'] ?? fields['s'] ?? ''}',
          'ownerName': profile.ownerName,
          'breederNumber': profile.breederNumber,
          'fields': fields,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<PtipoteFigurine?> getMyFigurineByTagUid(String tagUid) async {
    final user = _auth.currentUser;
    if (user == null || tagUid.trim().isEmpty) return null;

    final snapshot = await _getDocFromServer(
      _collectionFor(user.uid).doc(_safeId(tagUid)),
    );
    if (snapshot.exists && snapshot.data() != null) {
      return _fromSnapshot(snapshot.id, snapshot.data()!);
    }

    final byTagUid = await _getQueryFromServer(
      _collectionFor(user.uid).where('tagUid', isEqualTo: tagUid).limit(1),
    );
    if (byTagUid.docs.isNotEmpty) return _fromDoc(byTagUid.docs.first);

    final byLowerTagUid = await _getQueryFromServer(
      _collectionFor(user.uid)
          .where('tagUid', isEqualTo: tagUid.toLowerCase())
          .limit(1),
    );
    if (byLowerTagUid.docs.isEmpty) return null;
    return _fromDoc(byLowerTagUid.docs.first);
  }

  Future<PtipoteFigurine?> getMyFigurineByPublicKey(String publicKey) async {
    final user = _auth.currentUser;
    if (user == null || publicKey.trim().isEmpty) return null;
    final safePublicKey = _safeId(publicKey);

    final snapshot = await _getQueryFromServer(
      _collectionFor(user.uid)
          .where('publicKey', isEqualTo: safePublicKey)
          .limit(1),
    );
    if (snapshot.docs.isEmpty) return null;
    return _fromDoc(snapshot.docs.first);
  }

  Future<PtipoteFigurine?> getPublicFigurine({
    required String rawSource,
    required String tagUid,
  }) async {
    final publicKey = publicKeyFromSource(rawSource);

    if (publicKey.isNotEmpty) {
      final byPublicKey = await _getDocFromServer(
        _firestore.collection('publicFigurines').doc(publicKey),
      );
      if (byPublicKey.exists && byPublicKey.data() != null) {
        return _fromSnapshot(byPublicKey.id, byPublicKey.data()!);
      }
    }

    if (tagUid.trim().isEmpty) return null;
    final byUid = await _getQueryFromServer(
      _firestore
          .collection('publicFigurines')
          .where('tagUid', isEqualTo: tagUid)
          .limit(1),
    );
    if (byUid.docs.isEmpty) return null;
    return _fromDoc(byUid.docs.first);
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getDocFromServer(
    DocumentReference<Map<String, dynamic>> ref,
  ) =>
      ref.get(const GetOptions(source: Source.server));

  Future<QuerySnapshot<Map<String, dynamic>>> _getQueryFromServer(
    Query<Map<String, dynamic>> query,
  ) =>
      query.get(const GetOptions(source: Source.server));

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
    final publicKey = publicKeyFromSource(rawSource);
    final now = FieldValue.serverTimestamp();
    final normalizedFields = Map<String, String>.from(fields);
    normalizedFields['s'] = nickname;
    normalizedFields['o'] = ownerProfile.ownerName;
    normalizedFields['on'] = ownerProfile.breederNumber;

    await doc.set(
      <String, dynamic>{
        'ownerUid': user.uid,
        'tagUid': tagUid,
        'publicKey': publicKey,
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

    if (publicKey.isNotEmpty) {
      await _firestore.collection('publicFigurines').doc(publicKey).set(
        <String, dynamic>{
          'ownerUid': user.uid,
          'tagUid': tagUid,
          'publicKey': publicKey,
          'species': fields['e'] ?? '',
          'type': fields['t'] ?? '',
          'nickname': nickname,
          'ownerName': ownerProfile.ownerName,
          'breederNumber': ownerProfile.breederNumber,
          'fields': normalizedFields,
          'updatedAt': now,
          'createdAt': now,
        },
        SetOptions(merge: true),
      );
    }
  }

  Future<void> publishPublicFigurine({
    required String rawSource,
    required PtipoteFigurine figurine,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connexion requise pour publier une figurine.');
    }

    final publicKey = publicKeyFromSource(rawSource);
    if (publicKey.isEmpty) return;

    final fields = Map<String, String>.from(figurine.fields);
    fields['s'] = figurine.displayName;
    fields['o'] = figurine.ownerName == '-' ? '' : figurine.ownerName;
    fields['on'] = figurine.breederNumber == '-' ? '' : figurine.breederNumber;

    await _firestore.collection('publicFigurines').doc(publicKey).set(
      <String, dynamic>{
        'ownerUid': user.uid,
        'tagUid': figurine.tagUid,
        'publicKey': publicKey,
        'species': figurine.species == '-' ? '' : figurine.species,
        'type': figurine.type == '-' ? '' : figurine.type,
        'nickname': figurine.displayName,
        'ownerName': fields['o'] ?? '',
        'breederNumber': fields['on'] ?? '',
        'fields': fields,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String publicKeyFromSource(String source) {
    final token = _extractPublicToken(source);
    return token.isEmpty ? '' : _safeId(token);
  }

  String _extractPublicToken(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final fragment = uri.fragment.trim();
      if (fragment.isNotEmpty) return fragment;

      final pathLast =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last.trim() : '';
      if (pathLast.isNotEmpty) return pathLast;
    }

    final hashIndex = trimmed.indexOf('#');
    if (hashIndex >= 0 && hashIndex + 1 < trimmed.length) {
      return trimmed.substring(hashIndex + 1).trim();
    }

    return trimmed;
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
      publicKey: '${data['publicKey'] ?? ''}',
      rawSource: '${data['rawSource'] ?? ''}',
      sortOrder: _readSortOrder(data['sortOrder']),
      transferStatus: _readTransferStatus(data['transfer']),
      transferFromName: _readTransferFromName(data['transfer']),
      transferLockedUntil: data['transferLockedUntil'] is Timestamp
          ? (data['transferLockedUntil'] as Timestamp).toDate()
          : null,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAt is Timestamp
          ? updatedAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  int _compareFigurines(PtipoteFigurine a, PtipoteFigurine b) {
    if (a.sortOrder != b.sortOrder) return a.sortOrder.compareTo(b.sortOrder);
    return b.updatedAt.compareTo(a.updatedAt);
  }

  int _readSortOrder(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 1 << 30;
  }

  String _readTransferStatus(Object? value) {
    if (value is! Map) return '';
    return '${value['status'] ?? ''}';
  }

  String _readTransferFromName(Object? value) {
    if (value is! Map) return '';
    return '${value['fromName'] ?? ''}';
  }

  Future<void> _writePublicTransferState(
    WriteBatch batch,
    PtipoteFigurine figurine,
    Map<String, String> fields, {
    required String ownerUid,
  }) async {
    final publicKey = figurine.publicKey.trim().isNotEmpty
        ? figurine.publicKey.trim()
        : publicKeyFromSource(figurine.rawSource);
    if (publicKey.isEmpty) return;
    batch.set(
      _firestore.collection('publicFigurines').doc(publicKey),
      <String, dynamic>{
        'ownerUid': ownerUid,
        'fields': fields,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

class FriendProfile {
  const FriendProfile({
    required this.uid,
    required this.username,
    required this.ownerName,
  });

  final String uid;
  final String username;
  final String ownerName;
}

class PendingTransfer {
  const PendingTransfer({
    required this.id,
    required this.figurineId,
    required this.tagUid,
    required this.publicKey,
    required this.fromUid,
    required this.fromName,
    required this.nickname,
    required this.species,
    required this.type,
    required this.fields,
  });

  final String id;
  final String figurineId;
  final String tagUid;
  final String publicKey;
  final String fromUid;
  final String fromName;
  final String nickname;
  final String species;
  final String type;
  final Map<String, String> fields;

  static PendingTransfer fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final fieldsData =
        data['fields'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return PendingTransfer(
      id: '${data['id'] ?? doc.id}',
      figurineId: '${data['figurineId'] ?? doc.id}',
      tagUid: '${data['tagUid'] ?? ''}',
      publicKey: '${data['publicKey'] ?? ''}',
      fromUid: '${data['fromUid'] ?? ''}',
      fromName: '${data['fromName'] ?? ''}',
      nickname: '${data['nickname'] ?? fieldsData['s'] ?? ''}',
      species: '${data['species'] ?? fieldsData['e'] ?? ''}',
      type: '${data['type'] ?? fieldsData['t'] ?? ''}',
      fields: fieldsData.map((key, value) => MapEntry(key, '$value')),
    );
  }
}
