import 'package:flutter/material.dart';

/// Le langage visuel commun de PTIPOTE.
///
/// Il garde les surfaces très sombres de l'Alcôve, les accents minéraux dorés
/// et une typographie éditoriale pour les écrans de jeu. Les règles de jeu ne
/// vivent pas ici : cette couche ne définit que leur présentation.
abstract final class AppTheme {
  static ThemeData get light => _forestTheme();

  // Le prototype utilise volontairement le même monde visuel dans les deux
  // modes. Le choix système ne doit pas transformer l'Alcôve en interface
  // blanche et casser l'atmosphère de jeu.
  static ThemeData get dark => _forestTheme();

  static ThemeData _forestTheme() {
    const canvas = Color(0xFF111C18);
    const surface = Color(0xFF213129);
    const surfaceRaised = Color(0xFF2B3E34);
    const cream = Color(0xFFF7F2E7);
    const mutedCream = Color(0xFFC8CFC3);
    const gold = Color(0xFFE7C67F);
    const outline = Color(0xFF6B7868);
    const accent = Color(0xFFEFD298);

    final scheme = ColorScheme.fromSeed(
      seedColor: gold,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(
      primary: accent,
      onPrimary: canvas,
      secondary: gold,
      onSecondary: canvas,
      tertiary: const Color(0xFF90B6A0),
      onTertiary: canvas,
      surface: surface,
      onSurface: cream,
      surfaceContainerHighest: surfaceRaised,
      outline: outline,
      error: const Color(0xFFFFB5A7),
      onError: const Color(0xFF4A130D),
    );

    const body = TextStyle(
      fontFamily: 'Avenir Next',
      fontFamilyFallback: <String>['Helvetica Neue', 'Arial', 'sans-serif'],
      color: cream,
      fontSize: 16,
      height: 1.35,
    );
    const display = TextStyle(
      fontFamily: 'Georgia',
      fontFamilyFallback: <String>['Times New Roman', 'serif'],
      color: cream,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.6,
      height: .96,
    );

    return ThemeData(
      colorScheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: canvas,
      textTheme: TextTheme(
        displayLarge: display.copyWith(fontSize: 64),
        displayMedium: display.copyWith(fontSize: 50),
        displaySmall: display.copyWith(fontSize: 40),
        headlineLarge: display.copyWith(fontSize: 34),
        headlineMedium: display.copyWith(fontSize: 30),
        headlineSmall: display.copyWith(fontSize: 26),
        titleLarge: display.copyWith(fontSize: 25, letterSpacing: -.55),
        titleMedium: body.copyWith(fontSize: 17, fontWeight: FontWeight.w800),
        titleSmall: body.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
        bodyLarge: body,
        bodyMedium: body.copyWith(color: mutedCream, fontSize: 15),
        bodySmall: body.copyWith(color: mutedCream, fontSize: 13),
        labelLarge: body.copyWith(
          color: canvas,
          fontWeight: FontWeight.w900,
          letterSpacing: .1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: cream,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle:
            body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: .22),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: canvas,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: body.copyWith(fontSize: 15, fontWeight: FontWeight.w900),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cream,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: body.copyWith(fontSize: 15, fontWeight: FontWeight.w900),
          side: const BorderSide(color: outline, width: 1.2),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gold,
          textStyle: body.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      iconTheme: const IconThemeData(color: cream),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        hintStyle: body.copyWith(color: mutedCream),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: gold, width: 1.8),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceRaised,
        selectedColor: const Color(0xFF41594B),
        labelStyle: body.copyWith(fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: outline),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF536557)),
      useMaterial3: true,
    );
  }
}
