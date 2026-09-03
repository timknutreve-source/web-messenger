import 'user.dart';

/// Resolved authentication state. Loading/error while resolving it are
/// represented by the surrounding `AsyncValue` from Riverpod, not by this type.
sealed class AuthState {
  const AuthState();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user, required this.token});

  final User user;
  final String token;
}
