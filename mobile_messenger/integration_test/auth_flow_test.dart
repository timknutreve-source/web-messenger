// True end-to-end test: drives the REAL app (real Dio HTTP calls, real
// flutter_secure_storage) against a REAL running backend + PostgreSQL.
//
// Requires the backend to be reachable at the configured API base URL
// (defaults to http://localhost:8080) with a clean `users` table for the
// usernames/emails used below. Run with, e.g.:
//   flutter test integration_test/auth_flow_test.dart -d linux
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/features/auth/presentation/login_screen.dart';
import 'package:mobile_messenger/features/auth/presentation/register_screen.dart';
import 'package:mobile_messenger/features/health/presentation/home_screen.dart';

/// Repeatedly pumps with real time advancing until [finder] matches or
/// [timeout] elapses. Needed because `pumpAndSettle` does not reliably wait
/// out a real network round-trip that briefly has no animating widget.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (tester.any(finder)) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsOneWidget, reason: 'timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Real secure storage persists across test runs, so each test must not
  // assume a clean slate left behind by a previous run of this suite.
  setUp(() => const FlutterSecureStorage().deleteAll());

  testWidgets('register, persisted session, logout, and log back in', (tester) async {
    final username = 'e2euser${DateTime.now().millisecondsSinceEpoch}';
    const password = 'Str0ng!Pass';
    final email = '$username@example.com';

    // Start from a clean slate: this account must not already exist.
    await tester.pumpWidget(const ProviderScope(child: MobileMessengerApp()));
    await pumpUntilFound(tester, find.byType(LoginScreen));

    // --- Register ---
    await tester.tap(find.byKey(const Key('login_go_to_register_button')));
    await pumpUntilFound(tester, find.byType(RegisterScreen));

    await tester.enterText(find.byKey(const Key('register_username_field')), username);
    await tester.enterText(find.byKey(const Key('register_email_field')), email);
    await tester.enterText(find.byKey(const Key('register_password_field')), password);
    await tester.enterText(find.byKey(const Key('register_confirmPassword_field')), password);
    await tester.tap(find.byKey(const Key('register_submit_button')));

    await pumpUntilFound(
      tester,
      find.byType(HomeScreen),
      timeout: const Duration(seconds: 20),
    );
    expect(find.text('Welcome, $username'), findsOneWidget);

    // The real backend call should resolve to a real "Connected" status.
    await pumpUntilFound(tester, find.text('Connected'));

    // --- Logout ---
    await tester.tap(find.byKey(const Key('logout_button')));
    await pumpUntilFound(tester, find.byType(LoginScreen));

    // --- Log back in with the same real credentials ---
    await tester.enterText(find.byKey(const Key('login_usernameOrEmail_field')), username);
    await tester.enterText(find.byKey(const Key('login_password_field')), password);
    await tester.tap(find.byKey(const Key('login_submit_button')));

    await pumpUntilFound(
      tester,
      find.byType(HomeScreen),
      timeout: const Duration(seconds: 20),
    );
    expect(find.text('Welcome, $username'), findsOneWidget);

    // --- Relaunch: the session should be restored from secure storage ---
    await tester.pumpWidget(Container());
    await tester.pumpWidget(const ProviderScope(child: MobileMessengerApp()));

    await pumpUntilFound(
      tester,
      find.byType(HomeScreen),
      timeout: const Duration(seconds: 20),
    );
    expect(
      find.text('Welcome, $username'),
      findsOneWidget,
      reason: 'the stored token should restore the session on relaunch',
    );

    // Leave a clean slate (no persisted session) for other tests/runs that
    // share this real device's secure storage.
    await tester.tap(find.byKey(const Key('logout_button')));
    await pumpUntilFound(tester, find.byType(LoginScreen));
  });

  testWidgets('shows a clear error for wrong login credentials', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MobileMessengerApp()));
    await pumpUntilFound(tester, find.byType(LoginScreen));

    await tester.enterText(
      find.byKey(const Key('login_usernameOrEmail_field')),
      'no-such-user-e2e',
    );
    await tester.enterText(find.byKey(const Key('login_password_field')), 'WhoKnows1!');
    await tester.tap(find.byKey(const Key('login_submit_button')));

    await pumpUntilFound(tester, find.textContaining('Invalid credentials'));
    expect(find.byType(LoginScreen), findsOneWidget, reason: 'stays on login after a failure');
  });
}
