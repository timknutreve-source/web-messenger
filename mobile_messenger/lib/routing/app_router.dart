import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_providers.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/contact/presentation/contacts_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import 'app_root.dart';

/// Reachable only while NOT authenticated - an authenticated user is
/// redirected away from these back to '/'.
const _unauthenticatedOnlyRoutes = {'/login', '/register', '/forgot-password', '/reset-password'};

/// Reachable regardless of auth state, with no redirect either way. A
/// verification link may legitimately be opened whether or not the user
/// happens to already be logged in.
const _publicRoutes = {'/verify-email'};

/// Bridges Riverpod's [authControllerProvider] to go_router's
/// [GoRouter.refreshListenable], so the router re-evaluates its redirect
/// whenever auth state changes (login, logout, or the startup token check
/// resolving).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}

/// Builds the app's router. Kept as a plain `Provider` (not autoDispose) so
/// the same [GoRouter] instance lives for the app's lifetime and never resets
/// the navigation stack.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final isResolving = authState.isLoading;
      final isAuthenticated = authState.value is AuthAuthenticated;
      final location = state.matchedLocation;

      if (isResolving) return null;
      if (_publicRoutes.contains(location)) return null;

      final isOnUnauthOnlyRoute = _unauthenticatedOnlyRoutes.contains(location);
      if (!isAuthenticated && !isOnUnauthOnlyRoute) return '/login';
      if (isAuthenticated && isOnUnauthOnlyRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AppRoot()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) => VerifyEmailScreen(token: state.uri.queryParameters['token']),
      ),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/profile/edit', builder: (context, state) => const EditProfileScreen()),
      GoRoute(path: '/contacts', builder: (context, state) => const ContactsScreen()),
    ],
  );
});
