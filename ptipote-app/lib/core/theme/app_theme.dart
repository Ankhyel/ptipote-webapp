import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData get light {
    const base = Color(0xFF0A0E18);
    const accent = Color(0xFF24C7B4);

    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: accent),
      scaffoldBackgroundColor: const Color(0xFFF3F6FF),
      appBarTheme: const AppBarTheme(
        backgroundColor: base,
        foregroundColor: Colors.white,
      ),
      useMaterial3: true,
    );
  }
}
