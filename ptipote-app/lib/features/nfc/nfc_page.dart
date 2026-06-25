import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lzstring/lzstring.dart';

import '../../services/figurine_service.dart';
import '../../services/nfc_service.dart';
import '../../services/user_profile_service.dart';
import '../figurines/figurines_page.dart';
import '../figurines/ptipote_image.dart';

class NfcPage extends StatefulWidget {
  const NfcPage({
    super.key,
    this.service,
    this.initialUid = '',
    this.initialPayload = '',
  });

  static const route = '/nfc';

  final NfcService? service;
  final String initialUid;
  final String initialPayload;

  @override
  State<NfcPage> createState() => _NfcPageState();
}

class _NfcPageState extends State<NfcPage> with SingleTickerProviderStateMixin {
  late final NfcService _service;
  late final FigurineService _figurineService;
  late final UserProfileService _profileService;

  bool _busy = false;
  bool _saving = false;
  bool _checkingFirebase = false;
  bool _alreadyRegistered = false;
  bool _firebaseLookupFailed = false;
  bool _statusIsError = false;
  bool _canSeeDiagnostics = false;
  bool _confirmingTransfer = false;
  bool _showStatusCard = true;
  bool _adoptedInSession = false;
  bool _showAdoptionSuccess = false;
  String _status = 'Prêt à scanner une puce PTIPOTE.';
  String _tagUid = '';
  String _rawSource = '';
  String _decodedText = '';
  String? _pendingNickname;
  NfcDiagnosticEvent? _diagnostic;
  PendingTransfer? _pendingTransfer;
  Map<String, String> _fields = _emptyFields();
  Timer? _statusTimer;
  late final AnimationController _adoptPulseController;

  @override
  void dispose() {
    _statusTimer?.cancel();
    _adoptPulseController.dispose();
    super.dispose();
  }

