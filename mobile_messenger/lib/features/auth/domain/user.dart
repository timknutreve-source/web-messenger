/// The authenticated account's safe, public data. Never carries a password
/// or password hash - the backend never sends those to the client.
class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.emailVerified,
    required this.aboutMe,
    required this.avatarFileName,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      emailVerified: json['emailVerified'] as bool,
      aboutMe: json['aboutMe'] as String?,
      avatarFileName: json['avatarFileName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String username;
  final String email;
  final bool emailVerified;

  /// Optional free-text bio. Null/empty until the user sets one.
  final String? aboutMe;

  /// Opaque server-generated file name (not a full URL/path) for the
  /// user's uploaded avatar, or null if they haven't uploaded one - in that
  /// case the UI shows a bundled default avatar rather than requesting an
  /// image from the backend.
  final String? avatarFileName;

  final DateTime createdAt;

  User copyWith({
    String? username,
    String? email,
    bool? emailVerified,
    String? aboutMe,
    String? avatarFileName,
  }) {
    return User(
      id: id,
      username: username ?? this.username,
      email: email ?? this.email,
      emailVerified: emailVerified ?? this.emailVerified,
      aboutMe: aboutMe ?? this.aboutMe,
      avatarFileName: avatarFileName ?? this.avatarFileName,
      createdAt: createdAt,
    );
  }
}
