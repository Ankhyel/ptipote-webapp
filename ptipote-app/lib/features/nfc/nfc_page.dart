import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lzstring/lzstring.dart';

import '../../services/figurine_service.dart';
import '../../services/nfc_service.dart';
import '../../services/user_profile_service.dart';
import '../figurines/ptipote_image.dart';

class NfcPage extends StatefulWidget {
  const NfcPage({super.key, this.service});

  static const route = '/nfc';

  final NfcService? service;

  @override
  State<NfcPage> createState() => _NfcPageState();
}

class _NfcPageState extends State<NfcPage> {
  late final NfcService _service;
  late final FigurineService _figurineService;
  late final UserProfileService _profileService;

  bool _busy = false;
  bool _saving = false;
  bool _checkingFirebase = false;
  bool _alreadyRegistered = false;
  bool _firebaseLookupFailed = false;
  bool _statusIsError = false;
  String _status = 'Prêt à scanner une puce PTIPOTE.';
  String _tagUid = '';
  String _rawSource = '';
  String _decodedText = '';
  NfcDiagnosticEvent? _diagnostic;
  Map<String, String> _fields = _emptyFields();

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NfcManagerService();
    _figurineService = FigurineService();
    _profileService = UserProfileService();
  }

  static Map<String, String> _emptyFields() {
    return <String, String>{
      'e': '',
      't': '',
      's': '',
      'r': '',
      'b': '',
      'l': '',
      'x': '',
      'o': '',
      'on': '',
      'te': '',
      'ter': '',
      'a1': '',
      'a2': '',
      'a3': '',
      'a4': '',
    };
  }

  Future<void> _readAndDecodeTag() async {
    setState(() {
      _busy = true;
      _statusIsError = false;
      _status = 'Lecture NFC en cours...';
      _tagUid = '';
      _rawSource = '';
      _decodedText = '';
      _diagnostic = const NfcDiagnosticEvent(step: 'Démarrage scan');
      _checkingFirebase = false;
      _alreadyRegistered = false;
      _firebaseLookupFailed = false;
      _fields = _emptyFields();
    });

    try {
      final result = await _service.readTag(
        onDiagnostic: (event) {
          if (!mounted) return;
          setState(() {
            _diagnostic = event;
            if (event.uid.isNotEmpty) {
              _tagUid = event.uid;
            }
            if (event.payload.isNotEmpty) {
              _rawSource = event.payload;
            }
            if (event.error.isNotEmpty) {
              _status = event.error;
              _statusIsError = true;
            } else {
              _status = event.step;
              _statusIsError = false;
            }
          });
        },
      );
      final raw = (result.payload ?? '').trim();
      if (raw.isEmpty) {
        throw NfcServiceException('Aucune donnée trouvée sur la puce.');
      }

      final payload = _extractPayloadFromSource(raw);
      final decoded = _decodePayload(payload);
      final kv = _parseKv(decoded);
      if (kv.isEmpty) {
        throw NfcServiceException('Décodage OK mais format non reconnu.');
      }

      final normalizedFields = _normalizeFields(kv);
      setState(() {
        _statusIsError = false;
        _status = 'Décodage NDEF OK, recherche Firebase...';
        _busy = false;
        _tagUid = result.uid;
        _rawSource = raw;
        _decodedText = decoded;
        _checkingFirebase = true;
        _alreadyRegistered = false;
        _firebaseLookupFailed = false;
        _fields = Map<String, String>.from(normalizedFields);
      });

      final warnings = <String>[];
      var alreadyRegistered = false;
      var firebaseLookupFailed = false;

      try {
        final publicKey = _figurineService.publicKeyFromSource(raw);
        final ownFigurine = await _withFirebaseTimeout(
              _figurineService.getMyFigurineByTagUid(result.uid),
            ) ??
            await _withFirebaseTimeout(
              _figurineService.getMyFigurineByPublicKey(publicKey),
            );
        final existing = ownFigurine ??
            await _withFirebaseTimeout(
              _figurineService.getPublicFigurine(
                rawSource: raw,
                tagUid: result.uid,
              ),
            );
        if (existing != null) {
          alreadyRegistered = true;
          _mergeFigurineFields(normalizedFields, existing.fields);
          final existingName = existing.displayName.trim();
          if (existingName.isNotEmpty && existingName != 'PTIPOTE sans nom') {
            normalizedFields['s'] = existingName;
          }
        }
        if (ownFigurine != null) {
          unawaited(
            _figurineService
                .publishPublicFigurine(
                  rawSource: raw,
                  figurine: ownFigurine,
                )
                .catchError((_) {}),
          );
        }
      } catch (error) {
        firebaseLookupFailed = true;
        warnings.add('surnom Firebase indisponible');
      }

      try {
        final profile = await _profileService.getOrCreateMyProfile().timeout(
              const Duration(seconds: 6),
            );
        normalizedFields['o'] = profile.ownerName;
        normalizedFields['on'] = profile.breederNumber;
      } catch (error) {
        warnings.add('profil indisponible');
      }

      setState(() {
        _busy = false;
        _statusIsError = false;
        _status =
            warnings.isEmpty ? 'Scan OK' : 'Scan OK (${warnings.join(', ')})';
        _tagUid = result.uid;
        _rawSource = raw;
        _decodedText = decoded;
        _checkingFirebase = false;
        _alreadyRegistered = alreadyRegistered;
        _firebaseLookupFailed = firebaseLookupFailed;
        _fields = normalizedFields;
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _checkingFirebase = false;
        _statusIsError = true;
        _status = error.toString();
      });
    }
  }

  Future<T?> _withFirebaseTimeout<T>(Future<T?> future) {
    return future.timeout(const Duration(seconds: 6), onTimeout: () => null);
  }

  void _mergeFigurineFields(
    Map<String, String> target,
    Map<String, String> source,
  ) {
    for (final key in <String>['s', 'o', 'on', 'l', 'x']) {
      final value = source[key]?.trim() ?? '';
      if (value.isNotEmpty && value != '-') {
        target[key] = value;
      }
    }
  }

  Future<void> _saveFigurine() async {
    if (_checkingFirebase) {
      setState(() {
        _statusIsError = true;
        _status = 'Attends la fin de la verification Firebase.';
      });
      return;
    }

    if (_alreadyRegistered) {
      setState(() {
        _statusIsError = false;
        _status = 'Ce PTIPOTE est deja enregistre.';
      });
      return;
    }

    if (_firebaseLookupFailed) {
      setState(() {
        _statusIsError = true;
        _status =
            'Verification Firebase impossible: enregistrement bloque pour eviter un doublon.';
      });
      return;
    }

    if (_tagUid.isEmpty ||
        _decodedText.isEmpty ||
        _fields.values.every((value) => value.trim().isEmpty)) {
      setState(() {
        _statusIsError = true;
        _status = 'Scanne une puce avant de l’enregistrer.';
      });
      return;
    }

    final nickname = await _askNickname();
    if (nickname == null) return;

    setState(() {
      _saving = true;
      _statusIsError = false;
    });

    try {
      final profile = await _profileService.getOrCreateMyProfile();
      final fields = Map<String, String>.from(_fields);
      fields['o'] = profile.ownerName;
      fields['on'] = profile.breederNumber;

      await _figurineService.saveScannedFigurine(
        tagUid: _tagUid,
        nickname: nickname,
        rawSource: _rawSource,
        decodedText: _decodedText,
        fields: fields,
        ownerProfile: profile,
      );
      setState(() {
        _saving = false;
        _statusIsError = false;
        _status = 'Figurine enregistree dans ton compte.';
        _alreadyRegistered = true;
        _firebaseLookupFailed = false;
      });
    } catch (error) {
      setState(() {
        _saving = false;
        _statusIsError = true;
        _status = error.toString();
      });
    }
  }

  Future<String?> _askNickname() async {
    final controller = TextEditingController(text: _fields['s'] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nommer ce PTIPOTE'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Surnom',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();

    final nickname = result?.trim();
    if (nickname == null) return null;
    if (nickname.isEmpty) {
      setState(() {
        _statusIsError = true;
        _status = 'Le surnom est requis pour lier la puce au compte.';
      });
      return null;
    }
    return nickname;
  }

  String _extractPayloadFromSource(String source) {
    final trimmed = source.trim();
    if (_looksLikeBase32(trimmed)) {
      return trimmed;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final fragment = uri.fragment.trim();
      if (fragment.isNotEmpty) return fragment;

      final pathLast =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last.trim() : '';
      if (_looksLikeBase32(pathLast)) return pathLast;
    }

    final hashIndex = trimmed.indexOf('#');
    if (hashIndex >= 0 && hashIndex + 1 < trimmed.length) {
      return trimmed.substring(hashIndex + 1).trim();
    }

    throw NfcServiceException('Payload Base32 introuvable dans la puce.');
  }

  bool _looksLikeBase32(String value) {
    final s = value.trim();
    if (s.length < 20) return false;
    return RegExp(r'^[A-Z2-7=]+$', caseSensitive: false).hasMatch(s);
  }

  String _decodePayload(String payload) {
    final bytes = _decodeBase32ToBytes(payload);
    return _decodeLz(bytes);
  }

  Uint8List _decodeBase32ToBytes(String b32) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    var s = b32
        .trim()
        .replaceFirst(RegExp(r'^#'), '')
        .replaceAll(RegExp(r'[\s-]+'), '')
        .toUpperCase();

    s = s.replaceAll('0', 'O').replaceAll('1', 'I');
    s = s.replaceAll(RegExp(r'=+$'), '');

    final bits = StringBuffer();
    for (final ch in s.split('')) {
      final value = alphabet.indexOf(ch);
      if (value < 0) {
        throw NfcServiceException("Base32 invalide: '$ch'");
      }
      bits.write(value.toRadixString(2).padLeft(5, '0'));
    }

    final bitString = bits.toString();
    final byteLen = bitString.length ~/ 8;
    final out = Uint8List(byteLen);
    for (var i = 0; i < byteLen; i++) {
      final byteBits = bitString.substring(i * 8, i * 8 + 8);
      out[i] = int.parse(byteBits, radix: 2);
    }
    return out;
  }

  String _decodeLz(Uint8List bytes) {
    final maxTrim = bytes.length < 24 ? bytes.length : 24;
    String? fallback;

    for (var trim = 0; trim <= maxTrim; trim++) {
      final arr = trim == 0 ? bytes : bytes.sublist(0, bytes.length - trim);
      final text = LZString.decompressFromUint8ArraySync(arr);
      final clean = (text ?? '').trim();

      if (clean.isNotEmpty && _looksLikeKv(clean)) {
        return clean;
      }
      if (fallback == null && clean.isNotEmpty) {
        fallback = clean;
      }
    }

    if (fallback != null) return fallback;
    throw NfcServiceException('Payload LZ invalide.');
  }

  bool _looksLikeKv(String text) {
    return RegExp(r'(^|;)\s*([a-z]{1,3}|a[1-4])\s*=').hasMatch(text.trim());
  }

  Map<String, String> _parseKv(String text) {
    final out = <String, String>{};
    final parts = text.split(';');
    for (final part in parts) {
      if (part.trim().isEmpty) continue;
      final idx = part.indexOf('=');
      if (idx < 0) continue;
      final key = part.substring(0, idx).trim();
      final value = part.substring(idx + 1).trim();
      if (key.isNotEmpty) out[key] = value;
    }
    return out;
  }

  Map<String, String> _normalizeFields(Map<String, String> input) {
    final fields = _emptyFields();
    for (final key in fields.keys) {
      fields[key] = (input[key] ?? '').trim();
    }

    if ((fields['l'] ?? '').isEmpty && (input['n'] ?? '').trim().isNotEmpty) {
      fields['l'] = input['n']!.trim();
    }
    if ((fields['te'] ?? '').isEmpty && (input['ta'] ?? '').trim().isNotEmpty) {
      fields['te'] = input['ta']!.trim();
    }
    return fields;
  }

  List<_FieldRow> _rows() {
    return <_FieldRow>[
      _FieldRow('Espèce', _fields['e'] ?? ''),
      _FieldRow('Type', _fields['t'] ?? ''),
      _FieldRow('Surnom', _fields['s'] ?? ''),
      _FieldRow('Rareté', _rarityLabel(_fields['r'] ?? '')),
      _FieldRow('Niveau', _fields['l'] ?? ''),
      _FieldRow('XP', _fields['x'] ?? ''),
      _FieldRow('Nom éleveur', _fields['o'] ?? ''),
    ];
  }

  List<_FieldRow> _accessoryRows() {
    return <_FieldRow>[
      _FieldRow('A1', _fields['a1'] ?? ''),
      _FieldRow('A2', _fields['a2'] ?? ''),
      _FieldRow('A3', _fields['a3'] ?? ''),
      _FieldRow('A4', _fields['a4'] ?? ''),
    ];
  }

  String _rarityLabel(String value) {
    switch (value.trim()) {
      case '1':
        return 'Commun';
      case '2':
        return 'Spéciale';
      case '3':
        return 'Rare';
      case '4':
        return 'Légendaire';
      default:
        return value;
    }
  }

  bool get _canSaveFigurine =>
      _decodedText.isNotEmpty &&
      !_saving &&
      !_checkingFirebase &&
      !_alreadyRegistered &&
      !_firebaseLookupFailed;

  String get _saveButtonLabel {
    if (_saving) return 'Enregistrement...';
    if (_checkingFirebase) return 'Vérification Firebase...';
    if (_alreadyRegistered) return 'Déjà enregistré';
    if (_firebaseLookupFailed) return 'Vérification impossible';
    return 'Enregistrer dans mon compte';
  }

  IconData get _saveButtonIcon {
    if (_checkingFirebase) return Icons.sync;
    if (_alreadyRegistered) return Icons.check_circle;
    if (_firebaseLookupFailed) return Icons.cloud_off;
    return Icons.save;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner un PTIPOTE')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FilledButton.icon(
            onPressed: _busy ? null : _readAndDecodeTag,
            icon: const Icon(Icons.nfc),
            label: Text(_busy ? 'Scan en cours...' : 'Scanner une puce'),
          ),
          if (_decodedText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _canSaveFigurine ? _saveFigurine : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_saveButtonIcon),
              label: Text(_saveButtonLabel),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _status,
                style: TextStyle(
                  color: _statusIsError
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (_decodedText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _PublicPtipoteCard(
              fields: _fields,
              rows: _rows(),
              accessories: _accessoryRows(),
              tagUid: _tagUid,
            ),
          ],
          if (_diagnostic != null) ...<Widget>[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Diagnostic NFC',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _diagnosticRows(_diagnostic!)
                    .map(
                      (row) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              flex: 4,
                              child: Text(
                                row.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 7,
                              child: SelectableText(
                                row.value.isEmpty ? '—' : row.value,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PublicPtipoteCard extends StatelessWidget {
  const _PublicPtipoteCard({
    required this.fields,
    required this.rows,
    required this.accessories,
    required this.tagUid,
  });

  final Map<String, String> fields;
  final List<_FieldRow> rows;
  final List<_FieldRow> accessories;
  final String tagUid;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final xp = _xpValue(fields['x'] ?? '');
    final hasAccessories =
        accessories.any((row) => row.value.trim().isNotEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 112,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _RoundPtipoteImage(fields: fields),
                      const SizedBox(height: 12),
                      _TinyInfo(label: 'Niveau', value: fields['l'] ?? ''),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (xp / 100).clamp(0.0, 1.0),
                          minHeight: 9,
                          backgroundColor: const Color(0xFFE8D9BD),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$xp / 100 XP',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _TinyInfo(label: 'Éleveur', value: fields['o'] ?? ''),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: rows
                        .where((row) =>
                            row.label == 'Espèce' ||
                            row.label == 'Type' ||
                            row.label == 'Surnom' ||
                            row.label == 'Rareté')
                        .map(
                          (row) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _OrganicInfoCard(
                              label: row.label,
                              value: row.value,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: colorScheme.primary.withValues(alpha: 0.08),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFE0CFAE)),
                ),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFE0CFAE)),
                ),
                backgroundColor: const Color(0xFFFFFCF4),
                collapsedBackgroundColor: const Color(0xFFFFFCF4),
                title: const Text(
                  'Accessoires',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: Text(
                  hasAccessories ? 'Voir' : 'Aucun',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: accessories
                    .map(
                      (row) => _AccessoryLine(
                        label: row.label,
                        value: row.value,
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                if (tagUid.trim().isNotEmpty)
                  Expanded(
                    child: Text(
                      'UID ${tagUid.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Text(
                  'Batch ${_display(fields['b'] ?? '')}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _xpValue(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }
}

class _RoundPtipoteImage extends StatelessWidget {
  const _RoundPtipoteImage({required this.fields});

  final Map<String, String> fields;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD2BD93), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: PtipoteImage(
        type: fields['t'] ?? '',
        species: fields['e'] ?? '',
        height: 96,
      ),
    );
  }
}

class _OrganicInfoCard extends StatelessWidget {
  const _OrganicInfoCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        border: Border.all(color: const Color(0xFFE0CFAE)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _display(value),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _TinyInfo extends StatelessWidget {
  const _TinyInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        Text(
          _display(value),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _AccessoryLine extends StatelessWidget {
  const _AccessoryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _display(value, fallback: 'Aucun'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

String _display(String value, {String fallback = '—'}) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

List<_FieldRow> _diagnosticRows(NfcDiagnosticEvent event) {
  return <_FieldRow>[
    _FieldRow('Étape', event.step),
    _FieldRow('UID', event.uid),
    _FieldRow('Technos', event.technologies.join(', ')),
    _FieldRow('Record', event.recordType),
    _FieldRow('Brut', event.payload),
    _FieldRow('Erreur', event.error),
  ];
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _FieldRow {
  _FieldRow(this.label, this.value);

  final String label;
  final String value;
}
