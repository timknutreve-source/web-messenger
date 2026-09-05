import '../../contact/domain/contact_user_summary.dart';

/// A preview of a conversation's most recent message, for the chat list.
/// [attachmentType] is `"IMAGE"`/`"VIDEO"`/`null` - the client decides how to
/// render that (e.g. "📷 Photo"), never baked in by the backend.
class LastMessagePreview {
  const LastMessagePreview({required this.content, required this.deleted, required this.attachmentType});

  factory LastMessagePreview.fromJson(Map<String, dynamic> json) => LastMessagePreview(
        content: json['content'] as String?,
        deleted: json['deleted'] as bool,
        attachmentType: json['attachmentType'] as String?,
      );

  final String? content;
  final bool deleted;
  final String? attachmentType;
}

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.otherUser,
    required this.lastActivityAt,
    required this.archived,
    this.lastMessage,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
        id: json['id'] as String,
        otherUser: ContactUserSummary.fromJson(json['otherUser'] as Map<String, dynamic>),
        lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
        archived: json['archived'] as bool,
        lastMessage: json['lastMessage'] != null
            ? LastMessagePreview.fromJson(json['lastMessage'] as Map<String, dynamic>)
            : null,
      );

  final String id;
  final ContactUserSummary otherUser;
  final DateTime lastActivityAt;
  final bool archived;
  final LastMessagePreview? lastMessage;

  /// A short, safe-to-display summary of the last message - never a raw
  /// internal filename, and never fake content when there is none.
  String get previewText {
    final last = lastMessage;
    if (last == null) return 'No messages yet';
    if (last.deleted) return 'This message was deleted';

    final hasText = last.content != null && last.content!.trim().isNotEmpty;
    final attachmentLabel = switch (last.attachmentType) {
      'IMAGE' => '📷 Photo',
      'VIDEO' => '🎥 Video',
      _ => null,
    };
    if (attachmentLabel != null) {
      return hasText ? '$attachmentLabel  ${last.content}' : attachmentLabel;
    }
    return hasText ? last.content! : 'No messages yet';
  }
}
