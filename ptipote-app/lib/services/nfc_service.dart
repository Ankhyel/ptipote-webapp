import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nfc_manager/nfc_manager.dart';

abstract class NfcService {
  Future<NfcTagReadResult> readTag({NfcDiagnosticCallback? onDiagnostic});
  Future<String?> readTagPayload();
  Future<void> writeTagPayload(String payload);
}

typedef NfcDiagnosticCallback = void Function(NfcDiagnosticEvent event);

class NfcDiagnosticEvent {
  const NfcDiagnosticEvent({
    required this.step,
    this.uid = '',
    this.payload = '',
    this.recordType = '',
    this.technologies = const <String>[],
    this.error = '',
  });

  final String step;
  final String uid;
  final String payload;
  final String recordType;
  final List<String> technologies;
  final String error;
}

class NfcTagReadResult {
  const NfcTagReadResult({
    required this.uid,
    required this.payload,
  });

  final String uid;
  final String? payload;
}

class NfcServiceException implements Exception {
  NfcServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NfcManagerService implements NfcService {
  NfcManagerService([NfcManager? manager])
      : _manager = manager ?? NfcManager.instance;

  final NfcManager _manager;
  static const List<String> _uriPrefixes = <String>[
    '',
    'http://www.',
    'https://www.',
    'http://',
    'https://',
    'tel:',
    'mailto:',
    'ftp://anonymous:anonymous@',
    'ftp://ftp.',
    'ftps://',
    'sftp://',
    'smb://',
    'nfs://',
    'ftp://',
    'dav://',
    'news:',
    'telnet://',
    'imap:',
    'rtsp://',
    'urn:',
    'pop:',
    'sip:',
    'sips:',
    'tftp:',
    'btspp://',
    'btl2cap://',
    'btgoep://',
    'tcpobex://',
    'irdaobex://',
    'file://',
    'urn:epc:id:',
    'urn:epc:tag:',
    'urn:epc:pat:',
    'urn:epc:raw:',
    'urn:epc:',
    'urn:nfc:',
  ];

  Future<void> _ensureAvailable() async {
    final available = await _manager.isAvailable();
    if (!available) {
      throw NfcServiceException('NFC indisponible sur cet appareil.');
    }
  }

  @override
  Future<NfcTagReadResult> readTag({
    NfcDiagnosticCallback? onDiagnostic,
  }) async {
    onDiagnostic?.call(
      const NfcDiagnosticEvent(step: 'Vérification disponibilité NFC'),
    );
    await _ensureAvailable();

    final completer = Completer<NfcTagReadResult>();
    onDiagnostic?.call(
      const NfcDiagnosticEvent(step: 'Session NFC ouverte'),
    );

    await _manager.startSession(
      alertMessage: 'Approche le haut de ton iPhone de la puce NFC PTIPOTE.',
      pollingOptions:
          Platform.isIOS ? <NfcPollingOption>{NfcPollingOption.iso14443} : null,
      onDiscovered: (NfcTag tag) async {
        try {
          final technologies = _tagTechnologies(tag);
          onDiagnostic?.call(
            NfcDiagnosticEvent(
              step: 'Puce détectée',
              uid: _extractUid(tag),
              technologies: technologies,
            ),
          );

          final ndef = Ndef.from(tag);
          if (ndef == null) {
            throw NfcServiceException('Tag NFC non-NDEF.');
          }
          onDiagnostic?.call(
            NfcDiagnosticEvent(
              step: 'Tag NDEF reconnu',
              uid: _extractUid(tag),
              technologies: technologies,
            ),
          );

          final message = ndef.cachedMessage ?? await ndef.read();
          if (message.records.isEmpty) {
            throw NfcServiceException('Aucune donnee NDEF sur ce tag.');
          }

          final record = message.records.first;
          final payload = _decodeRecord(record);
          final uid = _extractUid(tag);
          if (uid.isEmpty) {
            throw NfcServiceException('UID de puce introuvable.');
          }
          onDiagnostic?.call(
            NfcDiagnosticEvent(
              step: 'Record NDEF lu',
              uid: uid,
              payload: payload,
              recordType: _recordTypeLabel(record),
              technologies: technologies,
            ),
          );

          if (!completer.isCompleted) {
            completer.complete(NfcTagReadResult(uid: uid, payload: payload));
          }
          unawaited(_safeStopWithMessage('Lecture NFC terminee.'));
        } catch (error) {
          onDiagnostic?.call(
            NfcDiagnosticEvent(
              step: 'Erreur lecture NFC',
              error: _toReadableError(error).message,
            ),
          );
          await _safeStopWithError(error);
          if (!completer.isCompleted) {
            completer.completeError(_toReadableError(error));
          }
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () async {
        await _safeStopWithError(NfcServiceException('Timeout NFC.'));
        onDiagnostic?.call(
          const NfcDiagnosticEvent(
            step: 'Timeout NFC',
            error: 'Aucune puce détectée en 30 secondes.',
          ),
        );
        throw NfcServiceException('Aucun tag detecte (timeout).');
      },
    );
  }

  @override
  Future<String?> readTagPayload() async {
    final result = await readTag();
    return result.payload;
  }

  @override
  Future<void> writeTagPayload(String payload) async {
    await _ensureAvailable();

    final value = payload.trim();
    if (value.isEmpty) {
      throw NfcServiceException('Le payload a ecrire est vide.');
    }

    final message = NdefMessage([NdefRecord.createText(value)]);
    final completer = Completer<void>();

    await _manager.startSession(
      alertMessage: 'Approche le haut de ton iPhone de la puce NFC PTIPOTE.',
      pollingOptions:
          Platform.isIOS ? <NfcPollingOption>{NfcPollingOption.iso14443} : null,
      onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef != null) {
            if (!ndef.isWritable) {
              throw NfcServiceException('Tag non inscriptible.');
            }
            await ndef.write(message);
            await _manager.stopSession(alertMessage: 'Ecriture NFC terminee.');
            if (!completer.isCompleted) completer.complete();
            return;
          }

          throw NfcServiceException('Tag incompatible NDEF.');
        } catch (error) {
          await _safeStopWithError(error);
          if (!completer.isCompleted) {
            completer.completeError(_toReadableError(error));
          }
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () async {
        await _safeStopWithError(NfcServiceException('Timeout NFC.'));
        throw NfcServiceException('Aucun tag detecte pour ecriture (timeout).');
      },
    );
  }

  String _decodeRecord(NdefRecord record) {
    final payload = record.payload;
    if (payload.isEmpty) return '';

    final isUriRecord =
        record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
            _sameBytes(record.type, const [0x55]); // 'U'
    if (isUriRecord) {
      final prefixIndex = payload.first;
      final prefix =
          prefixIndex < _uriPrefixes.length ? _uriPrefixes[prefixIndex] : '';
      final suffix = utf8.decode(payload.sublist(1), allowMalformed: true);
      return '$prefix$suffix';
    }

    final isTextRecord =
        record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
            _sameBytes(record.type, const [0x54]); // 'T'

    if (isTextRecord && payload.length > 1) {
      final languageCodeLength = payload.first & 0x3F;
      final textStart = 1 + languageCodeLength;
      if (textStart < payload.length) {
        return utf8.decode(payload.sublist(textStart), allowMalformed: true);
      }
    }

    return utf8.decode(payload, allowMalformed: true);
  }

  String _extractUid(NfcTag tag) {
    final candidates = <Object?>[
      tag.data['mifare']?['identifier'],
      tag.data['nfcA']?['identifier'],
      tag.data['nfcB']?['identifier'],
      tag.data['iso7816']?['identifier'],
      tag.data['iso15693']?['identifier'],
      tag.data['felica']?['currentIDm'],
    ];

    for (final candidate in candidates) {
      final bytes = _asBytes(candidate);
      if (bytes.isNotEmpty) {
        return bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase();
      }
    }
    return '';
  }

  List<String> _tagTechnologies(NfcTag tag) {
    final names = tag.data.keys.where((key) {
      final value = tag.data[key];
      return value is Map && value.isNotEmpty;
    }).toList()
      ..sort();
    return names;
  }

  String _recordTypeLabel(NdefRecord record) {
    final type = utf8.decode(record.type, allowMalformed: true);
    final tnf = record.typeNameFormat.name;
    return type.isEmpty ? tnf : '$tnf / $type';
  }

  List<int> _asBytes(Object? value) {
    if (value is List<int>) return value;
    if (value is List) return value.whereType<int>().toList();
    return const <int>[];
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<void> _safeStopWithError(Object error) async {
    try {
      await _manager.stopSession(errorMessage: _toReadableError(error).message);
    } catch (_) {
      // Ignore session-stop failures.
    }
  }

  Future<void> _safeStopWithMessage(String message) async {
    try {
      await _manager.stopSession(alertMessage: message);
    } catch (_) {
      // Ignore session-stop failures.
    }
  }

  NfcServiceException _toReadableError(Object error) {
    if (error is NfcServiceException) return error;
    return NfcServiceException('Erreur NFC: $error');
  }
}
