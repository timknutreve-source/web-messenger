import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/auth/presentation/forgot_password_screen.dart';
import 'package:mobile_messenger/features/auth/presentation/login_screen.dart';
import 'package:mobile_messenger/features/auth/presentation/verify_email_screen.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/presentation/chat_screen.dart';
import 'package:mobile_messenger/features/chat/presentation/chats_screen.dart';
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
        chatsControllerProvider.overrideWith(() => FakeChatsController([])),
        pendingInvitationsControllerProvider.overrideWith(() => FakePendingInvitationsController([])),
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
        chatsControllerProvider.overrideWith(() => FakeChatsController([])),
        pendingInvitationsControllerProvider.overrideWith(() => FakePendingInvitationsController([])),
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

  testWidgets('an unauthenticated user is redirected away from verify-email', (tester) async {
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

    container.read(routerProvider).go('/verify-email');
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(VerifyEmailScreen), findsNothing);
  });

  testWidgets('a verified authenticated user is redirected away from verify-email (nothing to verify)',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
        chatsControllerProvider.overrideWith(() => FakeChatsController([])),
        pendingInvitationsControllerProvider.overrideWith(() => FakePendingInvitationsController([])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/verify-email');
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(VerifyEmailScreen), findsNothing);
  });

  testWidgets('an unverified authenticated user is forced to verify-email regardless of destination',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(
            AuthAuthenticated(user: sampleUser.copyWith(emailVerified: false), token: 'tok'),
          ),
        ),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VerifyEmailScreen), findsOneWidget,
        reason: 'even the default "/" destination redirects to verify-email while unverified');

    container.read(routerProvider).go('/contacts');
    await tester.pumpAndSettle();

    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    expect(find.byType(ContactsScreen), findsNothing);
  });

  testWidgets(
      "verify-email's back button ends up on login, not back on verify-email (no redirect loop)",
      (tester) async {
    final storage = FakeAuthLocalStorage();
    await storage.saveToken('tok');
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(
            AuthAuthenticated(user: sampleUser.copyWith(emailVerified: false), token: 'tok'),
          ),
        ),
        authLocalStorageProvider.overrideWithValue(storage),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VerifyEmailScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('verify_email_back_button')));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(VerifyEmailScreen), findsNothing);
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
        chatsControllerProvider.overrideWith(() => FakeChatsController([])),
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

  testWidgets('an unauthenticated user is redirected away from chats', (tester) async {
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

    container.read(routerProvider).go('/chats');
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ChatsScreen), findsNothing);
  });

  testWidgets('an authenticated user can reach chats', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
        chatsControllerProvider.overrideWith(() => FakeChatsController([])),
        pendingInvitationsControllerProvider.overrideWith(() => FakePendingInvitationsController([])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/chats');
    await tester.pumpAndSettle();

    expect(find.byType(ChatsScreen), findsOneWidget);
  });

  testWidgets('an unauthenticated user is redirected away from a chat conversation', (tester) async {
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

    container.read(routerProvider).go('/chats/chat-1');
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('an authenticated user can reach a chat conversation', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        healthApiProvider.overrideWithValue(FakeHealthApi()),
        messageApiProvider.overrideWithValue(FakeMessageApi()),
        chatWebSocketClientFactoryProvider.overrideWithValue(() => FakeChatWebSocketClient()),
        chatsControllerProvider.overrideWith(() => FakeChatsController([])),
        pendingInvitationsControllerProvider.overrideWith(() => FakePendingInvitationsController([])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MobileMessengerApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/chats/chat-1');
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
  });
}
