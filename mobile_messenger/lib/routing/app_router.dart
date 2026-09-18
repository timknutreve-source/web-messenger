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
import '../features/chat/presentation/archived_chats_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/chat/presentation/chats_screen.dart';
import '../features/contact/domain/contact_user_summary.dart';
import '../features/contact/presentation/contacts_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import 'app_root.dart';

/// Reachable only while NOT authenticated - an authenticated user is
/// redirected away from these back to '/' (or, if their email isn't
/// verified yet, to '/verify-email').
const _unauthenticatedOnlyRoutes = {'/login', '/register', '/forgot-password', '/reset-password'};

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
      final authValue = authState.value;
      final location = state.matchedLocation;

      if (isResolving) return null;

      final isOnUnauthOnlyRoute = _unauthenticatedOnlyRoutes.contains(location);

      if (authValue is! AuthAuthenticated) {
        return isOnUnauthOnlyRoute ? null : '/login';
      }

      // Authenticated from here on. An unverified account is forced to the
      // code-entry screen regardless of where it was headed - see
      // VerifyEmailScreen - and a verified one has nothing to do there.
      final needsVerification = !authValue.user.emailVerified;
      if (needsVerification) {
        return location == '/verify-email' ? null : '/verify-email';
      }
      if (location == '/verify-email' || isOnUnauthOnlyRoute) return '/';
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
        builder: (context, state) => ResetPasswordScreen(email: state.extra as String?),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/profile/edit', builder: (context, state) => const EditProfileScreen()),
      GoRoute(path: '/contacts', builder: (context, state) => const ContactsScreen()),
      GoRoute(path: '/chats', builder: (context, state) => const ChatsScreen()),
      GoRoute(path: '/chats/archived', builder: (context, state) => const ArchivedChatsScreen()),
      GoRoute(
        path: '/chats/:chatId',
        builder: (context, state) => ChatScreen(
          chatId: state.pathParameters['chatId']!,
          otherUser: state.extra as ContactUserSummary?,
        ),
      ),
    ],
  );
});
