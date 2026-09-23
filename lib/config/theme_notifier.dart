// CleanIT — Theme Notifier
//
// Global ValueNotifier for theme mode, persisted via SharedPreferences.
// Loads the saved theme on startup and saves on every change.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global theme mode notifier — persists across app restarts.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

const _kThemeKey = 'cleanit_theme_mode';

/// Call once in [main] before [runApp] to restore the user's saved theme.
Future<void> loadSavedTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_kThemeKey);
  if (saved == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else {
    themeNotifier.value = ThemeMode.dark;
  }

  // Persist every future change automatically
  themeNotifier.addListener(() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kThemeKey,
      themeNotifier.value == ThemeMode.light ? 'light' : 'dark',
    );
  });
}
