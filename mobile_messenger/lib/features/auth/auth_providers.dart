import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import 'data/auth_api.dart';
import 'data/auth_local_storage.dart';
import 'domain/auth_state.dart';

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
    } catch (_) {
      // Token is missing, expired, or otherwise rejected by the backend.
      await storage.clearToken();
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
      return AuthAuthenticated(user: result.user, token: result.token);
    });
  }

  /// JWTs are stateless and are not revoked server-side by this endpoint -
  /// "logout" here only means the app forgets the token and returns to the
  /// unauthenticated state. See the README for details.
  Future<void> logout() async {
    await ref.read(authLocalStorageProvider).clearToken();
    state = const AsyncData(AuthUnauthenticated());
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
