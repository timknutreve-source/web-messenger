import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/auth/presentation/login_screen.dart';
import 'package:mobile_messenger/features/auth/presentation/register_screen.dart';
import 'package:mobile_messenger/features/health/health_providers.dart';

import '../../support/fakes.dart';

void main() {
  Future<ProviderContainer> pumpAppOnLoginScreen(WidgetTester tester, {FakeAuthApi? authApi}) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(const AuthUnauthenticated()),
        ),
        authApiProvider.overrideWithValue(authApi ?? FakeAuthApi()),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    return container;
  }

  Future<void> goToRegister(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('login_go_to_register_button')));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  }

  testWidgets('the register screen is reachable from login and has a working UI back button',
      (tester) async {
    await pumpAppOnLoginScreen(tester);
    await goToRegister(tester);

    expect(find.byTooltip('Back'), findsOneWidget,
        reason: 'register must be pushed (not go()) onto the stack so a back destination exists');

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('the Android system back button returns to login from the register screen',
      (tester) async {
    await pumpAppOnLoginScreen(tester);
    await goToRegister(tester);

    final didPop = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(didPop, isTrue);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('a validation error keeps the user on the register screen with back still working',
      (tester) async {
    await pumpAppOnLoginScreen(tester);
    await goToRegister(tester);

    await tester.ensureVisible(find.byKey(const Key('register_submit_button')));
    await tester.tap(find.byKey(const Key('register_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget,
        reason: 'a client-side validation failure must not navigate away');
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  Future<void> fillValidForm(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('register_username_field')), 'newuser');
    await tester.enterText(find.byKey(const Key('register_email_field')), 'newuser@example.com');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'StrongPass123!');
    await tester.enterText(find.byKey(const Key('register_confirmPassword_field')), 'StrongPass123!');
  }

  testWidgets('a duplicate username/email error keeps the user on the register screen, back still works',
      (tester) async {
    final authApi = FakeAuthApi()..registerError = const DuplicateResourceException();
    await pumpAppOnLoginScreen(tester, authApi: authApi);
    await goToRegister(tester);
    await fillValidForm(tester);

    await tester.ensureVisible(find.byKey(const Key('register_submit_button')));
    await tester.tap(find.byKey(const Key('register_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('That account already exists.'), findsOneWidget);
    expect(find.byType(RegisterScreen), findsOneWidget,
        reason: 'a server error must not strand navigation - the screen stays, with a working back');

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a network error keeps the user on the register screen, back still works', (tester) async {
    final authApi = FakeAuthApi()..registerError = const NetworkUnavailableException();
    await pumpAppOnLoginScreen(tester, authApi: authApi);
    await goToRegister(tester);
    await fillValidForm(tester);

    await tester.ensureVisible(find.byKey(const Key('register_submit_button')));
    await tester.tap(find.byKey(const Key('register_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Unable to connect. Please try again.'), findsOneWidget);

    final didPop = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(didPop, isTrue);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a server error keeps the user on the register screen, back still works', (tester) async {
    final authApi = FakeAuthApi()..registerError = const ServerErrorException();
    await pumpAppOnLoginScreen(tester, authApi: authApi);
    await goToRegister(tester);
    await fillValidForm(tester);

    await tester.ensureVisible(find.byKey(const Key('register_submit_button')));
    await tester.tap(find.byKey(const Key('register_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong on our end. Please try again later.'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a weak password is rejected locally without ever navigating away', (tester) async {
    await pumpAppOnLoginScreen(tester);
    await goToRegister(tester);

    await tester.enterText(find.byKey(const Key('register_username_field')), 'newuser');
    await tester.enterText(find.byKey(const Key('register_email_field')), 'newuser@example.com');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'weak');
    await tester.enterText(find.byKey(const Key('register_confirmPassword_field')), 'weak');

    await tester.ensureVisible(find.byKey(const Key('register_submit_button')));
    await tester.tap(find.byKey(const Key('register_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('tapping "Already have an account?" returns to login', (tester) async {
    await pumpAppOnLoginScreen(tester);
    await goToRegister(tester);

    await tester.ensureVisible(find.byKey(const Key('register_go_to_login_button')));
    await tester.tap(find.byKey(const Key('register_go_to_login_button')));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });
}
