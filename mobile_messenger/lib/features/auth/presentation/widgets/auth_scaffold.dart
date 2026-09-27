import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/ambient_background.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/brand_mark.dart';

/// The frame shared by every signed-out screen (log in, register, verify,
/// forgot/reset password).
///
/// Wide screens get a split layout - a brand hero with a small product
/// preview on the left, the form card on the right. Phones get the brand
/// lock-up above a focused form card. Same design language, one component.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showBack,
    this.onBack,
    this.backKey,
    this.maxWidth = AppLayout.authCardMaxWidth,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Whether to show a back button. Defaults to whether the route can pop.
  final bool? showBack;
  final VoidCallback? onBack;
  final Key? backKey;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final back = showBack ?? canPop;

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= AppLayout.desktopBreakpoint;
              final backButton = back
                  ? IconButton(
                      key: backKey,
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    )
                  : null;
              // On a phone the back button stays pinned to the corner (the form
              // scrolls beneath it); on a wide screen it sits in the card.
              final card = _FormCard(
                title: title,
                subtitle: subtitle,
                maxWidth: maxWidth,
                back: wide ? backButton : null,
                child: child,
              );

              if (wide) {
                return Row(
                  children: [
                    const Expanded(flex: 11, child: _BrandHero()),
                    Expanded(
                      flex: 10,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                          child: card,
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, backButton != null ? 56 : 16, 16, 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 22),
                            child: BrandLockup(),
                          ),
                          card,
                        ],
                      ),
                    ),
                  ),
                  if (backButton != null)
                    Positioned(
                      top: 4,
                      left: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.surfaceElevated.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          border: Border.all(color: context.colors.border),
                        ),
                        child: backButton,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.title, required this.child, required this.maxWidth, this.subtitle, this.back});

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? back;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AppSurface(
        radius: AppRadius.xl,
        elevated: true,
        shadow: true,
        clip: false,
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (back != null)
              Align(alignment: Alignment.centerLeft, child: Transform.translate(offset: const Offset(-10, 0), child: back))
            else
              const SizedBox(height: 6),
            Text(title, style: text.headlineMedium),
            const SizedBox(height: 10),
            const Align(alignment: Alignment.centerLeft, child: BrandStripe()),
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Text(subtitle!, style: text.bodyMedium?.copyWith(color: c.textSecondary)),
            ],
            const SizedBox(height: 22),
            child,
          ],
        ),
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 44, 24, 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLockup(markSize: 42, fontSize: 21),
          const Spacer(),
          Text(
            'Stay close,\nin real time.',
            style: text.displayMedium?.copyWith(height: 1.08),
          ),
          const SizedBox(height: 18),
          const BrandStripe(height: 4, scale: 1.3),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              'Chats, groups, polls and media that stay in sync between your phone and your browser.',
              style: text.bodyLarge?.copyWith(color: c.textSecondary),
            ),
          ),
          const SizedBox(height: 30),
          const _HeroPreview(),
          const Spacer(),
          Wrap(
            spacing: 22,
            runSpacing: 10,
            children: const [
              _HeroPoint(icon: Icons.bolt_rounded, label: 'Instant sync'),
              _HeroPoint(icon: Icons.groups_rounded, label: 'Groups & polls'),
              _HeroPoint(icon: Icons.lock_rounded, label: 'Encrypted at rest'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPoint extends StatelessWidget {
  const _HeroPoint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: c.primary),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.textSecondary)),
      ],
    );
  }
}

/// A static mock of a conversation - not data, just a glimpse of the product.
class _HeroPreview extends StatelessWidget {
  const _HeroPreview();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bubble(String text, {required bool mine}) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 250),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: mine ? c.outgoingBubbleGradient : null,
              color: mine ? null : c.bubbleIncoming,
              border: mine ? null : Border.all(color: c.bubbleIncomingBorder),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 5),
                bottomRight: Radius.circular(mine ? 5 : 18),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(color: mine ? c.bubbleOutgoingText : c.textPrimary, fontSize: 14, height: 1.35),
            ),
          ),
        );

    return ExcludeSemantics(
      child: Transform.rotate(
        angle: -0.025,
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.72),
            borderRadius: AppRadius.xlAll,
            border: Border.all(color: c.border),
            boxShadow: AppShadows.floating(c),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bubble('Saturday, 8pm at the studio?', mine: false),
              const SizedBox(height: 8),
              bubble('Count me in. Bringing the speakers.', mine: true),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surfaceElevated,
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Which night works?', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    for (final (label, value, tone) in [
                      ('Friday', 0.34, c.primary),
                      ('Saturday', 0.66, c.accentGreen),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              Container(height: 26, color: c.surfaceHover),
                              FractionallySizedBox(
                                widthFactor: value,
                                child: Container(height: 26, color: tone.withValues(alpha: 0.32)),
                              ),
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(label, style: TextStyle(color: c.textPrimary, fontSize: 12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
