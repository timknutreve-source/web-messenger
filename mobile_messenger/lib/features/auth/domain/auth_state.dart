import 'user.dart';

/// Resolved authentication state. Loading/error while resolving it are
/// represented by the surrounding `AsyncValue` from Riverpod, not by this type.
sealed class AuthState {
  const AuthState();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.sessionExpired = false});

  /// True when the user did not sign out themselves but the server stopped
  /// accepting their session (it expired, or it was signed out from another
  /// device) - the login screen explains this instead of just appearing.
  final bool sessionExpired;
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user, required this.token});

  final User user;
  final String token;
}
