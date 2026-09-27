import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A calm, atmospheric backdrop for full-screen surfaces (sign-in, splash):
/// the base background, two very soft colour glows (green top-left, gold
/// bottom-right) and a faint diagonal hairline texture. Kept low-contrast so
/// it adds depth without competing with content.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: c.background),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.9, -1.0),
                radius: 1.15,
                colors: [c.accentGreen.withValues(alpha: c.isDark ? 0.20 : 0.16), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.0, 1.05),
                radius: 1.0,
                colors: [c.primary.withValues(alpha: c.isDark ? 0.11 : 0.16), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: _DiagonalHairlines(c.textPrimary.withValues(alpha: 0.035)))),
        child,
      ],
    );
  }
}

class _DiagonalHairlines extends CustomPainter {
  _DiagonalHairlines(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const gap = 46.0;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalHairlines old) => old.color != color;
}
