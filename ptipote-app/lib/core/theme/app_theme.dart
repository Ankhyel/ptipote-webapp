import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData get light {
    // Direction visuelle commune : un monde vivant, doux et minéral.
    // Les couleurs ne décrivent aucune règle de gameplay : elles permettent
    // simplement à Zone 0 et Élevage de parler le même langage visuel.
    const ink = Color(0xFF18342D);
    const moss = Color(0xFF4E7D57);
    const mineral = Color(0xFFC58D42);
    const surface = Color(0xFFFFFCF4);
    const background = Color(0xFFE8F0DE);
    const outline = Color(0xFFB9C9AA);

    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: moss,
        brightness: Brightness.light,
        surface: surface,
      ).copyWith(
        primary: moss,
        secondary: mineral,
        tertiary: const Color(0xFF5F9CA2),
        surfaceContainerHighest: const Color(0xFFF1F5E9),
        outline: outline,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: const Color(0x2818342D),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: moss,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: moss, width: 1.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF6F8EF),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: outline)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: moss, width: 2)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF1F5E9),
        selectedColor: const Color(0xFFD7E8CE),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: const BorderSide(color: outline)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFCBD9BE)),
      useMaterial3: true,
    );
  }

  static ThemeData get dark {
    const ink = Color(0xFF0E211D);
    const moss = Color(0xFF8ABF86);
    const mineral = Color(0xFFE1B362);
    const surface = Color(0xFF1D312A);
    const background = Color(0xFF12231E);
    const outline = Color(0xFF4D6B5B);

    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: moss,
        brightness: Brightness.dark,
        surface: surface,
      ).copyWith(
        primary: moss,
        secondary: mineral,
        tertiary: const Color(0xFF8FC5CF),
        surfaceContainerHighest: const Color(0xFF294238),
        outline: outline,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: const Color(0xAA000000),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: moss,
          foregroundColor: const Color(0xFF10251E),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: moss,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: moss, width: 1.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF294238),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: outline)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: moss, width: 2)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF294238),
        selectedColor: const Color(0xFF406B4A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: const BorderSide(color: outline)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF466554)),
      useMaterial3: true,
    );
  }
}
