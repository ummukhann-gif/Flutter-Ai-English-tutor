import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF00B4D8);
  static const Color primaryDarkBlue = Color(0xFF0077B6);
  static const Color accentPink = Color(0xFFFF006E);
  static const Color accentYellow = Color(0xFFFFD60A);
  static const Color backgroundWhite = Colors.white;
  static const Color surfaceGrey = Color(0xFFF8F9FA);
  static const Color textDark = Color(0xFF1A1A1A);
  static const Color textGrey = Color(0xFF8E8E8E);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: backgroundWhite,
      primaryColor: primaryBlue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentPink,
        tertiary: accentYellow,
        surface: surfaceGrey,
        // background is deprecated, using surface instead
      ),
      textTheme: GoogleFonts.outfitTextTheme().copyWith(
        displayLarge: GoogleFonts.outfit(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        displayMedium: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        bodyLarge: GoogleFonts.outfit(
          fontSize: 16,
          color: textDark,
        ),
        bodyMedium: GoogleFonts.outfit(
          fontSize: 14,
          color: textDark,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      // cardTheme: CardTheme(
      //   color: Colors.white,
      //   elevation: 0,
      //   shape: RoundedRectangleBorder(
      //     borderRadius: BorderRadius.circular(24),
      //     side: BorderSide(color: Colors.grey.shade100, width: 1),
      //   ),
      //   margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      // ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceGrey,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.all(20),
      ),
    );
  }
}
