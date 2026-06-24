import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme_controller.dart';
import '../../services/notification_service.dart';
import '../../services/nfc_service.dart';
import '../chat/chats_page.dart';
import '../figurines/figurines_page.dart';
import '../friends/friends_page.dart';
import '../nfc/nfc_page.dart';
import '../profile/profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const route = '/';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _notificationService = NotificationService();
  bool _scanning = false;

  Future<void> _scanFigurine() async {
    if (_scanning) return;

    setState(() => _scanning = true);
    var dialogOpen = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        dialogOpen = true;
        return const _ScanDialog();
      },
    );

    try {
      final result = await NfcManagerService().readTag();
      if (!mounted) return;
      if (dialogOpen) Navigator.of(context, rootNavigator: true).pop();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NfcPage(
            initialUid: result.uid,
            initialPayload: result.payload ?? '',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (dialogOpen) Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PTIPOTE App'),
        actions: <Widget>[
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ptipoteThemeMode,
            builder: (context, themeMode, _) => IconButton(
              tooltip: themeMode == ThemeMode.dark ? 'Mode clair' : 'Mode nuit',
              onPressed: togglePtipoteTheme,
              icon: Icon(
                themeMode == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
          ),
          const IconButton(
            tooltip: 'Boutique',
            onPressed: _openShop,
            icon: Icon(Icons.shopping_cart_outlined),
          ),
          IconButton(
            tooltip: 'Messages',
            onPressed: () => Navigator.of(context).pushNamed(ChatsPage.route),
            icon: StreamBuilder<int>(
              stream: _notificationService
                  .watchUnreadCountFor(<String>{'chat_message'}),
              builder: (context, snapshot) => _BadgedIcon(
                icon: Icons.chat_bubble_outline,
                count: snapshot.data ?? 0,
              ),
            ),
          ),
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            tooltip: 'Profil',
            icon: StreamBuilder<int>(
              stream: _notificationService
                  .watchUnreadCountFor(<String>{'friend_invite'}),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return _BadgedIcon(
                  icon: Icons.account_circle_outlined,
                  count: count,
                );
              },
            ),
            onSelected: (value) async {
              if (value == 'profile') {
                Navigator.of(context).pushNamed(ProfilePage.route);
              }
              if (value == 'friends') {
                Navigator.of(context).pushNamed(FriendsPage.route);
              }
              if (value == 'logout') {
                await GoogleSignIn.instance.signOut();
                await FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Profil'),
                ),
              ),
              PopupMenuItem(
                value: 'friends',
                child: StreamBuilder<int>(
                  stream: _notificationService
                      .watchUnreadCountFor(<String>{'friend_invite'}),
                  builder: (context, snapshot) => ListTile(
                    leading: _BadgedIcon(
                      icon: Icons.group_outlined,
                      count: snapshot.data ?? 0,
                    ),
                    title: const Text('Amis'),
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Déconnexion'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final unit = constraints.maxHeight / 5;
            return Stack(
              children: <Widget>[
                Positioned(
                  left: (constraints.maxWidth - 154) / 2,
                  top: unit * 2.12,
                  child: _CollectionButton(
                    onTap: () =>
                        Navigator.of(context).pushNamed(FigurinesPage.route),
                    countStream: _notificationService.watchUnreadCountFor(
                      <String>{
                        'transfer_request',
                        'transfer_confirmed',
                        'transfer_rejected',
                      },
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  top: unit * 4.02,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x5533281E),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7AFFEB),
                        foregroundColor: const Color(0xFF24342F),
                        minimumSize: const Size.fromHeight(64),
                      ),
                      onPressed: _scanning ? null : _scanFigurine,
                      icon: _scanning
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.egg_alt_outlined),
                      label: Text(
                        _scanning ? 'Scan en cours...' : 'Scan une figurine',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> _openShop() async {
  final uri = Uri.parse('https://shop.ptipotes.com');
  await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
}

class _ScanDialog extends StatelessWidget {
  const _ScanDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan NFC'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox.square(
            dimension: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 18),
          Text(
            'Approche la figurine du téléphone.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    );
  }
}

class _CollectionButton extends StatelessWidget {
  const _CollectionButton({required this.onTap, required this.countStream});

  final VoidCallback onTap;
  final Stream<int> countStream;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(34),
      onTap: onTap,
      child: Ink(
        width: 154,
        height: 154,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: const Color(0xFFE0CFAE)),
          borderRadius: BorderRadius.circular(34),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x3333281E),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.groups_2_outlined, size: 62),
                  SizedBox(height: 14),
                  Text(
                    'Mes ptipotes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: StreamBuilder<int>(
                stream: countStream,
                builder: (context, snapshot) =>
                    _Badge(count: snapshot.data ?? 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Icon(icon),
        Positioned(
          right: -5,
          top: -5,
          child: _Badge(count: count),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFE64A3C),
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
