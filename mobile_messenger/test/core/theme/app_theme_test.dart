import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/theme/app_colors.dart';
import 'package:mobile_messenger/core/theme/app_theme.dart';
import 'package:mobile_messenger/core/theme/theme_mode_provider.dart';
import 'package:mobile_messenger/features/chat/presentation/widgets/chat_list_tile.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final entry in {'dark': AppTheme.dark, 'light': AppTheme.light}.entries) {
    group('${entry.key} theme', () {
      final theme = entry.value;
      final c = theme.extension<AppColors>()!;

      test('exposes the semantic palette and keeps Material in sync with it', () {
        expect(theme.colorScheme.primary, c.primary);
        expect(theme.colorScheme.error, c.error);
        expect(theme.scaffoldBackgroundColor, c.background);
      });

      test('meets WCAG AA contrast for the text people actually read', () {
        expect(_contrast(c.textPrimary, c.background), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.textPrimary, c.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.textSecondary, c.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.textOnPrimary, c.primary), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.bubbleOutgoingText, c.bubbleOutgoingStart), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.bubbleOutgoingText, c.bubbleOutgoingEnd), greaterThanOrEqualTo(4.5));
      });
    });
  }

  test('the theme mode defaults to dark and toggles', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    container.read(themeModeProvider.notifier).toggle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    container.read(themeModeProvider.notifier).toggle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  group('formatChatTime', () {
    final now = DateTime(2026, 9, 19, 15, 30);

    test('today shows the clock time', () {
      expect(formatChatTime(DateTime(2026, 9, 19, 8, 5), now: now), '08:05');
    });

    test('yesterday, then a weekday within the week, then a date', () {
      expect(formatChatTime(DateTime(2026, 9, 18, 23, 59), now: now), 'Yesterday');
      expect(formatChatTime(DateTime(2026, 9, 15, 12), now: now), 'Tue');
      expect(formatChatTime(DateTime(2026, 8, 30, 12), now: now), '30 Aug');
      expect(formatChatTime(DateTime(2025, 12, 24, 12), now: now), '24 Dec 2025');
    });
  });
}
