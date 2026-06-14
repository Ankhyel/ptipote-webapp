import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../figurines/figurines_page.dart';
import '../nfc/nfc_page.dart';
import '../reprogram/reprogram_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const route = '/';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PTIPOTE App'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Deconnexion',
            onPressed: () async {
              await GoogleSignIn.instance.signOut();
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Collection',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _ActionCard(
            title: 'Mes PTIPOTE',
            subtitle: 'Voir les figurines enregistrees dans ton compte',
            onTap: () => Navigator.of(context).pushNamed(FigurinesPage.route),
          ),
          const SizedBox(height: 24),
          const Text(
            'Outils NFC',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _ActionCard(
            title: 'Scanner une puce',
            subtitle: 'Lire et verifier les donnees stockees',
            onTap: () => Navigator.of(context).pushNamed(NfcPage.route),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            title: 'Reprogrammer une puce',
            subtitle: 'Modifier niveau, xp et metadonnees',
            onTap: () => Navigator.of(context).pushNamed(ReprogramPage.route),
          ),
        ],
      ),
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
