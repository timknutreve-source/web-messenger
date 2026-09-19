import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../contact/domain/contact_user_summary.dart';
import 'chat_panel.dart';

/// A single conversation as a full page (the phone layout): an app bar with
/// the chat's name, search and info, over a [ChatPanel].
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.chatId, this.otherUser});

  final String chatId;

  /// Fallback title while the chat list (which knows the chat's real name,
  /// group or not) hasn't loaded, or for a chat that isn't in it.
  final ContactUserSummary? otherUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(chatSummaryProvider(chatId));
    return Scaffold(
      key: const Key('chat_screen'),
      appBar: AppBar(
        title: Text(summary?.title ?? otherUser?.username ?? 'Chat'),
        actions: chatHeaderActions(
          ref,
          chatId,
          onInfo: () => context.push('/chats/$chatId/info'),
        ),
      ),
      body: ChatPanel(chatId: chatId),
    );
  }
}
