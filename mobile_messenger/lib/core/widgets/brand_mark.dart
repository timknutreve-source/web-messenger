import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app's mark: a gold speech bubble on a deep green tile, with a slim
/// green/gold/red diagonal accent in the corner - the only place all three
/// reggae colours meet, and at a size where it reads as detail, not decoration.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Web Messenger',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BrandMarkPainter(context.colors)),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter(this.colors);

  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final tile = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.28));

    // Tile.
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF238A5E), Color(0xFF0D2A1E)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      tile.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    // Diagonal accent, clipped to the tile: green, gold, red.
    canvas.save();
    canvas.clipRRect(tile);
    final stripe = s * 0.05;
    final colorsList = [colors.accentGreen, colors.primary, colors.accentRed];
    for (var i = 0; i < 3; i++) {
      final offset = s * 0.60 + i * (stripe * 1.7);
      final path = Path()
        ..moveTo(s, offset)
        ..lineTo(s, offset + stripe)
        ..lineTo(s - (s - offset - stripe), s)
        ..lineTo(s - (s - offset), s)
        ..close();
      canvas.drawPath(path, Paint()..color = colorsList[i].withValues(alpha: 0.95));
    }
    canvas.restore();

    // Bubble.
    final bubble = RRect.fromLTRBR(s * 0.2, s * 0.22, s * 0.8, s * 0.64, Radius.circular(s * 0.14));
    final tail = Path()
      ..moveTo(s * 0.3, s * 0.6)
      ..lineTo(s * 0.26, s * 0.78)
      ..lineTo(s * 0.46, s * 0.62)
      ..close();
    final bubblePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFD66B), Color(0xFFEFAE1E)],
      ).createShader(Rect.fromLTWH(s * 0.2, s * 0.2, s * 0.6, s * 0.6));
    canvas.drawShadow(Path()..addRRect(bubble), Colors.black.withValues(alpha: 0.5), s * 0.04, false);
    canvas.drawRRect(bubble, bubblePaint);
    canvas.drawPath(tail, bubblePaint);

    // Typing dots inside the bubble.
    final dot = Paint()..color = const Color(0xFF1B1402).withValues(alpha: 0.82);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(s * (0.35 + i * 0.15), s * 0.43), s * 0.045, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter old) => old.colors != colors;
}

/// The three-colour signature stroke: three short rounded bars. A recurring
/// detail (under headings, on selected items), never a large graphic.
class BrandStripe extends StatelessWidget {
  const BrandStripe({super.key, this.height = 3, this.scale = 1});

  final double height;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(Color color, double width) => Container(
          width: width * scale,
          height: height,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
        );
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          bar(c.accentGreen, 22),
          SizedBox(width: 3 * scale),
          bar(c.primary, 12),
          SizedBox(width: 3 * scale),
          bar(c.accentRed, 6),
        ],
      ),
    );
  }
}

/// "Web Messenger" set with contrast in weight rather than colour.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.fontSize = 18});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Web ', style: TextStyle(fontWeight: FontWeight.w500, color: c.textSecondary)),
        TextSpan(text: 'Messenger', style: TextStyle(fontWeight: FontWeight.w700, color: c.textPrimary)),
      ]),
      style: TextStyle(fontSize: fontSize, letterSpacing: -0.3, height: 1.1),
    );
  }
}

/// Mark + wordmark lock-up.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.markSize = 36, this.fontSize = 19});

  final double markSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        const SizedBox(width: 12),
        BrandWordmark(fontSize: fontSize),
      ],
    );
  }
}
