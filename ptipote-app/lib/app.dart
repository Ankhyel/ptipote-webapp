import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/figurines/figurines_page.dart';
import 'features/friends/friends_page.dart';
import 'features/nfc/nfc_page.dart';
import 'features/notifications/notifications_page.dart';
import 'features/profile/profile_page.dart';

class PtipoteApp extends StatelessWidget {
  const PtipoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ptipoteThemeMode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'PTIPOTE App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: const AuthGate(),
        routes: {
          FigurinesPage.route: (_) => const FigurinesPage(),
          FriendsPage.route: (_) => const FriendsPage(),
          NfcPage.route: (_) => const NfcPage(),
          NotificationsPage.route: (_) => NotificationsPage(),
          ProfilePage.route: (_) => const ProfilePage(),
        },
      ),
    );
  }
}
