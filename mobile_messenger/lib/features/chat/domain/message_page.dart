import 'message.dart';

/// A page of messages, oldest-first, ready to render directly.
class MessagePage {
  const MessagePage({required this.messages, required this.hasMore});

  factory MessagePage.fromJson(Map<String, dynamic> json) => MessagePage(
        messages:
            (json['messages'] as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList(),
        hasMore: json['hasMore'] as bool,
      );

  final List<Message> messages;
  final bool hasMore;
}
