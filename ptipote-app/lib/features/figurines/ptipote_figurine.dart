class PtipoteFigurine {
  const PtipoteFigurine({
    required this.id,
    required this.tagUid,
    required this.nickname,
    required this.publicKey,
    required this.rawSource,
    required this.sortOrder,
    required this.transferStatus,
    required this.transferFromName,
    required this.transferLockedUntil,
    required this.fields,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tagUid;
  final String nickname;
  final String publicKey;
  final String rawSource;
  final int sortOrder;
  final String transferStatus;
  final String transferFromName;
  final DateTime? transferLockedUntil;
  final Map<String, String> fields;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName {
    final savedNickname = nickname.trim();
    if (savedNickname.isNotEmpty) return savedNickname;

    final fieldNickname = fields['s']?.trim();
    if (fieldNickname != null && fieldNickname.isNotEmpty) return fieldNickname;

    final label = [species, type].where((value) => value != '-').join(' ');
    return label.isEmpty ? 'PTIPOTE sans nom' : label;
  }

  String get level =>
      fields['l']?.trim().isNotEmpty == true ? fields['l']!.trim() : '-';

  String get xp =>
      fields['x']?.trim().isNotEmpty == true ? fields['x']!.trim() : '-';

  String get species =>
      fields['e']?.trim().isNotEmpty == true ? fields['e']!.trim() : '-';

  String get type =>
      fields['t']?.trim().isNotEmpty == true ? fields['t']!.trim() : '-';

  String get ownerName =>
      fields['o']?.trim().isNotEmpty == true ? fields['o']!.trim() : '-';

  String get breederNumber =>
      fields['on']?.trim().isNotEmpty == true ? fields['on']!.trim() : '-';

  bool get transferRequested => fields['te']?.trim() == '1';

  bool get transferConfirmed => fields['ter']?.trim() == '1';

  bool get needsTransferScan => transferStatus == 'accepted';

  bool get canTransfer => !isTransferLocked && !needsTransferScan;

  String get lockMessage {
    if (needsTransferScan) {
      return 'Scan de la figurine requis pour valider le transfert';
    }
    if (transferRequested) return 'Demande en attente';
    if (transferConfirmed &&
        transferLockedUntil != null &&
        transferLockedUntil!.isAfter(DateTime.now())) {
      final remaining = transferLockedUntil!.difference(DateTime.now());
      final days = (remaining.inHours / 24).ceil().clamp(1, 7);
      return 'Temps de recharge de la carte J-$days';
    }
    return '';
  }

  bool get isTransferLocked {
    final until = transferLockedUntil;
    return needsTransferScan ||
        transferRequested ||
        (transferConfirmed && until != null && until.isAfter(DateTime.now()));
  }
}
