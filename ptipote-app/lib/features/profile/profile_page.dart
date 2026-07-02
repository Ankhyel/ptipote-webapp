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
  final _roleUidController = TextEditingController();

  bool _loaded = false;
  bool _loading = true;
  bool _saving = false;
  bool _savingRole = false;
  String _selectedRole = 'dev';
  String? _status;
  UserProfile? _profile;

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
    _roleUidController.dispose();
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
        _profile = profile;
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
      setState(() {
        _profile = profile;
        _status = 'Profil et PTIPOTE synchronises.';
      });
    } catch (error) {
      setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveRole() async {
    final uid = _roleUidController.text.trim();
    if (uid.isEmpty) {
      setState(() => _status = 'UID utilisateur requis.');
      return;
    }

    setState(() {
      _savingRole = true;
      _status = null;
    });

    try {
      await _service.setUserRole(uid: uid, role: _selectedRole);
      setState(() => _status = 'Role $_selectedRole attribue.');
    } catch (error) {
      setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _savingRole = false);
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
                if (_profile?.isAdmin ?? false) ...<Widget>[
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Administration',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _roleUidController,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'UID utilisateur',
                              helperText: 'Attribue ou retire le role dev.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<String>(
                            segments: const <ButtonSegment<String>>[
                              ButtonSegment<String>(
                                value: 'dev',
                                icon: Icon(Icons.bug_report_outlined),
                                label: Text('Dev'),
                              ),
                              ButtonSegment<String>(
                                value: 'user',
                                icon: Icon(Icons.person_outline),
                                label: Text('Utilisateur'),
                              ),
                            ],
                            selected: <String>{_selectedRole},
                            onSelectionChanged: _savingRole
                                ? null
                                : (selection) {
                                    setState(() {
                                      _selectedRole = selection.first;
                                    });
                                  },
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _savingRole ? null : _saveRole,
                            icon: _savingRole
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.admin_panel_settings),
                            label: Text(
                              _savingRole
                                  ? 'Attribution...'
                                  : 'Enregistrer le role',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
