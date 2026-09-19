import '../../contact/domain/contact_user_summary.dart';
import 'attachment.dart';
import 'poll.dart';

enum MessageStatus { sent, delivered, read }

MessageStatus _messageStatusFromJson(String value) => switch (value) {
      'DELIVERED' => MessageStatus.delivered,
      'READ' => MessageStatus.read,
      _ => MessageStatus.sent,
    };

/// Whether an outgoing message has round-tripped to the server yet.
/// [MessageStatus] (sent/delivered/read) only applies once [SendState.confirmed].
enum SendState { confirmed, sending, failed }

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    required this.status,
    required this.createdAt,
    this.editedAt,
    required this.deleted,
    this.sendState = SendState.confirmed,
    this.attachments = const [],
    this.poll,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        sender: ContactUserSummary.fromJson(json['sender'] as Map<String, dynamic>),
        content: json['content'] as String?,
        status: _messageStatusFromJson(json['status'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        editedAt: json['editedAt'] != null ? DateTime.parse(json['editedAt'] as String) : null,
        deleted: json['deleted'] as bool,
        attachments: (json['attachments'] as List?)
                ?.map((e) => Attachment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        poll: json['poll'] != null ? Poll.fromJson(json['poll'] as Map<String, dynamic>) : null,
      );

  final String id;
  final String conversationId;
  final ContactUserSummary sender;
  final String? content;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool deleted;
  final SendState sendState;
  final List<Attachment> attachments;

  /// Set when this message is a poll (group chats only).
  final Poll? poll;

  bool get edited => editedAt != null;

  Message copyWith({
    String? content,
    MessageStatus? status,
    DateTime? editedAt,
    bool? deleted,
    SendState? sendState,
    Poll? poll,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        sender: sender,
        content: (deleted ?? this.deleted) ? null : (content ?? this.content),
        status: status ?? this.status,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
        deleted: deleted ?? this.deleted,
        sendState: sendState ?? this.sendState,
        attachments: (deleted ?? this.deleted) ? const [] : attachments,
        poll: (deleted ?? this.deleted) ? null : (poll ?? this.poll),
      );
}