  void _setStatus(String status, {required bool isError}) {
    _statusTimer?.cancel();
    _statusIsError = isError;
    _status = status;
    _showStatusCard = true;
    if (!isError) {
      _statusTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _showStatusCard = false);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NfcManagerService();
    _figurineService = FigurineService();
    _profileService = UserProfileService();
    _adoptPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    if (widget.initialPayload.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialScan());
    }
  }

  Future<void> _loadInitialScan() async {
    setState(() {
      _statusIsError = false;
      _status = 'Décodage NDEF en cours...';
      _tagUid = widget.initialUid;
      _rawSource = widget.initialPayload;
    });
    try {
      await _processRawScan(
        raw: widget.initialPayload,
        uid: widget.initialUid,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _checkingFirebase = false;
        _statusIsError = true;
        _status = error.toString();
      });
    }
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
      _showStatusCard = true;
      _tagUid = '';
      _rawSource = '';
      _decodedText = '';
      _diagnostic = const NfcDiagnosticEvent(step: 'Démarrage scan');
      _checkingFirebase = false;
      _alreadyRegistered = false;
      _firebaseLookupFailed = false;
      _adoptedInSession = false;
      _showAdoptionSuccess = false;
      _pendingNickname = null;
      _pendingTransfer = null;
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
      await _processRawScan(raw: result.payload ?? '', uid: result.uid);
    } catch (error) {
      setState(() {
        _busy = false;
        _checkingFirebase = false;
        _statusIsError = true;
        _status = error.toString();
      });
    }
  }

  Future<void> _processRawScan(
      {required String raw, required String uid}) async {
    final cleanRaw = raw.trim();
    if (cleanRaw.isEmpty) {
      throw NfcServiceException('Aucune donnée trouvée sur la puce.');
    }

    final payload = _extractPayloadFromSource(cleanRaw);
    final decoded = _decodePayload(payload);
    final kv = _parseKv(decoded);
    if (kv.isEmpty) {
      throw NfcServiceException('Décodage OK mais format non reconnu.');
    }

    final normalizedFields = _normalizeFields(kv);
    setState(() {
      _statusIsError = false;
      _status = 'Décodage NDEF OK, recherche Firebase...';
      _showStatusCard = true;
      _busy = false;
      _tagUid = uid;
      _rawSource = cleanRaw;
      _decodedText = decoded;
      _checkingFirebase = true;
      _alreadyRegistered = false;
      _firebaseLookupFailed = false;
      _adoptedInSession = false;
      _showAdoptionSuccess = false;
      _pendingNickname = null;
      _fields = Map<String, String>.from(normalizedFields);
    });

    final warnings = <String>[];
    var alreadyRegistered = false;
    var firebaseLookupFailed = false;

    try {
      final publicKey = _figurineService.publicKeyFromSource(cleanRaw);
      final ownFigurine = await _withFirebaseTimeout(
            _figurineService.getMyFigurineByTagUid(uid),
          ) ??
          await _withFirebaseTimeout(
            _figurineService.getMyFigurineByPublicKey(publicKey),
          );
      final existing = ownFigurine ??
          await _withFirebaseTimeout(
            _figurineService.getPublicFigurine(
              rawSource: cleanRaw,
              tagUid: uid,
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
              .publishPublicFigurine(rawSource: cleanRaw, figurine: ownFigurine)
              .catchError((_) {}),
        );
      }
    } catch (error) {
      firebaseLookupFailed = true;
      warnings.add('surnom Firebase indisponible');
    }

    try {
      final profile = await _profileService
          .getOrCreateMyProfile()
          .timeout(const Duration(seconds: 6));
      normalizedFields['o'] = profile.ownerName;
      normalizedFields['on'] = profile.breederNumber;
      _canSeeDiagnostics = profile.canSeeDiagnostics;
      _pendingTransfer =
          await _figurineService.getIncomingTransferByTagUid(uid);
      final pending = _pendingTransfer;
      if (pending != null) {
        _mergeFigurineFields(normalizedFields, pending.fields);
        normalizedFields['te'] = '1';
      }
    } catch (error) {
      warnings.add('profil indisponible');
    }

    setState(() {
      _busy = false;
      _setStatus(
        _pendingTransfer == null
            ? (warnings.isEmpty
                ? 'Scan OK'
                : 'Scan OK (${warnings.join(', ')})')
            : 'Scan requis OK, transfert prêt à confirmer',
        isError: false,
      );
      _tagUid = uid;
      _rawSource = cleanRaw;
      _decodedText = decoded;
      _checkingFirebase = false;
      _alreadyRegistered = alreadyRegistered;
      _firebaseLookupFailed = firebaseLookupFailed;
      _fields = normalizedFields;
    });
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
    if (_adoptedInSession) {
      Navigator.of(context).pushNamed(FigurinesPage.route);
      return;
    }

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

    final pendingNickname = _pendingNickname;
    if (pendingNickname == null) {
      final nickname = await _askNickname();
      if (nickname == null) return;
      setState(() {
        _pendingNickname = nickname;
        _fields = Map<String, String>.from(_fields)..['s'] = nickname;
        _setStatus('Surnom prêt. Valide avec Bien adopter.', isError: false);
      });
      return;
    }

    setState(() {
      _saving = true;
      _statusIsError = false;
    });

    try {
      final profile = await _profileService.getOrCreateMyProfile();
      final fields = Map<String, String>.from(_fields);
      fields['o'] = profile.ownerName;
      fields['on'] = profile.breederNumber;
      fields['s'] = pendingNickname;

      await _figurineService.saveScannedFigurine(
        tagUid: _tagUid,
        nickname: pendingNickname,
        rawSource: _rawSource,
        decodedText: _decodedText,
        fields: fields,
        ownerProfile: profile,
      );
      setState(() {
        _saving = false;
        _statusIsError = false;
        _setStatus('Figurine enregistree dans ton compte.', isError: false);
        _alreadyRegistered = true;
        _adoptedInSession = true;
        _showAdoptionSuccess = true;
        _pendingNickname = null;
        _firebaseLookupFailed = false;
        _fields = fields;
      });
      Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _showAdoptionSuccess = false);
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
    return _rarityLabelText(value);
  }

  bool get _canSaveFigurine =>
      _decodedText.isNotEmpty &&
      !_saving &&
      !_checkingFirebase &&
      (!_alreadyRegistered || _adoptedInSession) &&
      !_firebaseLookupFailed;

  String get _saveButtonLabel {
    if (_showAdoptionSuccess) return 'Adoption réussie';
    if (_adoptedInSession) return 'Voir Mes PTIPOTES';
    if (_saving) return 'Enregistrement...';
    if (_checkingFirebase) return 'Vérification Firebase...';
    if (_alreadyRegistered) return 'Déjà adopté';
    if (_firebaseLookupFailed) return 'Vérification impossible';
    if (_pendingNickname != null) return 'Bien adopter';
    return 'Adopter';
  }

  IconData get _saveButtonIcon {
    if (_showAdoptionSuccess) return Icons.check_circle;
    if (_adoptedInSession) return Icons.inventory_2_outlined;
    if (_checkingFirebase) return Icons.sync;
    if (_alreadyRegistered) return Icons.check_circle;
    if (_firebaseLookupFailed) return Icons.cloud_off;
    return Icons.egg_alt_outlined;
  }

  Future<void> _confirmTransfer() async {
    final transfer = _pendingTransfer;
    if (transfer == null) return;
    setState(() => _confirmingTransfer = true);
    try {
      final profile = await _profileService.getOrCreateMyProfile();
      await _figurineService.confirmIncomingTransfer(
        transfer: transfer,
        newOwner: profile,
      );
      if (!mounted) return;
      setState(() {
        _confirmingTransfer = false;
        _pendingTransfer = null;
        _alreadyRegistered = true;
        _statusIsError = false;
        _showStatusCard = true;
        _status = 'Transfert confirmé. Ce PTIPOTE rejoint ton compte.';
      });
      await _showTransferConfirmedDialog();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _confirmingTransfer = false;
        _statusIsError = true;
        _showStatusCard = true;
        _status = error.toString();
      });
    }
  }

  Future<void> _showTransferConfirmedDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Row(
          children: <Widget>[
            const Expanded(child: Text('Transfert confirmé')),
            IconButton(
              tooltip: 'Fermer',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: const Text(
          'Ce PTIPOTE a bien été transféré. Il est maintenant sous votre responsabilité.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed(FigurinesPage.route);
            },
            child: const Text('Retourner à Mes PTIPOTES'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner un PTIPOTE')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_showStatusCard)
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
            const SizedBox(height: 10),
            _AdoptActionButton(
              enabled: _pendingTransfer == null &&
                  _canSaveFigurine &&
                  !_showAdoptionSuccess,
              saving: _saving,
              label: _saveButtonLabel,
              icon: _saveButtonIcon,
              stage: _adoptedInSession
                  ? (_showAdoptionSuccess
                      ? _AdoptButtonStage.success
                      : _AdoptButtonStage.done)
                  : _pendingNickname != null
                      ? _AdoptButtonStage.confirm
                      : _AdoptButtonStage.ready,
              animation: _adoptPulseController,
              onPressed: _saveFigurine,
            ),
          ],
          if (_decodedText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _PublicPtipoteCard(
              fields: _fields,
              rows: _rows(),
              accessories: _accessoryRows(),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _readAndDecodeTag,
            icon: const Icon(Icons.nfc),
            label: Text(_busy ? 'Scan en cours...' : 'Scanner une figurine'),
          ),
          if (_pendingTransfer != null) ...<Widget>[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _confirmingTransfer ? null : _confirmTransfer,
              icon: _confirmingTransfer
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.handshake_outlined),
              label: Text(
                _confirmingTransfer
                    ? 'Confirmation...'
                    : 'Confirmer le transfert',
              ),
            ),
          ],
          if (_diagnostic != null && _canSeeDiagnostics) ...<Widget>[
            const SizedBox(height: 12),
            _DiagnosticCard(event: _diagnostic!),
          ],
        ],
      ),
    );
  }
}

