import 'package:flutter/material.dart';

import '../../services/figurine_service.dart';
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
  late final FigurineService _figurineService;
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _loaded = false;
  bool _loading = true;
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? UserProfileService();
    _figurineService = FigurineService();
    _load();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _status = null;
    });

    try {
      final profile = await _service.getOrCreateMyProfile();
      if (!mounted) return;
      _usernameController.text = profile.username;
      _displayNameController.text = profile.displayName;
      setState(() {
        _loaded = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loaded = false;
        _loading = false;
        _status = 'Chargement du profil impossible: $error';
      });
    }
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
      final profile = await _service.getOrCreateMyProfile();
      await _figurineService.syncOwnerProfileOnMyFigurines(profile);
      setState(() => _status = 'Profil et PTIPOTE synchronises.');
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
                    labelText: 'Identifiant ami',
                    helperText: 'Utilise pour la recherche et les invitations.',
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
          : _ProfileLoadState(
              loading: _loading,
              message: _status,
              onRetry: _load,
            ),
    );
  }
}

class _ProfileLoadState extends StatelessWidget {
  const _ProfileLoadState({
    required this.loading,
    required this.message,
    required this.onRetry,
  });

  final bool loading;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message ?? 'Chargement du profil impossible.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
