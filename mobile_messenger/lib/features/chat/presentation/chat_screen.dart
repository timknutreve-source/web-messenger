import 'package:flutter/material.dart';

import '../../contact/domain/contact_user_summary.dart';

/// Placeholder conversation screen. Actual message sending/receiving is
/// implemented in Phase 7 - Phase 6 only establishes the chat list and the
/// route into a conversation.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.chatId, this.otherUser});

  final String chatId;
  final ContactUserSummary? otherUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('chat_screen'),
      appBar: AppBar(title: Text(otherUser?.username ?? 'Chat')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Messaging is coming in the next phase.',
            key: const Key('chat_screen_placeholder_text'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
