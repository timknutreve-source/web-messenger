import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'brand_mark.dart';

/// A friendly, geometric empty state: two tilted cards behind a round icon
/// tile, a title, one line of guidance and (optionally) the next action.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final art = compact ? 76.0 : 104.0;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: art + 28,
                height: art + 16,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: -0.20,
                      child: _artCard(art * 0.78, c.accentGreen.withValues(alpha: c.isDark ? 0.16 : 0.14), c.accentGreen),
                    ),
                    Transform.translate(
                      offset: Offset(art * 0.12, art * 0.06),
                      child: Transform.rotate(
                        angle: 0.16,
                        child: _artCard(art * 0.7, c.primary.withValues(alpha: c.isDark ? 0.14 : 0.2), c.primary),
                      ),
                    ),
                    Container(
                      width: art * 0.72,
                      height: art * 0.72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.surfaceElevated,
                        border: Border.all(color: c.border),
                        boxShadow: AppShadows.card(c),
                      ),
                      child: Icon(icon, size: art * 0.34, color: c.primary),
                    ),
                    Positioned(
                      right: 2,
                      top: 6,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: c.accentRed, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 14 : 22),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(message!, style: text.bodyMedium?.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
              ],
              if (action != null) ...[const SizedBox(height: 18), action!],
              SizedBox(height: compact ? 10 : 18),
              const BrandStripe(scale: 0.8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artCard(double size, Color fill, Color edge) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: edge.withValues(alpha: 0.35)),
        ),
      );
}

/// A polished error state: a soft red tile with the icon (red never floods
/// the whole component), the message, and a retry action when possible.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Something went wrong',
    this.icon = Icons.wifi_off_rounded,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 56 : 68,
                height: compact ? 56 : 68,
                decoration: BoxDecoration(
                  color: c.errorSoft,
                  borderRadius: BorderRadius.circular(compact ? 18 : 22),
                  border: Border.all(color: c.error.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: c.error, size: compact ? 26 : 30),
              ),
              const SizedBox(height: 16),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(message, style: text.bodyMedium?.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An inline banner for form-level and session messages: soft tinted fill,
/// icon, text. [tone] picks the accent; the whole banner is never solid red.
class AppBanner extends StatelessWidget {
  const AppBanner({super.key, required this.message, this.icon, this.tone = AppBannerTone.error, this.textKey});

  final String message;
  final IconData? icon;
  final AppBannerTone tone;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color accent, Color fill, IconData defaultIcon) = switch (tone) {
      AppBannerTone.error => (c.error, c.errorSoft, Icons.error_outline_rounded),
      AppBannerTone.success => (c.success, c.successSoft, Icons.check_circle_outline_rounded),
      AppBannerTone.warning => (c.warning, c.warning.withValues(alpha: 0.16), Icons.info_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? defaultIcon, size: 19, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              key: textKey,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

enum AppBannerTone { error, success, warning }
