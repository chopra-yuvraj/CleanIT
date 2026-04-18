// CleanIT — Theme Notifier
//
// Global ValueNotifier for theme mode, allowing any screen to
// toggle between light and dark mode.

import 'package:flutter/material.dart';

/// Global theme mode notifier — persists in memory for the session.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);
