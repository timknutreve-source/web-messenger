/// The authenticated account's safe, public data. Never carries a password
/// or password hash - the backend never sends those to the client.
class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.emailVerified,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      emailVerified: json['emailVerified'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String username;
  final String email;
  final bool emailVerified;
  final DateTime createdAt;
}
