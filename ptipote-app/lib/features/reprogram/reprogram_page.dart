import 'package:flutter/material.dart';

class ReprogramPage extends StatelessWidget {
  const ReprogramPage({super.key});

  static const route = '/reprogram';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reprogrammer')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'TODO: formulaire de reprogrammation\n'
          '- niveau\n'
          '- xp\n'
          '- validation backend avant ecriture NFC',
        ),
      ),
    );
  }
}
