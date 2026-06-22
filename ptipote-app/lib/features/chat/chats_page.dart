import 'package:flutter/material.dart';

import '../../services/chat_service.dart';
import '../../services/figurine_service.dart';
import '../../services/friend_service.dart';
import '../../services/notification_service.dart';
import 'chat_page.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  static const route = '/chats';

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final _friendService = FriendService();
  final _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => _notificationService.markTypesAsRead(<String>{'chat_message'}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: StreamBuilder<List<FriendProfile>>(
        stream: _friendService.watchFriends(),
        builder: (context, snapshot) {
          final friends = snapshot.data ?? const <FriendProfile>[];
          if (friends.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ajoute un ami pour commencer une conversation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: friends.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final friend = friends[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFD9E1C3),
                    child: Text(
                      friend.ownerName.trim().isEmpty
                          ? '?'
                          : friend.ownerName.trim()[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  title: Text(
                    friend.ownerName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: friend.username.isEmpty
                      ? null
                      : Text('@${friend.username}'),
                  trailing: StreamBuilder<int>(
                    stream: ChatService().watchUnreadCountForFriend(friend.uid),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      if (count <= 0) return const Icon(Icons.chevron_right);
                      return _Badge(count: count);
                    },
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatPage(friend: friend),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
