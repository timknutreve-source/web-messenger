import '../../contact/domain/contact_user_summary.dart';

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.otherUser,
    required this.lastActivityAt,
    required this.archived,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
        id: json['id'] as String,
        otherUser: ContactUserSummary.fromJson(json['otherUser'] as Map<String, dynamic>),
        lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
        archived: json['archived'] as bool,
      );

  final String id;
  final ContactUserSummary otherUser;
  final DateTime lastActivityAt;
  final bool archived;
}
