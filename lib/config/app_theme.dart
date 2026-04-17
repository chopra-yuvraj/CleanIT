// CleanIT — Theme Configuration
//
// Catppuccin Mocha-inspired dark theme with premium aesthetics.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Core Palette (Catppuccin Mocha) ──
  static const Color crust    = Color(0xFF11111B);
  static const Color base     = Color(0xFF1E1E2E);
  static const Color mantle   = Color(0xFF181825);
  static const Color surface0 = Color(0xFF313244);
  static const Color surface1 = Color(0xFF45475A);
  static const Color overlay0 = Color(0xFF6C7086);
  static const Color subtext0 = Color(0xFFA6ADC8);
  static const Color text     = Color(0xFFCDD6F4);
  static const Color white    = Colors.white;

  // ── Accent Colors ──
  static const Color blue     = Color(0xFF89B4FA);
  static const Color green    = Color(0xFFA6E3A1);
  static const Color red      = Color(0xFFFF6B6B);
  static const Color peach    = Color(0xFFFAB387);
  static const Color yellow   = Color(0xFFF9E2AF);
  static const Color mauve    = Color(0xFFCBA6F7);
  static const Color teal     = Color(0xFF89DCEB);
  static const Color pink     = Color(0xFFF5C2E7);

  // ── Theme Data ──
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: crust,
      colorScheme: const ColorScheme.dark(
        primary: blue,
        secondary: green,
        error: red,
        surface: base,
        onSurface: text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: base,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: white,
        ),
        iconTheme: const IconThemeData(color: text),
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData.dark().textTheme,
      ).apply(
        bodyColor: text,
        displayColor: white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: crust,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: base,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: surface0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: surface0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: blue, width: 2),
        ),
        hintStyle: const TextStyle(color: overlay0),
        labelStyle: const TextStyle(color: subtext0),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: base,
        contentTextStyle: const TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: base,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: surface0, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface0,
        labelStyle: const TextStyle(color: text, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: const DividerThemeData(color: surface0, thickness: 1),
    );
  }
}
