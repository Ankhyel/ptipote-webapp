import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme_controller.dart';
import '../../services/nfc_service.dart';
import '../figurines/figurines_page.dart';
import '../nfc/nfc_page.dart';
import '../profile/profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const route = '/';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            tooltip: 'Profil',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) async {
              if (value == 'profile') {
                Navigator.of(context).pushNamed(ProfilePage.route);
              }
              if (value == 'logout') {
                await GoogleSignIn.instance.signOut();
                await FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Profil'),
                ),
              ),
              PopupMenuItem(
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: Column(
            children: <Widget>[
              DecoratedBox(
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
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _ActionCard(
                      title: 'Mes PTIPOTES',
                      subtitle:
                          'Voir les figurines enregistrées dans ton compte',
                      onTap: () =>
                          Navigator.of(context).pushNamed(FigurinesPage.route),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
