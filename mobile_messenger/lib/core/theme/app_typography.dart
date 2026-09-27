import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The type scale. Inter (bundled asset) with tight tracking on large sizes
/// and slightly open tracking on small metadata - hierarchy comes from size,
/// weight and colour together, not from colour alone.
///
/// Levels -> Material slots:
///   Display  -> displayLarge / displayMedium / displaySmall
///   Heading  -> headlineLarge / headlineMedium / headlineSmall
///   Title    -> titleLarge / titleMedium / titleSmall
///   Body     -> bodyLarge / bodyMedium / bodySmall
///   Caption  -> labelLarge / labelMedium
///   Metadata -> labelSmall
class AppTypography {
  const AppTypography._();

  static const String fontFamily = 'Inter';

  static TextTheme textTheme(AppColors c) {
    TextStyle s(double size, double height, FontWeight weight, {double spacing = 0, Color? color}) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          height: height / size,
          fontWeight: weight,
          letterSpacing: spacing,
          color: color ?? c.textPrimary,
        );

    return TextTheme(
      displayLarge: s(44, 52, FontWeight.w700, spacing: -1.2),
      displayMedium: s(36, 44, FontWeight.w700, spacing: -0.9),
      displaySmall: s(30, 38, FontWeight.w700, spacing: -0.7),
      headlineLarge: s(28, 36, FontWeight.w700, spacing: -0.6),
      headlineMedium: s(24, 32, FontWeight.w700, spacing: -0.45),
      headlineSmall: s(21, 28, FontWeight.w700, spacing: -0.3),
      titleLarge: s(18, 26, FontWeight.w600, spacing: -0.2),
      titleMedium: s(16, 22, FontWeight.w600, spacing: -0.1),
      titleSmall: s(14, 20, FontWeight.w600),
      bodyLarge: s(16, 24, FontWeight.w400),
      bodyMedium: s(14, 21, FontWeight.w400),
      bodySmall: s(13, 18, FontWeight.w400, color: c.textSecondary),
      labelLarge: s(14, 20, FontWeight.w600, spacing: 0.05),
      labelMedium: s(12, 16, FontWeight.w600, spacing: 0.2, color: c.textSecondary),
      labelSmall: s(11, 14, FontWeight.w500, spacing: 0.3, color: c.textMuted),
    );
  }
}
