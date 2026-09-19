import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_providers.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/health/presentation/home_screen.dart';
import '../features/shell/presentation/desktop_shell.dart';

/// Root route ('/'). Shows a splash while the stored token (if any) is being
/// validated at startup or while auth state is otherwise resolving.
///
/// [AppRouter]'s redirect is what actually keeps unauthenticated users off
/// this route, but that redirect only re-runs on navigation events; between
/// a state change and the next redirect check this widget can still be asked
/// to build for an unauthenticated state, so it checks explicitly rather
/// than assuming redirect already ran.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    if (authState.isLoading || authState.value is! AuthAuthenticated) {
      return const SplashScreen();
    }
    // Wide screens get the desktop layout; anything narrower keeps the
    // phone layout (a home page that pushes chats, contacts, ... as pages).
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= desktopBreakpoint ? const DesktopShell() : const HomeScreen(),
    );
  }
}
