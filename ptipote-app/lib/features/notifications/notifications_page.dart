import 'package:flutter/material.dart';

import '../../services/notification_service.dart';

class NotificationsPage extends StatelessWidget {
  NotificationsPage({super.key, NotificationService? service})
      : _service = service ?? NotificationService();

  static const route = '/notifications';

  final NotificationService _service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Tout marquer comme lu',
            onPressed: _service.markAllAsRead,
            icon: const Icon(Icons.done_all),
          ),
        ],
      ),
      body: StreamBuilder<List<PtipoteNotification>>(
        stream: _service.watchMyNotifications(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <PtipoteNotification>[];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune notification pour le moment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final notification = items[index];
              return Card(
                color: notification.read ? null : const Color(0xFFFFFCF4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: notification.read
                        ? const Color(0xFFE8D9BD)
                        : const Color(0xFFD9E1C3),
                    foregroundColor: const Color(0xFF33281E),
                    child: Icon(_iconFor(notification.type)),
                  ),
                  title: Text(
                    notification.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(notification.body),
                  trailing: notification.read
                      ? null
                      : const Icon(Icons.circle, size: 10),
                  onTap: () => _service.markAsRead(notification),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(String type) {
    return switch (type) {
      'friend_invite' => Icons.person_add_alt_1,
      'transfer_request' => Icons.ios_share,
      'transfer_confirmed' => Icons.handshake_outlined,
      'chat_message' => Icons.chat_bubble_outline,
      'event' => Icons.campaign_outlined,
      _ => Icons.notifications_none,
    };
  }
}
