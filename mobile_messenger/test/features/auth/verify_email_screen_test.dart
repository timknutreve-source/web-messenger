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
  Future<void> pumpScreen(
    WidgetTester tester,
    FakeAuthApi authApi, {
    String? token = 'valid-token',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authApiProvider.overrideWithValue(authApi),
          authControllerProvider.overrideWith(
            () => FakeAuthController(const AuthUnauthenticated()),
          ),
        ],
        child: MaterialApp(home: VerifyEmailScreen(token: token)),
      ),
    );
  }

  testWidgets('shows a loading indicator while verifying', (tester) async {
    final delay = Completer<String>();
    await pumpScreen(tester, FakeAuthApi()..verifyEmailDelay = delay);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Verifying your email...'), findsOneWidget);

    delay.complete('done');
    await tester.pumpAndSettle();
  });

  testWidgets('auto-verifies on load and shows success', (tester) async {
    await pumpScreen(tester, FakeAuthApi());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verify_email_success_view')), findsOneWidget);
    expect(find.text('Your email has been verified.'), findsOneWidget);
  });

  testWidgets('shows an error for an invalid/expired token', (tester) async {
    final authApi = FakeAuthApi()
      ..verifyEmailError = const ValidationException(
        'This link is invalid or has expired. Please request a new one.',
        {},
      );
    await pumpScreen(tester, authApi);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verify_email_error_view')), findsOneWidget);
    expect(
      find.text('This link is invalid or has expired. Please request a new one.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a message when no token was supplied', (tester) async {
    await pumpScreen(tester, FakeAuthApi(), token: null);
    await tester.pumpAndSettle();

    expect(find.text('This verification link is missing or invalid.'), findsOneWidget);
  });
}