enum _AdoptButtonStage { ready, confirm, success, done }

class _AdoptActionButton extends StatelessWidget {
  const _AdoptActionButton({
    required this.enabled,
    required this.saving,
    required this.label,
    required this.icon,
    required this.stage,
    required this.animation,
    required this.onPressed,
  });

  final bool enabled;
  final bool saving;
  final String label;
  final IconData icon;
  final _AdoptButtonStage stage;
  final Animation<double> animation;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final baseColor = switch (stage) {
      _AdoptButtonStage.ready => const Color(0xFF8D8158),
      _AdoptButtonStage.confirm => const Color(0xFF3F8F59),
      _AdoptButtonStage.success => const Color(0xFF4E9B61),
      _AdoptButtonStage.done => const Color(0xFF8D8158),
    };
    final pulseColor = switch (stage) {
      _AdoptButtonStage.ready => const Color(0xFFFF8A3D),
      _AdoptButtonStage.confirm => const Color(0xFF68C17C),
      _AdoptButtonStage.success => baseColor,
      _AdoptButtonStage.done => baseColor,
    };

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final shouldPulse = enabled &&
            stage != _AdoptButtonStage.done &&
            stage != _AdoptButtonStage.success;
        final color = shouldPulse
            ? Color.lerp(baseColor, pulseColor, animation.value)!
            : baseColor;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: enabled
                ? <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.22),
                      blurRadius: shouldPulse ? 16 + animation.value * 8 : 14,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: enabled ? color : null,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(58),
            ),
            onPressed: enabled ? onPressed : null,
            icon: saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon),
            label: Text(label),
          ),
        );
      },
    );
  }
}

