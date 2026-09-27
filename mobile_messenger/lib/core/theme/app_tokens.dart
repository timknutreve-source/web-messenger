import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Spacing scale (4-pt grid). Prefer these over ad-hoc numbers.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}

/// Corner radii - one family, so every surface feels related.
class AppRadius {
  const AppRadius._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

/// Animation timing: fast, subtle, purposeful.
class AppDurations {
  const AppDurations._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 340);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
}

/// Layout widths shared by the responsive layouts.
class AppLayout {
  const AppLayout._();

  /// At or above this width the app uses the desktop shell (three panes).
  static const double desktopBreakpoint = 900;

  /// Wide enough for the message action button / hover affordances.
  static const double wideContent = 720;

  static const double railWidth = 76;
  static const double listPaneWidth = 344;
  static const double infoPaneWidth = 340;
  static const double minChatPanelWidth = 380;
  static const double authCardMaxWidth = 440;
  static const double formMaxWidth = 520;
}

/// Elevation expressed as shadows (Material elevation tints look flat on the
/// dark palette). Softer and lower-opacity in the light theme.
class AppShadows {
  const AppShadows._();

  static List<BoxShadow> card(AppColors c) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: c.isDark ? 0.34 : 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: c.isDark ? 0.22 : 0.05),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> floating(AppColors c) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: c.isDark ? 0.45 : 0.14),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
      ];

  static List<BoxShadow> glow(Color color) => [
        BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -2, offset: const Offset(0, 4)),
      ];
}
