import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/auth/presentation/forgot_password_screen.dart';
import 'package:mobile_messenger/features/auth/presentation/login_screen.dart';
import 'package:mobile_messenger/features/auth/presentation/verify_email_screen.dart';
import 'package:mobile_messenger/features/contact/contact_providers.dart';
import 'package:mobile_messenger/features/contact/presentation/contacts_screen.dart';
import 'package:mobile_messenger/features/health/health_providers.dart';
import 'package:mobile_messenger/features/health/presentation/home_screen.dart';
import 'package:mobile_messenger/features/profile/profile_providers.dart';
import 'package:mobile_messenger/routing/app_router.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('an unauthenticated user is redirected to the login screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(const AuthUnauthenticated()),
          ),
        ],
        child: const MobileMessengerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('an authenticated user reaches home and cannot navigate back to login',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);

    container.read(routerProvider).go('/login');
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('an unauthenticated user can reach forgot-password', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(const AuthUnauthenticated()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/forgot-password');
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });

  testWidgets('an authenticated user is redirected away from forgot-password', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
        profileApiProvider.overrideWithValue(FakeProfileApi()..profile = sampleUser),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/forgot-password');
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
  });

  testWidgets('verify-email is reachable for an unauthenticated user', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(const AuthUnauthenticated()),
        ),
        authApiProvider.overrideWithValue(FakeAuthApi()..verifyEmailResult = 'verified'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/verify-email?token=abc');
    await tester.pumpAndSettle();

    expect(find.byType(VerifyEmailScreen), findsOneWidget);
  });

  testWidgets('verify-email is reachable for an already-authenticated user (not redirected away)',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
        authApiProvider.overrideWithValue(FakeAuthApi()..verifyEmailResult = 'verified'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/verify-email?token=abc');
    await tester.pumpAndSettle();

    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('an unauthenticated user is redirected away from contacts', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(const AuthUnauthenticated()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/contacts');
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ContactsScreen), findsNothing);
  });

  testWidgets('an authenticated user can reach contacts', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
        contactsControllerProvider.overrideWith(() => FakeContactsController([])),
        pendingInvitationsControllerProvider.overrideWith(() => FakePendingInvitationsController([])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/contacts');
    await tester.pumpAndSettle();

    expect(find.byType(ContactsScreen), findsOneWidget);
  });
}
