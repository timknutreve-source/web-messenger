import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// An unread/notification count pill. Red is reserved for exactly this kind
/// of "needs your attention" signal, and the number itself carries the
/// meaning, so it never relies on colour alone.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.max = 99, this.compact = false});

  final int count;
  final int max;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = count > max ? '$max+' : '$count';
    return Semantics(
      label: '$count unread',
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minWidth: compact ? 18 : 22, minHeight: compact ? 18 : 22),
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.badgeFill,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: c.badgeFill.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 10.5 : 11.5,
            fontWeight: FontWeight.w700,
            height: 1.1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// A small labelled status pill (e.g. "Admin", "Pending", "Anonymous").
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.icon, this.color, this.filled = false});

  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? tone.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: tone), const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(color: tone, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2, height: 1.1),
          ),
        ],
      ),
    );
  }
}
