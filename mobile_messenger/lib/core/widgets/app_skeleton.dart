import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Sweeps a soft highlight across its (opaque, skeleton-coloured) children.
/// One controller drives a whole skeleton screen.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final highlight = c.isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.75);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final t = _controller.value;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(-1.6 + 3.2 * t, -0.3),
              end: Alignment(-0.6 + 3.2 * t, 0.3),
              colors: [Colors.transparent, highlight, Colors.transparent],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(rect),
            child: child,
          );
        },
      ),
    );
  }
}

/// A rounded placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 12, this.radius = 8, this.circle = false});

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: c.surfaceHover,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton for a list of rows with an avatar and two lines (chat list,
/// contacts, invitations).
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 7, this.padding = const EdgeInsets.fromLTRB(14, 8, 14, 8)});

  final int rows;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: rows,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const SkeletonBox(height: 48, circle: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 90.0 + (i % 3) * 34, height: 13),
                    const SizedBox(height: 9),
                    SkeletonBox(width: 150.0 + (i % 4) * 22, height: 11),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const SkeletonBox(width: 30, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for a conversation: alternating incoming/outgoing bubbles.
class MessagesSkeleton extends StatelessWidget {
  const MessagesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    const widths = [220.0, 150.0, 260.0, 120.0, 200.0];
    return Shimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        reverse: true,
        itemCount: widths.length,
        itemBuilder: (context, i) {
          final mine = i.isOdd;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: SkeletonBox(width: widths[i], height: 44 + (i % 2) * 14, radius: AppRadius.lg),
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton for a profile/detail page.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SkeletonBox(height: 112, circle: true),
            SizedBox(height: 22),
            SkeletonBox(width: 160, height: 18),
            SizedBox(height: 12),
            SkeletonBox(width: 210, height: 12),
            SizedBox(height: 28),
            SkeletonBox(width: 320, height: 84, radius: AppRadius.lg),
          ],
        ),
      ),
    );
  }
}
