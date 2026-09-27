import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Three softly bouncing dots - the "someone is typing" cue that sits next to
/// the typing text (the text is the accessible signal; the dots are ornament).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color, this.size = 5});

  final Color color;
  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.only(right: i == 2 ? 0 : widget.size * 0.6),
                  child: _dot(i),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _dot(int index) {
    final phase = (_controller.value - index * 0.16) % 1.0;
    // A single hump per cycle: up and back down over the first 40%.
    final lift = phase < 0.4 ? math.sin(phase / 0.4 * math.pi) : 0.0;
    return Transform.translate(
      offset: Offset(0, -lift * widget.size * 0.9),
      child: Opacity(
        opacity: 0.45 + lift * 0.55,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
