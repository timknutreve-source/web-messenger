import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../contact/domain/contact_user_summary.dart';
import 'chat_panel.dart';

/// A single conversation as a full page (the phone layout): an app bar with
/// the chat's avatar, name, live subtitle, search and info, over a [ChatPanel].
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.chatId, this.otherUser});

  final String chatId;

  /// Fallback title while the chat list (which knows the chat's real name,
  /// group or not) hasn't loaded, or for a chat that isn't in it.
  final ContactUserSummary? otherUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Scaffold(
      key: const Key('chat_screen'),
      backgroundColor: c.background,
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 64,
        backgroundColor: c.surface,
        shape: Border(bottom: BorderSide(color: c.divider)),
        title: ChatHeaderTitle(
          chatId: chatId,
          fallbackTitle: otherUser?.username,
          avatarRadius: 19,
        ),
        actions: [
          ...chatHeaderActions(
            context,
            ref,
            chatId,
            onInfo: () => context.push('/chats/$chatId/info'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ChatPanel(chatId: chatId),
    );
  }
}
