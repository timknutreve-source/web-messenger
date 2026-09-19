import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_exception.dart';
import '../../core/network/dio_provider.dart';
import '../chat/chat_providers.dart';
import '../contact/contact_providers.dart';
import '../group/group_providers.dart';
import '../shell/workspace_providers.dart';
import 'data/auth_api.dart';
import 'data/auth_local_storage.dart';
import 'domain/auth_state.dart';
import 'domain/user.dart';

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(dioProvider)));

final authLocalStorageProvider = Provider<AuthLocalStorage>((ref) => AuthLocalStorage());

/// Holds the app's authentication state.
///
/// On first read this restores any token saved from a previous launch and
/// validates it against the backend, so the user stays signed in between
/// app launches without re-entering credentials.
class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final storage = ref.read(authLocalStorageProvider);
    final String? token;
    try {
      token = await storage.readToken();
    } catch (_) {
      return const AuthUnauthenticated();
    }

    if (token == null) {
      return const AuthUnauthenticated();
    }

    try {
      final user = await ref.read(authApiProvider).fetchCurrentUser(token);
      return AuthAuthenticated(user: user, token: token);
    } on InvalidCredentialsException {
      // The backend explicitly rejected this token (expired/invalid) - only
      // this case actually proves the stored token is no good, so only here
      // is it safe to discard it.
      await storage.clearToken();
      return const AuthUnauthenticated();
    } catch (_) {
      // Couldn't reach the backend at all, or it errored (network down,
      // timeout, 5xx, ...) - this says nothing about whether the token
      // itself is still valid, so it must be kept: clearing it here would
      // force a full re-login purely because of a transient connectivity
      // problem, which is not a "session expired" or "user logged out" and
      // must not end the session. A later launch (or a future in-app retry)
      // gets to try validating the same token again once the backend is
      // reachable.
      return const AuthUnauthenticated();
    }
  }

  Future<void> login({required String usernameOrEmail, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref.read(authApiProvider).login(
            usernameOrEmail: usernameOrEmail,
            password: password,
          );
      await ref.read(authLocalStorageProvider).saveToken(result.token);
      _resetPerAccountState();
      return AuthAuthenticated(user: result.user, token: result.token);
    });
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref.read(authApiProvider).register(
            username: username,
            email: email,
            password: password,
          );
      await ref.read(authLocalStorageProvider).saveToken(result.token);
      _resetPerAccountState();
      return AuthAuthenticated(user: result.user, token: result.token);
    });
  }

  /// Signs out of *this* device only. The local session is cleared straight
  /// away (so the UI never waits on the network to leave), and the server is
  /// told to revoke this device's session best-effort in the background -
  /// other devices signed in to the same account keep working either way.
  Future<void> logout() async {
    final current = state.value;
    final token = current is AuthAuthenticated ? current.token : null;
    await ref.read(authLocalStorageProvider).clearToken();
    _resetPerAccountState();
    state = const AsyncData(AuthUnauthenticated());
    if (token != null) {
      unawaited(ref.read(authApiProvider).logout(token).catchError((Object _) {}));
    }
  }

  /// Called when the server rejects the current session (HTTP 401 on an
  /// authenticated call): it expired, or was signed out remotely. Clears the
  /// local session and lands on the login screen with an explanation.
  Future<void> handleSessionExpired() async {
    if (state.value is! AuthAuthenticated) return;
    await ref.read(authLocalStorageProvider).clearToken();
    _resetPerAccountState();
    state = const AsyncData(AuthUnauthenticated(sessionExpired: true));
  }

  /// Invalidates every provider that caches data scoped to "whoever is
  /// currently logged in" - contacts, pending invitations, and chats are
  /// all plain (non-autoDispose) providers that, left alone, would keep
  /// showing whichever account's data they last loaded.
  ///
  /// This matters on both sides of a session change: on login/register, it's
  /// what makes a pending invitation sent while the recipient was logged out
  /// (or logged in as no one yet) show up immediately instead of only after
  /// an app restart - previously nothing ever told these providers a new
  /// session had started, so a stale (often empty) fetch from earlier in the
  /// process could linger indefinitely. On logout, it's what stops the next
  /// person who logs in on this device from ever seeing a flash of the
  /// previous account's contacts/chats before their own fetch completes.
  void _resetPerAccountState() {
    ref.invalidate(contactsControllerProvider);
    ref.invalidate(pendingInvitationsControllerProvider);
    ref.invalidate(pendingGroupInvitationsControllerProvider);
    ref.invalidate(workspaceControllerProvider);
    ref.invalidate(chatsControllerProvider);
    ref.invalidate(archivedChatsControllerProvider);
  }

  /// Updates the cached user (e.g. after a profile edit) without touching
  /// the session token or re-authenticating. No-ops if not authenticated.
  void updateUser(User updatedUser) {
    final current = state.value;
    if (current is AuthAuthenticated) {
      state = AsyncData(AuthAuthenticated(user: updatedUser, token: current.token));
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
