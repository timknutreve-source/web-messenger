/// Safe, public view of another user, as returned by the contacts API
/// (search results, invitation senders, contacts). Deliberately narrower
/// than [User] - never carries email-verification status, bio, or account
/// creation date.
class ContactUserSummary {
  const ContactUserSummary({
    required this.id,
    required this.username,
    required this.email,
    required this.avatarFileName,
  });

  factory ContactUserSummary.fromJson(Map<String, dynamic> json) {
    return ContactUserSummary(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      avatarFileName: json['avatarFileName'] as String?,
    );
  }

  final String id;
  final String username;
  final String email;
  final String? avatarFileName;
}
