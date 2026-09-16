import 'package:flutter/material.dart';

/// Uygulamanın OLED siyahı / Neon fütüristik gizlilik teması.
class AppTheme {
  AppTheme._();

  // --- Renk Paleti ---
  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF13131A);
  static const Color surfaceElevated = Color(0xFF1C1C26);
  static const Color border = Color(0xFF2A2A3A);

  static const Color neonCyan = Color(0xFF00F5D4);
  static const Color neonPurple = Color(0xFF9B5DE5);
  static const Color neonBlue = Color(0xFF4CC9F0);
  static const Color neonGreen = Color(0xFF06D6A0);
  static const Color neonRed = Color(0xFFEF233C);

  static const Color textPrimary = Color(0xFFEEEEF5);
  static const Color textSecondary = Color(0xFF8888A4);
  static const Color textMuted = Color(0xFF4A4A60);

  // Mesaj renkleri
  static const Color outgoingBubble = Color(0xFF1A1A4E);
  static const Color incomingBubble = Color(0xFF1A2A1E);

  // --- Gradyanlar ---
  static const LinearGradient neonGradient = LinearGradient(
    colors: [neonCyan, neonPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0A0A0F), Color(0xFF0D0D18)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // --- Ana Tema ---
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: neonCyan,
        secondary: neonPurple,
        surface: surface,
        background: background,
        error: neonRed,
        onPrimary: background,
        onSecondary: background,
        onSurface: textPrimary,
        onBackground: textPrimary,
        outline: border,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
            fontSize: 32, fontWeight: FontWeight.w700, color: textPrimary),
        displayMedium: TextStyle(
            fontSize: 28, fontWeight: FontWeight.w700, color: textPrimary),
        headlineLarge: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
        headlineMedium: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
        titleLarge: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w400, color: textPrimary),
        bodyMedium: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w400, color: textSecondary),
        labelLarge: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w500, color: neonCyan),
        labelMedium: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w500, color: textMuted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.3,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: neonCyan,
        unselectedItemColor: textMuted,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: neonCyan, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textMuted, fontFamily: 'Inter'),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonCyan,
          foregroundColor: background,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
