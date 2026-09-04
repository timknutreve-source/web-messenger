import 'contact_user_summary.dart';

/// An accepted contact relationship with another user.
class Contact {
  const Contact({required this.user, required this.since});

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      user: ContactUserSummary.fromJson(json['user'] as Map<String, dynamic>),
      since: DateTime.parse(json['since'] as String),
    );
  }

  final ContactUserSummary user;
  final DateTime since;
}
