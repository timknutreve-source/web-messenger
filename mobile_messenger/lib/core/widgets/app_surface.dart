import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// A rounded, bordered, softly-elevated container - the base of panes, cards
/// and forms. [elevated] lifts it one step (dialogs, floating composer).
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppRadius.lg,
    this.elevated = false,
    this.shadow = false,
    this.color,
    this.borderColor,
    this.clip = true,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool elevated;
  final bool shadow;
  final Color? color;
  final Color? borderColor;
  final bool clip;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? (elevated ? c.surfaceElevated : c.surface)) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? c.divider),
        boxShadow: shadow ? AppShadows.card(c) : null,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      padding: padding,
      child: child,
    );
  }
}

/// The spinner used *inside* buttons. The theme's default spinner is gold,
/// which would vanish on a gold button - this takes the button's own
/// foreground colour.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key, this.color, this.size = 20});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: 2.2, color: color ?? context.colors.textOnPrimary),
    );
  }
}
