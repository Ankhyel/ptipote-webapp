import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> ptipoteThemeMode =
    ValueNotifier<ThemeMode>(ThemeMode.light);

void togglePtipoteTheme() {
  ptipoteThemeMode.value = ptipoteThemeMode.value == ThemeMode.dark
      ? ThemeMode.light
      : ThemeMode.dark;
}
