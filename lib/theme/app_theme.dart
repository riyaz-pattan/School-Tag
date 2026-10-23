import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';

class AppTheme {
  // Brand Colors
  static const Color primary = Color(0xFF00113A);
  static const Color primaryContainer = Color(0xFF002366);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF758DD5);

  static const Color secondary = Color(0xFF006D36);
  static const Color secondaryContainer = Color(0xFF83FBA5);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF00743A);

  static const Color tertiary = Color(0xFF001717);
  static const Color onTertiaryContainer = Color(0xFF399E9D);

  static const Color error = Color(0xFFBA1A1A);
  
  // Surface Colors
  static const Color surface = Color(0xFFF4FAFF);
  static const Color surfaceDim = Color(0xFFC0DFEE);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFE6F6FF);
  static const Color surfaceContainer = Color(0xFFD9F2FF);
  static const Color surfaceContainerHigh = Color(0xFFCEEDFD);
  static const Color surfaceContainerHighest = Color(0xFFC9E7F7);

  static const Color onSurface = Color(0xFF001F2A);
  static const Color onSurfaceVariant = Color(0xFF444650);
  static const Color outline = Color(0xFF757682);
  static const Color outlineVariant = Color(0xFFC5C6D2);

  // Gradients
  static const LinearGradient signatureGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      primary,
      onTertiaryContainer,
    ],
  );

  // Box Shadows
  static List<BoxShadow> get ambientShadow => [
    BoxShadow(
      color: const Color(0xFF001F2A).withOpacity(0.08),
      blurRadius: 40,
      offset: const Offset(0, 12),
      spreadRadius: -12,
    )
  ];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
      ),
      scaffoldBackgroundColor: surface,
      textTheme: TextTheme(
        displayLarge: GoogleFonts.manrope(fontSize: 57, fontWeight: FontWeight.w200, color: onSurface),
        displayMedium: GoogleFonts.manrope(fontSize: 45, fontWeight: FontWeight.w300, color: onSurface),
        displaySmall: GoogleFonts.manrope(fontSize: 36, fontWeight: FontWeight.w400, color: onSurface),
        headlineLarge: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w400, color: onSurface),
        headlineMedium: GoogleFonts.manrope(fontSize: 28, fontWeight: FontWeight.w500, color: onSurface),
        headlineSmall: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w600, color: onSurface),
        titleLarge: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w600, color: onSurface),
        titleMedium: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: onSurface),
        titleSmall: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: onSurface),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: onSurface),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: onSurface),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: onSurface),
        labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
        labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: onSurface),
        labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: onSurface),
      ),
    );
  }
}
