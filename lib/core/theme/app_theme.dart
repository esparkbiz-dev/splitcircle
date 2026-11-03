import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF14213D);
  static const accent = Color(0xFF3A86FF);
  static const received = Color(0xFF1B9E5A); // money you get back
  static const owed = Color(0xFFE76F2E); // money you owe
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: b == Brightness.light ? AppColors.navy : AppColors.accent,
      secondary: AppColors.accent,
      brightness: b,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          b == Brightness.light ? const Color(0xFFF6F7FB) : const Color(0xFF0F1115),
      appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withOpacity(0.5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

/// Spacing scale used everywhere.
class Gap {
  static const double xs = 4, s = 8, m = 16, l = 24, xl = 32;
}
