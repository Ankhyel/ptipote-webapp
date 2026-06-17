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
  bool _statusIsError = false;
  String _status = 'Prêt à scanner une puce PTIPOTE.';
  String _tagUid = '';
  String _rawSource = '';
  String _decodedText = '';
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
      _fields = _emptyFields();
    });

    try {
      final result = await _service.readTag();
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
      final warnings = <String>[];

      try {
        final publicKey = _figurineService.publicKeyFromSource(raw);
        final existing = await _figurineService.getMyFigurineByTagUid(
              result.uid,
            ) ??
            await _figurineService.getMyFigurineByPublicKey(publicKey);
        final existingName = existing?.displayName.trim() ?? '';
        if (existingName.isNotEmpty) {
          normalizedFields['s'] = existingName;
        }
        if (existing != null) {
          await _figurineService.publishPublicFigurine(
            rawSource: raw,
            figurine: existing,
          );
        }
      } catch (error) {
        warnings.add('surnom Firebase indisponible');
      }

      try {
        final profile = await _profileService.getOrCreateMyProfile();
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
        _fields = normalizedFields;
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _statusIsError = true;
        _status = error.toString();
      });
    }
  }

  Future<void> _saveFigurine() async {
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
      _FieldRow('Espèce (e)', _fields['e'] ?? ''),
      _FieldRow('Type (t)', _fields['t'] ?? ''),
      _FieldRow('Surnom (s)', _fields['s'] ?? ''),
      _FieldRow('Rareté (r)', _fields['r'] ?? ''),
      _FieldRow('Batch (b)', _fields['b'] ?? ''),
      _FieldRow('Niveau (l)', _fields['l'] ?? ''),
      _FieldRow('XP (x)', _fields['x'] ?? ''),
      _FieldRow('Nom éleveur', _fields['o'] ?? ''),
      _FieldRow('Nom utilisateur', _fields['on'] ?? ''),
      _FieldRow('Transfert (te)', _fields['te'] ?? ''),
      _FieldRow('Transfert confirmé (ter)', _fields['ter'] ?? ''),
      _FieldRow('Accessoire 1 (a1)', _fields['a1'] ?? ''),
      _FieldRow('Accessoire 2 (a2)', _fields['a2'] ?? ''),
      _FieldRow('Accessoire 3 (a3)', _fields['a3'] ?? ''),
      _FieldRow('Accessoire 4 (a4)', _fields['a4'] ?? ''),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();

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
              onPressed: _saving ? null : _saveFigurine,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving
                  ? 'Enregistrement...'
                  : 'Enregistrer dans mon compte'),
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
            _SectionCard(
              title: 'Image PTIPOTE',
              child: PtipoteImage(
                  type: _fields['t'] ?? '', species: _fields['e'] ?? ''),
            ),
          ],
          if (_tagUid.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'UID de la puce',
              child: SelectableText(_tagUid),
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Champs PTIPOTE',
            child: Column(
              children: rows
                  .map(
                    (row) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            flex: 6,
                            child: Text(
                              row.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 7,
                            child: SelectableText(
                                row.value.isEmpty ? '—' : row.value),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
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
