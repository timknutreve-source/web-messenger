import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/auth/presentation/verify_email_screen.dart';

import '../../support/fakes.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, FakeAuthApi authApi) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authApiProvider.overrideWithValue(authApi),
          authControllerProvider.overrideWith(
            () => FakeAuthController(
              AuthAuthenticated(user: sampleUser.copyWith(emailVerified: false), token: 'tok'),
            ),
          ),
        ],
        child: const MaterialApp(home: VerifyEmailScreen()),
      ),
    );
    // Lets the FakeAuthController's async build() resolve before a test
    // interacts with the form - otherwise `_submit`'s authControllerProvider
    // read can still see AsyncLoading (value == null) on the very first frame.
    await tester.pumpAndSettle();
  }

  Future<void> enterAndSubmitCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('verify_email_code_field')), code);
    await tester.tap(find.byKey(const Key('verify_email_submit_button')));
  }

  testWidgets('shows the code entry form', (tester) async {
    await pumpScreen(tester, FakeAuthApi());
    await tester.pumpAndSettle();

    expect(find.text('We sent a verification code to your email address.'), findsOneWidget);
    expect(find.byKey(const Key('verify_email_code_field')), findsOneWidget);
  });

  testWidgets('rejects a code that is not 6 digits', (tester) async {
    await pumpScreen(tester, FakeAuthApi());
    await enterAndSubmitCode(tester, '123');
    await tester.pumpAndSettle();

    expect(find.text('Enter the 6-digit code'), findsOneWidget);
  });

  testWidgets('shows a loading state while verifying', (tester) async {
    final delay = Completer<String>();
    await pumpScreen(tester, FakeAuthApi()..verifyEmailDelay = delay);

    await enterAndSubmitCode(tester, '482731');
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    delay.complete('done');
    await tester.pumpAndSettle();
  });

  testWidgets('shows success on a correct code', (tester) async {
    await pumpScreen(tester, FakeAuthApi());
    await enterAndSubmitCode(tester, '482731');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verify_email_success_view')), findsOneWidget);
    expect(find.text('Your email has been verified.'), findsOneWidget);
  });

  testWidgets('a correct code updates the cached user as verified', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(FakeAuthApi()),
        authControllerProvider.overrideWith(
          () => FakeAuthController(
            AuthAuthenticated(user: sampleUser.copyWith(emailVerified: false), token: 'tok'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: VerifyEmailScreen())),
    );

    await enterAndSubmitCode(tester, '482731');
    await tester.pumpAndSettle();

    final state = container.read(authControllerProvider).value;
    expect(state, isA<AuthAuthenticated>());
    expect((state as AuthAuthenticated).user.emailVerified, isTrue);
  });

  testWidgets('shows an error for a wrong/expired code', (tester) async {
    final authApi = FakeAuthApi()
      ..verifyEmailError = const ValidationException(
        'This code is invalid or has expired. Please request a new one.',
        {},
      );
    await pumpScreen(tester, authApi);
    await enterAndSubmitCode(tester, '482731');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verify_email_error_message')), findsOneWidget);
    expect(
      find.text('This code is invalid or has expired. Please request a new one.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('verify_email_success_view')), findsNothing);
  });

  testWidgets('resending shows loading then success feedback', (tester) async {
    final delay = Completer<String>();
    final authApi = FakeAuthApi()..resendVerificationDelay = delay;
    await pumpScreen(tester, authApi);

    await tester.tap(find.byKey(const Key('verify_email_resend_button')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('verify_email_resend_button')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    delay.complete('Verification email sent.');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verify_email_resend_feedback')), findsOneWidget);
    expect(find.text('Verification email sent.'), findsOneWidget);
  });

  testWidgets('resending shows an error message on failure', (tester) async {
    final authApi = FakeAuthApi()..resendVerificationError = const NetworkUnavailableException();
    await pumpScreen(tester, authApi);

    await tester.tap(find.byKey(const Key('verify_email_resend_button')));
    await tester.pumpAndSettle();

    expect(find.text('Unable to connect. Please try again.'), findsOneWidget);
  });

  // This screen is only ever reached via a forced router redirect (an
  // unverified user is sent here regardless of where they were headed), so
  // there is nothing on the navigation stack to pop back to - the back
  // button/gesture instead ends the session, which is what actually gets
  // the user "back" to login without looping back to this same screen.
  group('back navigation', () {
    Future<ProviderContainer> pumpWithRealLogout(WidgetTester tester) async {
      final storage = FakeAuthLocalStorage();
      await storage.saveToken('tok');
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(FakeAuthApi()),
          authLocalStorageProvider.overrideWithValue(storage),
          authControllerProvider.overrideWith(
            () => FakeAuthController(
              AuthAuthenticated(user: sampleUser.copyWith(emailVerified: false), token: 'tok'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MaterialApp(home: VerifyEmailScreen())),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('shows a back button', (tester) async {
      await pumpScreen(tester, FakeAuthApi());

      expect(find.byKey(const Key('verify_email_back_button')), findsOneWidget);
    });

    testWidgets('tapping the back button ends the session', (tester) async {
      final container = await pumpWithRealLogout(tester);

      await tester.tap(find.byKey(const Key('verify_email_back_button')));
      await tester.pumpAndSettle();

      expect(container.read(authControllerProvider).value, isA<AuthUnauthenticated>());
      expect(await container.read(authLocalStorageProvider).readToken(), isNull);
    });

    testWidgets('the system back gesture also ends the session instead of exiting the app',
        (tester) async {
      final container = await pumpWithRealLogout(tester);

      final didPop = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(didPop, isTrue, reason: 'the screen must intercept the pop, never let it fall through');
      expect(container.read(authControllerProvider).value, isA<AuthUnauthenticated>());
    });
  });
}
