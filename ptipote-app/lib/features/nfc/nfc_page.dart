import 'package:flutter/material.dart';

import '../../services/nfc_service.dart';

class NfcPage extends StatefulWidget {
  const NfcPage({super.key, this.service});

  static const route = '/nfc';

  final NfcService? service;

  @override
  State<NfcPage> createState() => _NfcPageState();
}

class _NfcPageState extends State<NfcPage> {
  late final NfcService _service;
  final TextEditingController _writeController = TextEditingController();

  bool _busy = false;
  bool _statusIsError = false;
  String _status = 'Pret. Pose une puce NFC pour lire ou ecrire.';
  String _lastRead = 'Aucune lecture pour le moment.';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NfcManagerService();
  }

  @override
  void dispose() {
    _writeController.dispose();
    super.dispose();
  }

  Future<void> _readTag() async {
    setState(() {
      _busy = true;
      _statusIsError = false;
      _status = 'Lecture NFC en cours...';
    });

    try {
      final payload = await _service.readTagPayload();
      setState(() {
        _busy = false;
        _statusIsError = false;
        _status = 'Lecture terminee.';
        _lastRead = (payload == null || payload.trim().isEmpty)
            ? '(Tag vide)'
            : payload;
        if (payload != null && payload.isNotEmpty) {
          _writeController.text = payload;
        }
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _statusIsError = true;
        _status = error.toString();
      });
    }
  }

  Future<void> _writeTag() async {
    final payload = _writeController.text.trim();
    if (payload.isEmpty) {
      setState(() {
        _statusIsError = true;
        _status = 'Le champ payload est vide.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _statusIsError = false;
      _status = 'Ecriture NFC en cours...';
    });

    try {
      await _service.writeTagPayload(payload);
      setState(() {
        _busy = false;
        _statusIsError = false;
        _status = 'Ecriture terminee.';
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _statusIsError = true;
        _status = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan / Ecriture NFC')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _status,
                    style: TextStyle(
                      color: _statusIsError ? Colors.red.shade700 : Colors.green.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _busy ? 'Action en cours, approche la puce du telephone.' : 'En attente.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dernier payload lu', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(_lastRead),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _readTag,
                    icon: const Icon(Icons.nfc),
                    label: const Text('Lire une puce'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Payload a ecrire', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _writeController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Ex: e=Geoda;t=Skadi;... ou Base32',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _writeTag,
                    icon: const Icon(Icons.edit),
                    label: const Text('Ecrire sur une puce'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
