import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../profile/presentation/widgets/profile_avatar.dart';
import '../../domain/chat_summary.dart';

/// A chat's avatar: the other person's picture for a direct chat, a group
/// glyph on a green-to-gold tile for a group.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.chat, required this.token, this.radius = 20, this.ring = false});

  final ChatSummary chat;
  final String? token;
  final double radius;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    if (chat.isGroup) {
      final c = context.colors;
      final tile = Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.accentGreen.withValues(alpha: 0.85), const Color(0xFF14503A)],
          ),
        ),
        child: Icon(Icons.groups_rounded, size: radius * 1.05, color: Colors.white.withValues(alpha: 0.95)),
      );
      if (!ring) return tile;
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: c.ringGradient),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.background),
          child: tile,
        ),
      );
    }
    return ProfileAvatar(
      avatarFileName: chat.otherUser?.avatarFileName,
      token: token,
      radius: radius,
      name: chat.otherUser?.username,
      ring: ring,
    );
  }
}
