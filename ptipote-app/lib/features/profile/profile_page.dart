import 'package:flutter/material.dart';

import '../../services/user_profile_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.service});

  static const route = '/profile';

  final UserProfileService? service;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final UserProfileService _service;
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _loaded = false;
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? UserProfileService();
    _load();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _service.getOrCreateMyProfile();
    if (!mounted) return;
    _usernameController.text = profile.username;
    _displayNameController.text = profile.displayName;
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();
    if (username.isEmpty) {
      setState(() => _status = 'Le nom utilisateur est requis.');
      return;
    }

    setState(() {
      _saving = true;
      _status = null;
    });

    try {
      await _service.saveMyProfile(
          username: username, displayName: displayName);
      setState(() => _status = 'Profil enregistre.');
    } catch (error) {
      setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Nom utilisateur',
                    helperText: 'Utilise comme numero eleveur public.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _displayNameController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Nom affiche',
                    helperText: 'Utilise comme nom de l’eleveur.',
                  ),
                ),
                if (_status != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(_status!,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