class _PublicPtipoteCard extends StatelessWidget {
  const _PublicPtipoteCard({
    required this.fields,
    required this.rows,
    required this.accessories,
  });

  final Map<String, String> fields;
  final List<_FieldRow> rows;
  final List<_FieldRow> accessories;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final xp = _xpValue(fields['x'] ?? '');
    final progress = (xp / 100).clamp(0.0, 1.0);
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
                  width: 196,
                  child: _ImageWithRarity(
                    fields: fields,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: rows
                        .where((row) =>
                            row.label == 'Espèce' ||
                            row.label == 'Type' ||
                            row.label == 'Surnom')
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
            _OrganicInfoCard(label: 'Éleveur', value: fields['o'] ?? ''),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Niveau',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _display(fields['l'] ?? ''),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 11,
                      backgroundColor: const Color(0xFFE8D9BD),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$xp / 100 XP',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
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
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
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
      width: 192,
      height: 192,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD2BD93), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Transform.scale(
        scale: 1.5,
        child: PtipoteImage(
          type: fields['t'] ?? '',
          species: fields['e'] ?? '',
          height: 192,
        ),
      ),
    );
  }
}

class _ImageWithRarity extends StatelessWidget {
  const _ImageWithRarity({required this.fields});

  final Map<String, String> fields;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        _RoundPtipoteImage(fields: fields),
        Positioned(
          left: 6,
          bottom: 6,
          child: _RarityBadge(
            value: fields['r'] ?? '',
          ),
        ),
      ],
    );
  }
}

class _RarityBadge extends StatelessWidget {
  const _RarityBadge({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final label = _rarityLabelText(value);
    final stars = _rarityStars(value);
    return Tooltip(
      message: label,
      triggerMode: TooltipTriggerMode.tap,
      decoration: BoxDecoration(
        color: const Color(0xFFC9A36D),
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
      ),
      child: Container(
        width: 58,
        height: 58,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: _rarityColorFor(value),
          border: Border.all(color: const Color(0xFFD2BD93), width: 2),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x3333281E),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: FittedBox(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(
              stars,
              (_) => const Icon(
                Icons.star_rounded,
                color: Color(0xFF8A6A22),
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrganicInfoCard extends StatelessWidget {
  const _OrganicInfoCard({
    required this.label,
    required this.value,
  });

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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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

Color _rarityColorFor(String? value) {
  switch (value?.trim()) {
    case '1':
      return const Color(0xFFE8E4DD);
    case '2':
      return const Color(0xFFD9ECFF);
    case '3':
      return const Color(0xFFE8D8FF);
    case '4':
      return const Color(0xFFFFE7A8);
    default:
      return const Color(0xFFFFFCF4);
  }
}

String _rarityLabelText(String value) {
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
      return value.trim().isEmpty ? '-' : value;
  }
}

int _rarityStars(String value) {
  final parsed = int.tryParse(value.trim()) ?? 0;
  if (parsed <= 0) return 1;
  if (parsed >= 4) return 5;
  return parsed;
}

String _display(String value, {String fallback = '—'}) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({required this.event});

  final NfcDiagnosticEvent event;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: const Text(
          '⚙️ Diagnostic NFC',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        children: _diagnosticRows(event)
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
    );
  }
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

class _FieldRow {
  _FieldRow(this.label, this.value);

  final String label;
  final String value;
}
