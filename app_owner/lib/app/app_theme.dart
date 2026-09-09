import 'package:flutter/material.dart';

import 'app_colors.dart';

final ThemeData appTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    surface: AppColors.surface,
    outline: AppColors.border,
  ),
  scaffoldBackgroundColor: AppColors.background,
  useMaterial3: true,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0.5,
  ),
  cardTheme: const CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
  ),
  dividerColor: AppColors.border,
);
