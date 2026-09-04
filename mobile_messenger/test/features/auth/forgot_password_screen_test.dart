import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/presentation/forgot_password_screen.dart';

import '../../support/fakes.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, FakeAuthApi authApi) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authApiProvider.overrideWithValue(authApi)],
        child: const MaterialApp(home: ForgotPasswordScreen()),
      ),
    );
  }

  testWidgets('rejects an empty email', (tester) async {
    await pumpScreen(tester, FakeAuthApi());

    await tester.tap(find.byKey(const Key('forgot_password_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Email is required'), findsOneWidget);
  });

  testWidgets('rejects an invalid email', (tester) async {
    await pumpScreen(tester, FakeAuthApi());

    await tester.enterText(find.byKey(const Key('forgot_password_email_field')), 'not-an-email');
    await tester.tap(find.byKey(const Key('forgot_password_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('shows a loading state while submitting', (tester) async {
    final delay = Completer<String>();
    final authApi = FakeAuthApi()..forgotPasswordDelay = delay;
    await pumpScreen(tester, authApi);

    await tester.enterText(find.byKey(const Key('forgot_password_email_field')), 'alice@example.com');
    await tester.tap(find.byKey(const Key('forgot_password_submit_button')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    delay.complete('done');
    await tester.pumpAndSettle();
  });

  testWidgets('shows the generic success message regardless of whether the email exists',
      (tester) async {
    final authApi = FakeAuthApi();
    await pumpScreen(tester, authApi);

    await tester.enterText(find.byKey(const Key('forgot_password_email_field')), 'alice@example.com');
    await tester.tap(find.byKey(const Key('forgot_password_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgot_password_success_message')), findsOneWidget);
    expect(
      find.text('If that email is registered, password reset instructions have been sent.'),
      findsOneWidget,
    );
  });

  testWidgets('shows an error message on network failure', (tester) async {
    final authApi = FakeAuthApi()..forgotPasswordError = const NetworkUnavailableException();
    await pumpScreen(tester, authApi);

    await tester.enterText(find.byKey(const Key('forgot_password_email_field')), 'alice@example.com');
    await tester.tap(find.byKey(const Key('forgot_password_submit_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not reach the backend server. Make sure it is running.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('forgot_password_success_message')), findsNothing);
  });
}
