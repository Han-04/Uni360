import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF192D48);
  static const teal = Color(0xFF007F79);
  static const background = Color(0xFFF4F6FA);
  static const muted = Color(0xFF65758A);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    primary: AppColors.teal,
    secondary: AppColors.navy,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.navy,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: AppColors.navy,
      displayColor: AppColors.navy,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDDE3EC)),
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.teal.withValues(alpha: .12),
    ),
  );
}
