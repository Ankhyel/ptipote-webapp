import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/chat/chats_page.dart';
import 'features/figurines/figurines_page.dart';
import 'features/friends/friends_page.dart';
import 'features/game/refuge_page.dart';
import 'features/game/lisiere_v2_simulation_page.dart';
import 'features/game/lisiere_v2_page.dart';
import 'features/game/zone0_v2_camp_page.dart';
import 'features/game/zone0_v2_onboarding_page.dart';
import 'features/game/worldcraft_dev_region_page.dart';
import 'features/nfc/nfc_page.dart';
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
          ChatsPage.route: (_) => const ChatsPage(),
          FigurinesPage.route: (_) => const FigurinesPage(),
          FriendsPage.route: (_) => const FriendsPage(),
          RefugePage.route: (_) => const RefugePage(),
          LisiereV2SimulationPage.route: (_) => const LisiereV2SimulationPage(),
          LisiereV2Page.route: (_) => const LisiereV2Page(),
          Zone0V2OnboardingPage.route: (_) => const Zone0V2OnboardingPage(),
          WorldcraftDevRegionPage.route: (_) => const WorldcraftDevRegionPage(),
          Zone0V2CampPage.route: (_) => const Zone0V2CampPage(),
          NfcPage.route: (_) => const NfcPage(),
          ProfilePage.route: (_) => const ProfilePage(),
        },
      ),
    );
  }
}
