import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
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
      initialRoute: HomePage.route,
      routes: {
        HomePage.route: (_) => const HomePage(),
        NfcPage.route: (_) => const NfcPage(),
        ReprogramPage.route: (_) => const ReprogramPage(),
      },
    );
  }
}
