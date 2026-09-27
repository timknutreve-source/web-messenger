import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/presentation/reset_password_screen.dart';

import '../../support/fakes.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    FakeAuthApi authApi, {
    String? email = 'alice@example.com',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authApiProvider.overrideWithValue(authApi)],
        child: MaterialApp(home: ResetPasswordScreen(email: email)),
      ),
    );
  }

  Future<void> fillValidForm(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('reset_password_code_field')), '847291');
    await tester.enterText(find.byKey(const Key('reset_password_new_password_field')), 'Str0ng!Pass');
    await tester.enterText(find.byKey(const Key('reset_password_confirm_password_field')), 'Str0ng!Pass');
  }

  testWidgets('shows an error and no form when the email is missing', (tester) async {
    await pumpScreen(tester, FakeAuthApi(), email: null);
    await tester.pumpAndSettle();

    expect(find.text('This password reset session is missing or invalid.'), findsOneWidget);
    expect(find.byKey(const Key('reset_password_new_password_field')), findsNothing);
  });

  testWidgets('rejects a code that is not 6 digits', (tester) async {
    await pumpScreen(tester, FakeAuthApi());

    await tester.enterText(find.byKey(const Key('reset_password_code_field')), '12');
    await tester.enterText(find.byKey(const Key('reset_password_new_password_field')), 'Str0ng!Pass');
    await tester.enterText(find.byKey(const Key('reset_password_confirm_password_field')), 'Str0ng!Pass');
    await tester.ensureVisible(find.byKey(const Key('reset_password_submit_button')));
    await tester.tap(find.byKey(const Key('reset_password_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Enter the 6-digit code'), findsOneWidget);
  });

  testWidgets('rejects a weak password', (tester) async {
    await pumpScreen(tester, FakeAuthApi());

    await tester.enterText(find.byKey(const Key('reset_password_code_field')), '847291');
    await tester.enterText(find.byKey(const Key('reset_password_new_password_field')), 'weak');
    await tester.enterText(find.byKey(const Key('reset_password_confirm_password_field')), 'weak');
    await tester.ensureVisible(find.byKey(const Key('reset_password_submit_button')));
    await tester.tap(find.byKey(const Key('reset_password_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Password does not meet all requirements'), findsOneWidget);
  });

  testWidgets('rejects mismatched confirmation', (tester) async {
    await pumpScreen(tester, FakeAuthApi());

    await tester.enterText(find.byKey(const Key('reset_password_code_field')), '847291');
    await tester.enterText(
      find.byKey(const Key('reset_password_new_password_field')),
      'Str0ng!Pass',
    );
    await tester.enterText(
      find.byKey(const Key('reset_password_confirm_password_field')),
      'Different1!',
    );
    await tester.ensureVisible(find.byKey(const Key('reset_password_submit_button')));
    await tester.tap(find.byKey(const Key('reset_password_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('shows a loading state while submitting', (tester) async {
    final delay = Completer<String>();
    await pumpScreen(tester, FakeAuthApi()..resetPasswordDelay = delay);

    await fillValidForm(tester);
    await tester.ensureVisible(find.byKey(const Key('reset_password_submit_button')));
    await tester.tap(find.byKey(const Key('reset_password_submit_button')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    delay.complete('done');
    await tester.pumpAndSettle();
  });

  testWidgets('shows success and a way back to login after a successful reset', (tester) async {
    await pumpScreen(tester, FakeAuthApi());

    await fillValidForm(tester);
    await tester.ensureVisible(find.byKey(const Key('reset_password_submit_button')));
    await tester.tap(find.byKey(const Key('reset_password_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reset_password_success_view')), findsOneWidget);
    expect(find.text('Your password has been reset. You can now log in.'), findsOneWidget);
    expect(find.text('Back to login'), findsOneWidget);
  });

  testWidgets('shows an error for an invalid/expired code', (tester) async {
    final authApi = FakeAuthApi()
      ..resetPasswordError = const ValidationException(
        'This code is invalid or has expired. Please request a new one.',
        {},
      );
    await pumpScreen(tester, authApi);

    await fillValidForm(tester);
    await tester.ensureVisible(find.byKey(const Key('reset_password_submit_button')));
    await tester.tap(find.byKey(const Key('reset_password_submit_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('This code is invalid or has expired. Please request a new one.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reset_password_success_view')), findsNothing);
  });
}
