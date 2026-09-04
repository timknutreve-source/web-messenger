import 'contact_user_summary.dart';

/// An incoming, not-yet-responded-to contact invitation.
class PendingInvitation {
  const PendingInvitation({required this.id, required this.sender, required this.createdAt});

  factory PendingInvitation.fromJson(Map<String, dynamic> json) {
    return PendingInvitation(
      id: json['id'] as String,
      sender: ContactUserSummary.fromJson(json['sender'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final ContactUserSummary sender;
  final DateTime createdAt;
}
