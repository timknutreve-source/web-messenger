import 'package:flutter/material.dart';

/// The app's semantic colour palette - the single place colours are defined.
///
/// Read it anywhere with `context.colors`. Widgets should ask for a *role*
/// (`surfaceElevated`, `success`, `textMuted`) rather than a raw colour, so a
/// palette tweak is one edit here.
///
/// **Direction.** A deep, green-tinted graphite foundation with warm gold as
/// the action colour. Green is reserved for "alive/delivered" state and red for
/// unread, failed and destructive - never both side by side to say the same
/// thing, and status is always paired with an icon or label so colour is never
/// the only signal.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.background,
    required this.backgroundSecondary,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHover,
    required this.surfaceSelected,
    required this.primary,
    required this.primarySoft,
    required this.primaryStrong,
    required this.textOnPrimary,
    required this.accentYellow,
    required this.accentRed,
    required this.accentGreen,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.errorSoft,
    required this.successSoft,
    required this.badgeFill,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.link,
    required this.border,
    required this.divider,
    required this.bubbleOutgoingStart,
    required this.bubbleOutgoingEnd,
    required this.bubbleOutgoingText,
    required this.bubbleOutgoingMeta,
    required this.bubbleIncoming,
    required this.bubbleIncomingBorder,
    required this.scrim,
  });

  final Brightness brightness;

  // Surfaces, darkest to lightest (dark theme).
  final Color background;
  final Color backgroundSecondary;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHover;
  final Color surfaceSelected;

  // Brand / action.
  final Color primary; // warm golden yellow
  final Color primarySoft; // translucent gold wash for selected/active fills
  final Color primaryStrong; // hover/pressed gold
  final Color textOnPrimary;

  // The three reggae accents, used strategically.
  final Color accentYellow;
  final Color accentRed;
  final Color accentGreen;

  // Status.
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color errorSoft;
  final Color successSoft;
  final Color badgeFill; // unread/notification pill background

  // Text.
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color link;

  // Lines.
  final Color border;
  final Color divider;

  // Message bubbles.
  final Color bubbleOutgoingStart;
  final Color bubbleOutgoingEnd;
  final Color bubbleOutgoingText;
  final Color bubbleOutgoingMeta;
  final Color bubbleIncoming;
  final Color bubbleIncomingBorder;

  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  /// The signature gradient: deep green into warm gold. Used sparingly - the
  /// avatar ring, the send button glow, the brand mark.
  LinearGradient get signatureGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accentGreen, primary],
      );

  /// A three-stop ring for the "you" avatar and the selected chat accent:
  /// green -> gold -> a whisper of red.
  SweepGradient get ringGradient => SweepGradient(
        colors: [accentGreen, primary, accentRed, accentGreen],
        stops: const [0.0, 0.45, 0.8, 1.0],
      );

  LinearGradient get outgoingBubbleGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bubbleOutgoingStart, bubbleOutgoingEnd],
      );

  static const dark = AppColors(
    brightness: Brightness.dark,
    background: Color(0xFF090E0B),
    backgroundSecondary: Color(0xFF0E1511),
    surface: Color(0xFF131B16),
    surfaceElevated: Color(0xFF19231D),
    surfaceHover: Color(0xFF212D26),
    surfaceSelected: Color(0xFF283830),
    primary: Color(0xFFF0B429),
    primarySoft: Color(0x29F0B429),
    primaryStrong: Color(0xFFFFC94D),
    textOnPrimary: Color(0xFF1B1402),
    accentYellow: Color(0xFFF0B429),
    accentRed: Color(0xFFE5544D),
    accentGreen: Color(0xFF3DB37A),
    success: Color(0xFF3DB37A),
    warning: Color(0xFFE8A13A),
    error: Color(0xFFE5544D),
    info: Color(0xFF5FB4C9),
    errorSoft: Color(0x2BE5544D),
    successSoft: Color(0x263DB37A),
    badgeFill: Color(0xFFD23F38),
    textPrimary: Color(0xFFEDF2EE),
    textSecondary: Color(0xFFA6B4AB),
    textMuted: Color(0xFF7D8E85),
    link: Color(0xFFF0B429),
    border: Color(0xFF2B3A32),
    divider: Color(0xFF1C2620),
    bubbleOutgoingStart: Color(0xFF24694C),
    bubbleOutgoingEnd: Color(0xFF1B5039),
    bubbleOutgoingText: Color(0xFFF4F9F5),
    bubbleOutgoingMeta: Color(0xB8E4F1E9),
    bubbleIncoming: Color(0xFF1C2620),
    bubbleIncomingBorder: Color(0xFF2A3830),
    scrim: Color(0xB3000000),
  );

  static const light = AppColors(
    brightness: Brightness.light,
    background: Color(0xFFF5F2E9),
    backgroundSecondary: Color(0xFFEEEADD),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF1EEE3),
    surfaceSelected: Color(0xFFE6F0E8),
    primary: Color(0xFFEDAE22),
    primarySoft: Color(0x33EDAE22),
    primaryStrong: Color(0xFFD9990F),
    textOnPrimary: Color(0xFF1B1402),
    accentYellow: Color(0xFFEDAE22),
    accentRed: Color(0xFFC7372F),
    accentGreen: Color(0xFF1E7A50),
    success: Color(0xFF1E7A50),
    warning: Color(0xFFB87A12),
    error: Color(0xFFC7372F),
    info: Color(0xFF2A7A92),
    errorSoft: Color(0x1FC7372F),
    successSoft: Color(0x1F1E7A50),
    badgeFill: Color(0xFFC7372F),
    textPrimary: Color(0xFF14201A),
    textSecondary: Color(0xFF4B5D53),
    textMuted: Color(0xFF66776D),
    link: Color(0xFF1E7A50),
    border: Color(0xFFDDD8C8),
    divider: Color(0xFFE7E3D6),
    bubbleOutgoingStart: Color(0xFF24694C),
    bubbleOutgoingEnd: Color(0xFF1B5039),
    bubbleOutgoingText: Color(0xFFF4F9F5),
    bubbleOutgoingMeta: Color(0xB8E4F1E9),
    bubbleIncoming: Color(0xFFFFFFFF),
    bubbleIncomingBorder: Color(0xFFE2DDCE),
    scrim: Color(0x8C000000),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: l(background, other.background),
      backgroundSecondary: l(backgroundSecondary, other.backgroundSecondary),
      surface: l(surface, other.surface),
      surfaceElevated: l(surfaceElevated, other.surfaceElevated),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      surfaceSelected: l(surfaceSelected, other.surfaceSelected),
      primary: l(primary, other.primary),
      primarySoft: l(primarySoft, other.primarySoft),
      primaryStrong: l(primaryStrong, other.primaryStrong),
      textOnPrimary: l(textOnPrimary, other.textOnPrimary),
      accentYellow: l(accentYellow, other.accentYellow),
      accentRed: l(accentRed, other.accentRed),
      accentGreen: l(accentGreen, other.accentGreen),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      error: l(error, other.error),
      info: l(info, other.info),
      errorSoft: l(errorSoft, other.errorSoft),
      successSoft: l(successSoft, other.successSoft),
      badgeFill: l(badgeFill, other.badgeFill),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      link: l(link, other.link),
      border: l(border, other.border),
      divider: l(divider, other.divider),
      bubbleOutgoingStart: l(bubbleOutgoingStart, other.bubbleOutgoingStart),
      bubbleOutgoingEnd: l(bubbleOutgoingEnd, other.bubbleOutgoingEnd),
      bubbleOutgoingText: l(bubbleOutgoingText, other.bubbleOutgoingText),
      bubbleOutgoingMeta: l(bubbleOutgoingMeta, other.bubbleOutgoingMeta),
      bubbleIncoming: l(bubbleIncoming, other.bubbleIncoming),
      bubbleIncomingBorder: l(bubbleIncomingBorder, other.bubbleIncomingBorder),
      scrim: l(scrim, other.scrim),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The app palette for the current theme. Falls back to the palette that
  /// matches the ambient brightness when a widget is built outside the app's
  /// theme (e.g. a bare `MaterialApp` in a widget test), so nothing ever
  /// throws over a missing extension.
  AppColors get colors {
    final theme = Theme.of(this);
    return theme.extension<AppColors>() ?? (theme.brightness == Brightness.dark ? AppColors.dark : AppColors.light);
  }
}
