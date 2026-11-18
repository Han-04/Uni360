import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF192D48);
  static const teal = Color(0xFF007F79);
  static const background = Color(0xFFF4F6FA);
  static const muted = Color(0xFF65758A);
}

abstract final class WorkerColors {
  static const blue = Color(0xFF145AF2);
  static const deepBlue = Color(0xFF123A9B);
  static const background = Color(0xFFF1F3F7);
  static const tint = Color(0xFFE7EEFF);
}

ThemeData buildWorkerTheme(ThemeData base) => base.copyWith(
  colorScheme: ColorScheme.fromSeed(
    seedColor: WorkerColors.blue,
    primary: WorkerColors.blue,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: WorkerColors.background,
  appBarTheme: base.appBarTheme.copyWith(
    backgroundColor: WorkerColors.background,
  ),
);

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
