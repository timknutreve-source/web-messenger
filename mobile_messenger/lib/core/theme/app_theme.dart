import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Builds the app's [ThemeData] from the [AppColors] palette.
///
/// Every Material component is themed here once, so plain `FilledButton`,
/// `TextField`, `AlertDialog`, `TabBar`... all come out on-brand without
/// per-screen styling.
class AppTheme {
  const AppTheme._();

  static ThemeData get dark => _build(AppColors.dark);
  static ThemeData get light => _build(AppColors.light);

  static ThemeData _build(AppColors c) {
    final text = AppTypography.textTheme(c);
    final brightness = c.brightness;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.textOnPrimary,
      primaryContainer: c.isDark ? const Color(0xFF3B2F0C) : const Color(0xFFFCE7B0),
      onPrimaryContainer: c.isDark ? const Color(0xFFFFDE94) : const Color(0xFF3B2A00),
      secondary: c.accentGreen,
      onSecondary: c.isDark ? const Color(0xFF04140C) : Colors.white,
      secondaryContainer: c.isDark ? const Color(0xFF17392A) : const Color(0xFFCFE8D9),
      onSecondaryContainer: c.isDark ? const Color(0xFFC2EBD5) : const Color(0xFF0B3524),
      tertiary: c.primaryStrong,
      onTertiary: c.textOnPrimary,
      tertiaryContainer: c.isDark ? const Color(0xFF4A3A0E) : const Color(0xFFFBE3A2),
      onTertiaryContainer: c.isDark ? const Color(0xFFFFE9B0) : const Color(0xFF3B2A00),
      error: c.error,
      onError: Colors.white,
      errorContainer: c.isDark ? const Color(0xFF3C1815) : const Color(0xFFFADAD6),
      onErrorContainer: c.isDark ? const Color(0xFFFFCDC8) : const Color(0xFF5C120D),
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceDim: c.background,
      surfaceBright: c.surfaceHover,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.backgroundSecondary,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceElevated,
      surfaceContainerHighest: c.surfaceHover,
      outline: c.border,
      outlineVariant: c.divider,
      shadow: Colors.black,
      scrim: c.scrim,
      inverseSurface: c.isDark ? const Color(0xFFEDF2EE) : const Color(0xFF14201A),
      onInverseSurface: c.isDark ? const Color(0xFF14201A) : const Color(0xFFEDF2EE),
      inversePrimary: c.isDark ? const Color(0xFF7A5A05) : const Color(0xFFFFD36B),
      surfaceTint: Colors.transparent,
    );

    OutlineInputBorder inputBorder(Color color, {double width = 1}) => OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    final hover = Colors.white.withValues(alpha: c.isDark ? 0.06 : 0.0);
    final overlayHover = c.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppTypography.fontFamily,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      extensions: [c],
      splashFactory: InkRipple.splashFactory,
      splashColor: c.primary.withValues(alpha: 0.10),
      highlightColor: Colors.transparent,
      hoverColor: hover == Colors.transparent ? overlayHover : hover,
      focusColor: c.primary.withValues(alpha: 0.16),
      dividerColor: c.divider,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
      }),
      iconTheme: IconThemeData(color: c.textSecondary, size: 22),
      primaryIconTheme: IconThemeData(color: c.textPrimary, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        toolbarHeight: 60,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: c.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: c.textSecondary, size: 22),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceElevated,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder(c.border),
        enabledBorder: inputBorder(c.border),
        focusedBorder: inputBorder(c.primary, width: 1.6),
        errorBorder: inputBorder(c.error),
        focusedErrorBorder: inputBorder(c.error, width: 1.6),
        disabledBorder: inputBorder(c.divider),
        labelStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
        floatingLabelStyle: text.labelMedium?.copyWith(color: c.primary),
        hintStyle: text.bodyMedium?.copyWith(color: c.textMuted),
        helperStyle: text.bodySmall?.copyWith(color: c.textMuted),
        errorStyle: text.bodySmall?.copyWith(color: c.error),
        counterStyle: text.labelSmall,
        prefixIconColor: c.textMuted,
        suffixIconColor: c.textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.textOnPrimary,
          disabledBackgroundColor: c.surfaceHover,
          disabledForegroundColor: c.textMuted,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: text.labelLarge?.copyWith(fontSize: 15, color: c.textOnPrimary),
          elevation: 0,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return Colors.black.withValues(alpha: 0.14);
            if (states.contains(WidgetState.hovered)) return Colors.white.withValues(alpha: 0.18);
            if (states.contains(WidgetState.focused)) return Colors.white.withValues(alpha: 0.22);
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.link,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          highlightColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          minimumSize: const Size(44, 44),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.surface,
          foregroundColor: c.textSecondary,
          selectedBackgroundColor: c.primarySoft,
          selectedForegroundColor: c.primary,
          side: BorderSide(color: c.border),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: c.divider),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.xlAll,
          side: BorderSide(color: c.border),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 480),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surfaceElevated,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: c.border,
        dragHandleSize: const Size(40, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        constraints: const BoxConstraints(maxWidth: 560),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        selectedColor: c.textPrimary,
        selectedTileColor: c.surfaceSelected,
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        titleTextStyle: text.titleSmall?.copyWith(fontSize: 15),
        subtitleTextStyle: text.bodySmall,
        leadingAndTrailingTextStyle: text.labelSmall,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.textPrimary,
        unselectedLabelColor: c.textMuted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: c.divider,
        dividerHeight: 1,
        overlayColor: WidgetStatePropertyAll(c.surfaceHover),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: c.primary, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          insets: const EdgeInsets.symmetric(horizontal: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.backgroundSecondary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: c.primarySoft,
        indicatorShape: RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => text.labelMedium?.copyWith(
              color: states.contains(WidgetState.selected) ? c.textPrimary : c.textMuted,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? c.primary : c.textMuted,
              size: 24,
            )),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.isDark ? c.surfaceSelected : const Color(0xFF14201A),
        contentTextStyle: text.bodyMedium?.copyWith(color: c.isDark ? c.textPrimary : Colors.white),
        actionTextColor: c.primary,
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: c.border)),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        showDuration: const Duration(seconds: 2),
        preferBelow: true,
        textStyle: text.labelMedium?.copyWith(color: c.isDark ? c.textPrimary : Colors.white),
        decoration: BoxDecoration(
          color: c.isDark ? const Color(0xFF2C3B33) : const Color(0xFF14201A),
          borderRadius: AppRadius.smAll,
          border: Border.all(color: c.border.withValues(alpha: c.isDark ? 1 : 0)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.badgeFill,
        textColor: Colors.white,
        textStyle: text.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0),
        smallSize: 8,
        largeSize: 18,
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceElevated,
        side: BorderSide(color: c.border),
        labelStyle: text.labelMedium?.copyWith(color: c.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.textOnPrimary : c.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceHover,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.textOnPrimary),
        side: BorderSide(color: c.textMuted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.textMuted,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceHover,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: c.border)),
        textStyle: text.bodyMedium,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.border),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.primary,
        selectionColor: c.primary.withValues(alpha: 0.28),
        selectionHandleColor: c.primary,
      ),
    );
  }
}
