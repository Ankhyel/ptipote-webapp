import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/figurines/figurines_page.dart';
import 'features/home/home_page.dart';
import 'features/nfc/nfc_page.dart';
import 'features/reprogram/reprogram_page.dart';

class PtipoteApp extends StatelessWidget {
  const PtipoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PTIPOTE App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
      routes: {
        HomePage.route: (_) => const HomePage(),
        FigurinesPage.route: (_) => const FigurinesPage(),
        NfcPage.route: (_) => const NfcPage(),
        ReprogramPage.route: (_) => const ReprogramPage(),
      },
    );
  }
}
