import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../figurines/figurines_page.dart';
import '../nfc/nfc_page.dart';
import '../profile/profile_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const route = '/';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PTIPOTE App'),
        actions: <Widget>[
          const IconButton(
            tooltip: 'Boutique',
            onPressed: _openShop,
            icon: Icon(Icons.shopping_cart_outlined),
          ),
          PopupMenuButton<String>(
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
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
            children: [
              _ActionCard(
                title: 'Mes PTIPOTES',
                subtitle: 'Voir les figurines enregistrées dans ton compte',
                onTap: () =>
                    Navigator.of(context).pushNamed(FigurinesPage.route),
              ),
            ],
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
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
                onPressed: () => Navigator.of(context).pushNamed(NfcPage.route),
                icon: const Icon(Icons.nfc),
                label: const Text(
                  'Scan une figurine',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openShop() async {
  final uri = Uri.parse('https://shop.ptipotes.com');
  await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
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
