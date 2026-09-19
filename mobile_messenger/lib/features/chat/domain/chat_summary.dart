import '../../contact/domain/contact_user_summary.dart';

/// A preview of a conversation's most recent message, for the chat list.
/// [attachmentType] is `"IMAGE"`/`"VIDEO"`/`null` - the client decides how to
/// render that (e.g. "📷 Photo"), never baked in by the backend.
class LastMessagePreview {
  const LastMessagePreview({
    required this.content,
    required this.deleted,
    required this.attachmentType,
    this.senderUsername,
  });

  factory LastMessagePreview.fromJson(Map<String, dynamic> json) => LastMessagePreview(
        content: json['content'] as String?,
        deleted: json['deleted'] as bool,
        attachmentType: json['attachmentType'] as String?,
        senderUsername: json['senderUsername'] as String?,
      );

  final String? content;
  final bool deleted;
  final String? attachmentType;

  /// Who sent it - only set in a group's chat list ("alice: see you at 6").
  final String? senderUsername;
}

enum ChatType { direct, group }

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.lastActivityAt,
    required this.archived,
    this.type = ChatType.direct,
    this.otherUser,
    this.name,
    this.memberCount = 0,
    this.lastMessage,
    this.unreadCount = 0,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
        id: json['id'] as String,
        type: json['type'] == 'GROUP' ? ChatType.group : ChatType.direct,
        otherUser: json['otherUser'] != null
            ? ContactUserSummary.fromJson(json['otherUser'] as Map<String, dynamic>)
            : null,
        name: json['name'] as String?,
        memberCount: json['memberCount'] as int? ?? 0,
        lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
        archived: json['archived'] as bool,
        lastMessage: json['lastMessage'] != null
            ? LastMessagePreview.fromJson(json['lastMessage'] as Map<String, dynamic>)
            : null,
        unreadCount: json['unreadCount'] as int? ?? 0,
      );

  final String id;
  final ChatType type;

  /// The other person in a direct chat; null for a group.
  final ContactUserSummary? otherUser;

  /// The group's name; null for a direct chat.
  final String? name;
  final int memberCount;
  final DateTime lastActivityAt;
  final bool archived;
  final LastMessagePreview? lastMessage;
  final int unreadCount;

  bool get isGroup => type == ChatType.group;

  /// What the chat list and chat header call this chat.
  String get title => isGroup ? (name ?? 'Group') : (otherUser?.username ?? 'Chat');

  ChatSummary copyWith({
    int? unreadCount,
    DateTime? lastActivityAt,
    int? memberCount,
    LastMessagePreview? lastMessage,
  }) =>
      ChatSummary(
        id: id,
        type: type,
        otherUser: otherUser,
        name: name,
        memberCount: memberCount ?? this.memberCount,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
        archived: archived,
        lastMessage: lastMessage ?? this.lastMessage,
        unreadCount: unreadCount ?? this.unreadCount,
      );

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
      'AUDIO' => '🎤 Voice message',
      _ => null,
    };
    final String body;
    if (attachmentLabel != null) {
      body = hasText ? '$attachmentLabel  ${last.content}' : attachmentLabel;
    } else {
      body = hasText ? last.content! : 'No messages yet';
    }
    final sender = last.senderUsername;
    return isGroup && sender != null && body != 'No messages yet' ? '$sender: $body' : body;
  }
}
