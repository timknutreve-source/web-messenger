import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/health/health_providers.dart';
import 'package:mobile_messenger/features/health/presentation/home_screen.dart';

import '../../support/fakes.dart';

void main() {
  final authenticatedOverride = authControllerProvider.overrideWith(
    () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
  );

  testWidgets('shows connected state when the backend is reachable', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, healthApiProvider.overrideWithValue(FakeHealthApi())],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Welcome, alice'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('shows error state and can retry when the backend is unreachable', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          healthApiProvider.overrideWithValue(
            FakeHealthApi(error: const NetworkUnavailableException()),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
    expect(
      find.text('Could not reach the backend server. Make sure it is running.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
  });

  testWidgets('shows an unverified-email notice for an unverified account', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, healthApiProvider.overrideWithValue(FakeHealthApi())],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Your email is not verified yet'), findsOneWidget);
  });

  testWidgets('resending verification shows loading then success feedback', (tester) async {
    final delay = Completer<String>();
    final authApi = FakeAuthApi()..resendVerificationDelay = delay;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          healthApiProvider.overrideWithValue(FakeHealthApi()),
          authApiProvider.overrideWithValue(authApi),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('resend_verification_button')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('resend_verification_button')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    delay.complete('Verification email sent.');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('resend_verification_feedback')), findsOneWidget);
    expect(find.text('Verification email sent.'), findsOneWidget);
  });

  testWidgets('resending verification shows an error message on failure', (tester) async {
    final authApi = FakeAuthApi()..resendVerificationError = const NetworkUnavailableException();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          healthApiProvider.overrideWithValue(FakeHealthApi()),
          authApiProvider.overrideWithValue(authApi),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('resend_verification_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not reach the backend server. Make sure it is running.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping logout clears the session', (tester) async {
    final storage = FakeAuthLocalStorage();
    await storage.saveToken('tok');
    final container = ProviderContainer(
      overrides: [
        authenticatedOverride,
        healthApiProvider.overrideWithValue(FakeHealthApi()),
        authLocalStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider).value, isA<AuthUnauthenticated>());
    expect(await storage.readToken(), isNull);
  });
}
