import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_providers.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import 'app_root.dart';

const _unauthenticatedRoutes = {'/login', '/register'};

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
      final isOnUnauthenticatedRoute = _unauthenticatedRoutes.contains(state.matchedLocation);

      if (isResolving) return null;

      if (!isAuthenticated && !isOnUnauthenticatedRoute) return '/login';
      if (isAuthenticated && isOnUnauthenticatedRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AppRoot()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
    ],
  );
});
