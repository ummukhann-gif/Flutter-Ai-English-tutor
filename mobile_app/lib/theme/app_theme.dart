import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF4D8CFF);
  static const Color accentPink = Color(0xFFFF7AD1);
  static const Color accentYellow = Color(0xFFFFD166);
  static const Color backgroundWhite = Colors.white;
  static const Color surfaceGrey =
      Color(0xFFF2F4F8); // Slightly darker for better contrast
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);

  // Soft UI Shadows
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF94A3B8).withOpacity(0.15),
          offset: const Offset(4, 4),
          blurRadius: 20,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: Colors.white.withOpacity(0.8),
          offset: const Offset(-4, -4),
          blurRadius: 20,
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get strongShadow => [
        BoxShadow(
          color: const Color(0xFF94A3B8).withOpacity(0.2),
          offset: const Offset(8, 8),
          blurRadius: 24,
          spreadRadius: 0,
        ),
      ];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: surfaceGrey, // Grey background
      primaryColor: primaryBlue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentPink,
        tertiary: accentYellow,
        surface: backgroundWhite, // Cards are white
        background: surfaceGrey,
      ),
      textTheme: GoogleFonts.outfitTextTheme().copyWith(
        displayLarge: GoogleFonts.outfit(
            fontSize: 34, fontWeight: FontWeight.w800, color: textDark),
        displayMedium: GoogleFonts.outfit(
            fontSize: 30, fontWeight: FontWeight.w800, color: textDark),
        titleLarge: GoogleFonts.outfit(
            fontSize: 22, fontWeight: FontWeight.w700, color: textDark),
        titleMedium: GoogleFonts.outfit(
            fontSize: 18, fontWeight: FontWeight.w700, color: textDark),
        bodyLarge: GoogleFonts.outfit(fontSize: 16, color: textDark),
        bodyMedium: GoogleFonts.outfit(fontSize: 14, color: textGrey),
        labelLarge: GoogleFonts.outfit(
            fontSize: 14, fontWeight: FontWeight.w700, color: textDark),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceGrey,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: textDark,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26), // 26px radius
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: backgroundWhite,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26), // 26px radius
          side: BorderSide(
              color: Colors.white.withOpacity(0.5), width: 1), // Subtle border
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.all(22),
      ),
    );
  }
}
