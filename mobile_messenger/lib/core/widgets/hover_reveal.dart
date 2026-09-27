import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Tracks whether the pointer is over - or keyboard focus is within - a
/// region, and tells the [builder] whether secondary actions should be
/// *revealed*.
///
/// Actions are revealed on hover/focus for people with a mouse, but are always
/// shown when no mouse is connected (phones, tablets), so nothing is ever
/// hidden behind an interaction a touch user cannot perform.
class HoverReveal extends StatefulWidget {
  const HoverReveal({super.key, required this.builder});

  final Widget Function(BuildContext context, bool revealed) builder;

  @override
  State<HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<HoverReveal> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final mouseConnected = RendererBinding.instance.mouseTracker.mouseIsConnected;
    final revealed = _hovered || _focused || !mouseConnected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: widget.builder(context, revealed),
      ),
    );
  }
}
