// CleanIT — Theme Configuration
//
// Premium dual-theme system: Catppuccin Mocha (dark) + Catppuccin Latte (light).
// Shared accent palette with per-theme surface and background colors.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Accent Colors (shared between themes) ──
  static const Color blue     = Color(0xFF89B4FA);
  static const Color green    = Color(0xFFA6E3A1);
  static const Color red      = Color(0xFFFF6B6B);
  static const Color peach    = Color(0xFFFAB387);
  static const Color yellow   = Color(0xFFF9E2AF);
  static const Color mauve    = Color(0xFFCBA6F7);
  static const Color teal     = Color(0xFF89DCEB);
  static const Color pink     = Color(0xFFF5C2E7);

  // ── Dark Keys (Catppuccin Mocha) ──
  static const Color crust    = Color(0xFF11111B);
  static const Color base     = Color(0xFF1E1E2E);
  static const Color mantle   = Color(0xFF181825);
  static const Color surface0 = Color(0xFF313244);
  static const Color surface1 = Color(0xFF45475A);
  static const Color overlay0 = Color(0xFF6C7086);
  static const Color subtext0 = Color(0xFFA6ADC8);
  static const Color text     = Color(0xFFCDD6F4);
  static const Color white    = Colors.white;

  // ── Light Keys (Catppuccin Latte) ──
  static const Color lCrust    = Color(0xFFDCE0E8);
  static const Color lBase     = Color(0xFFEFF1F5);
  static const Color lMantle   = Color(0xFFE6E9EF);
  static const Color lSurface0 = Color(0xFFCCD0DA);
  static const Color lSurface1 = Color(0xFFBCC0CC);
  static const Color lOverlay0 = Color(0xFF9CA0B0);
  static const Color lSubtext0 = Color(0xFF6C6F85);
  static const Color lText     = Color(0xFF4C4F69);
  static const Color lBlue     = Color(0xFF1E66F5);
  static const Color lGreen    = Color(0xFF40A02B);
  static const Color lRed      = Color(0xFFD20F39);
  static const Color lPeach    = Color(0xFFFE640B);
  static const Color lYellow   = Color(0xFFDF8E1D);

  // ── Dark Theme ──
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

  // ── Light Theme ──
  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: lCrust,
      colorScheme: ColorScheme.light(
        primary: lBlue,
        secondary: lGreen,
        error: lRed,
        surface: lBase,
        onSurface: lText,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lBase,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: lText,
        ),
        iconTheme: IconThemeData(color: lText),
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData.light().textTheme,
      ).apply(
        bodyColor: lText,
        displayColor: lText,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lBlue,
          foregroundColor: Colors.white,
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
        fillColor: lBase,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: lSurface0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: lSurface0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: lBlue, width: 2),
        ),
        hintStyle: TextStyle(color: lOverlay0),
        labelStyle: TextStyle(color: lSubtext0),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lBase,
        contentTextStyle: TextStyle(color: lText),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: lBase,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: lSurface0, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lSurface0,
        labelStyle: TextStyle(color: lText, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(color: lSurface0, thickness: 1),
    );
  }
}
