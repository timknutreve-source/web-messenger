import 'package:flutter/material.dart';

import '../../../profile/presentation/widgets/profile_avatar.dart';
import '../../domain/chat_summary.dart';

/// A chat's avatar: the other person's picture for a direct chat, a group
/// icon for a group.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.chat, required this.token, this.radius = 20});

  final ChatSummary chat;
  final String? token;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (chat.isGroup) {
      final colors = Theme.of(context).colorScheme;
      return CircleAvatar(
        radius: radius,
        backgroundColor: colors.secondaryContainer,
        child: Icon(Icons.groups_outlined, size: radius * 1.1, color: colors.onSecondaryContainer),
      );
    }
    return ProfileAvatar(avatarFileName: chat.otherUser?.avatarFileName, token: token, radius: radius);
  }
}
