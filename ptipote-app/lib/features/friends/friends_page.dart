import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/friend_service.dart';
import '../../services/figurine_service.dart';
import '../../services/user_profile_service.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  static const route = '/friends';

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _friendService = FriendService();
  final _profileService = UserProfileService();
  final _searchController = TextEditingController();
  List<FriendProfile> _results = const <FriendProfile>[];
  bool _searching = false;
  String? _status;
  Timer? _searchDebounce;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const <FriendProfile>[];
        _status = null;
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query),
    );
  }

  Future<void> _search([String? query]) async {
    final searchQuery = (query ?? _searchController.text).trim();
    if (searchQuery.isEmpty) {
      setState(() {
        _results = const <FriendProfile>[];
        _status = null;
        _searching = false;
      });
      return;
    }
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _status = null;
    });
    try {
      final results = await _friendService.searchUsers(searchQuery);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results.take(5).toList();
        _status = results.isEmpty ? 'Aucun éleveur trouvé.' : null;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _status = error.toString());
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _invite(FriendProfile friend) async {
    final profile = await _profileService.getOrCreateMyProfile();
    await _friendService.sendInvite(fromProfile: profile, to: friend);
    if (!mounted) return;
    _searchController.clear();
    setState(() {
      _results = const <FriendProfile>[];
      _status = 'Invitation envoyée à ${friend.ownerName}.';
    });
  }

  Future<void> _accept(FriendInvite invite) async {
    final profile = await _profileService.getOrCreateMyProfile();
    await _friendService.acceptInvite(invite, profile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Amis')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _IncomingInvites(
            friendService: _friendService,
            onAccept: _accept,
            onReject: _friendService.rejectInvite,
          ),
          StreamBuilder<List<FriendInvite>>(
            stream: _friendService.watchOutgoingInvites(),
            builder: (context, snapshot) {
              final invites = snapshot.data ?? const <FriendInvite>[];
              if (invites.isEmpty) return const SizedBox.shrink();
              return _SectionCard(
                title: 'Demandes envoyées',
                child: Column(
                  children: invites
                      .map(
                        (invite) => _InviteTile(
                          name: invite.toName,
                          username: invite.toUsername,
                          trailing: _SquareActionButton(
                            color: const Color(0xFFB84A3D),
                            icon: Icons.close,
                            onPressed: () =>
                                _friendService.cancelInvite(invite),
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Rechercher par pseudo',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _searchController.text.isEmpty
                    ? null
                    : () => _searchController.clear(),
                icon: _searching
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.close),
              ),
            ),
          ),
          if (_status != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_status!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final result = _results[index];
                  return _InviteTile(
                    name: result.ownerName,
                    username: result.username,
                    trailing: _SquareActionButton(
                      color: const Color(0xFF2E8B57),
                      icon: Icons.person_add_alt_1,
                      onPressed: () => _invite(result),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 18),
          _FriendsList(friendService: _friendService),
        ],
      ),
    );
  }
}

class _IncomingInvites extends StatelessWidget {
  const _IncomingInvites({
    required this.friendService,
    required this.onAccept,
    required this.onReject,
  });

  final FriendService friendService;
  final Future<void> Function(FriendInvite invite) onAccept;
  final Future<void> Function(FriendInvite invite) onReject;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendInvite>>(
      stream: friendService.watchIncomingInvites(),
      builder: (context, snapshot) {
        final invites = snapshot.data ?? const <FriendInvite>[];
        if (invites.isEmpty) return const SizedBox.shrink();
        return _SectionCard(
          title: 'Demandes reçues',
          child: Column(
            children: invites
                .map(
                  (invite) => _InviteTile(
                    name: invite.fromName,
                    username: invite.fromUsername,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _SquareActionButton(
                          color: const Color(0xFF2E8B57),
                          icon: Icons.check,
                          onPressed: () => onAccept(invite),
                        ),
                        const SizedBox(width: 8),
                        _SquareActionButton(
                          color: const Color(0xFFB84A3D),
                          icon: Icons.close,
                          onPressed: () => onReject(invite),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _FriendsList extends StatelessWidget {
  const _FriendsList({required this.friendService});

  final FriendService friendService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendProfile>>(
      stream: friendService.watchFriends(),
      builder: (context, snapshot) {
        final friends = snapshot.data ?? const <FriendProfile>[];
        return _SectionCard(
          title: 'Mes amis',
          child: friends.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucun ami pour le moment.'),
                )
              : Column(
                  children: friends
                      .map(
                        (friend) => _InviteTile(
                          name: friend.ownerName,
                          username: friend.username,
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.name,
    required this.username,
    required this.trailing,
  });

  final String name;
  final String username;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty ? username : name;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Avatar(name: displayName),
      title: Text(
        displayName.trim().isEmpty ? 'Éleveur' : displayName,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: username.trim().isEmpty ? null : Text('@$username'),
      trailing: trailing,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      backgroundColor: const Color(0xFFD9E1C3),
      foregroundColor: const Color(0xFF33281E),
      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _SquareActionButton extends StatelessWidget {
  const _SquareActionButton({
    required this.color,
    required this.icon,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 42,
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
