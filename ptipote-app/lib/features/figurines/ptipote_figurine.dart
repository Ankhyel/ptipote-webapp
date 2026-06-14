class PtipoteFigurine {
  const PtipoteFigurine({
    required this.id,
    required this.tagUid,
    required this.nickname,
    required this.fields,
    required this.rawSource,
    required this.decodedText,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tagUid;
  final String nickname;
  final Map<String, String> fields;
  final String rawSource;
  final String decodedText;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName {
    final savedNickname = nickname.trim();
    if (savedNickname.isNotEmpty) return savedNickname;

    final fieldNickname = fields['s']?.trim();
    if (fieldNickname != null && fieldNickname.isNotEmpty) return fieldNickname;

    final species = fields['e']?.trim();
    final type = fields['t']?.trim();
    final label = [species, type].where((value) => value != null && value.isNotEmpty).join(' ');
    return label.isEmpty ? 'PTIPOTE sans nom' : label;
  }

  String get level => fields['l']?.trim().isNotEmpty == true ? fields['l']!.trim() : '-';

  String get xp => fields['x']?.trim().isNotEmpty == true ? fields['x']!.trim() : '-';

  String get species => fields['e']?.trim().isNotEmpty == true ? fields['e']!.trim() : '-';

  String get type => fields['t']?.trim().isNotEmpty == true ? fields['t']!.trim() : '-';
}
