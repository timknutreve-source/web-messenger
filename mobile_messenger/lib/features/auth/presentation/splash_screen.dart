import 'package:flutter/material.dart';

import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/brand_mark.dart';

/// Shown briefly at startup while the stored auth token (if any) is being
/// validated, before the router decides between the login screen and home.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AmbientBackground(
        child: Center(child: _PulsingBrand()),
      ),
    );
  }
}

class _PulsingBrand extends StatefulWidget {
  const _PulsingBrand();

  @override
  State<_PulsingBrand> createState() => _PulsingBrandState();
}

class _PulsingBrandState extends State<_PulsingBrand> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(opacity: 0.72 + 0.28 * _controller.value, child: child),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(size: 64),
          SizedBox(height: 18),
          BrandWordmark(fontSize: 22),
          SizedBox(height: 14),
          BrandStripe(),
        ],
      ),
    );
  }
}
