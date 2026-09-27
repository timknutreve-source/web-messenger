import 'package:flutter/material.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';

/// Renders the user's avatar - or, if they haven't uploaded one (or it fails
/// to load), a tasteful placeholder: their initials on a deep tone derived
/// from their name, or a person glyph when no name is known. The UI never
/// shows a broken image and a new user has a usable avatar with nothing
/// stored per-user until they upload a photo.
///
/// [ring] draws the signature green-gold-red ring around it (used for "you"
/// and other emphasised identities).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.avatarFileName,
    required this.token,
    this.radius = 40,
    this.name,
    this.ring = false,
  });

  final String? avatarFileName;
  final String? token;
  final double radius;

  /// Used for the initials placeholder.
  final String? name;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final avatar = _avatar(context);
    if (!ring) return avatar;

    final c = context.colors;
    final gap = radius >= 30 ? 3.0 : 2.0;
    final stroke = radius >= 30 ? 3.0 : 2.0;
    return Container(
      padding: EdgeInsets.all(stroke),
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: c.ringGradient),
      child: Container(
        padding: EdgeInsets.all(gap),
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.background),
        child: avatar,
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final fileName = avatarFileName;
    final authToken = token;
    if (fileName == null || authToken == null) {
      return _placeholder(context);
    }

    final diameter = radius * 2;
    return ClipOval(
      child: Image.network(
        AppConfig.avatarUrl(fileName),
        headers: {'Authorization': 'Bearer $authToken'},
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _placeholder(context, loading: true);
        },
      ),
    );
  }

  Widget _placeholder(BuildContext context, {bool loading = false}) {
    final c = context.colors;
    final label = _initials(name);
    final (Color start, Color end) = _tones(name, c);
    // The initials are decoration - the adjacent name is what assistive tech reads.
    return ExcludeSemantics(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [start, end]),
        ),
        child: loading
            ? null
            : label == null
            ? Icon(Icons.person_rounded, size: radius * 1.05, color: Colors.white.withValues(alpha: 0.92))
            : Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.96),
                  fontSize: radius * 0.86,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  height: 1,
                ),
              ),
      ),
    );
  }

  static String? _initials(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final parts = trimmed.split(RegExp(r'[\s._-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    final first = String.fromCharCode(parts.first.runes.first);
    if (parts.length == 1) return first.toUpperCase();
    return (first + String.fromCharCode(parts[1].runes.first)).toUpperCase();
  }

  // A small set of deep, warm-leaning tones (green, teal, olive, amber,
  // terracotta, plum) chosen so avatars vary without ever looking neon.
  static const _hues = [152.0, 172.0, 96.0, 38.0, 14.0, 330.0];

  static (Color, Color) _tones(String? name, AppColors c) {
    if (name == null || name.isEmpty) {
      return (const Color(0xFF2E7D5B), const Color(0xFF1B4D39));
    }
    final hue = _hues[name.runes.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff) % _hues.length];
    return (
      HSLColor.fromAHSL(1, hue, 0.42, 0.34).toColor(),
      HSLColor.fromAHSL(1, (hue + 14) % 360, 0.46, 0.22).toColor(),
    );
  }
}
