/// A WebSocket event broadcast on `/topic/chats/{chatId}`. [payload]'s shape
/// depends on [type] - see the backend's `ChatEvent` Javadoc for the mapping.
class ChatEvent {
  const ChatEvent({required this.type, required this.payload});

  factory ChatEvent.fromJson(Map<String, dynamic> json) => ChatEvent(
        type: json['type'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  final String type;
  final Map<String, dynamic> payload;
}
