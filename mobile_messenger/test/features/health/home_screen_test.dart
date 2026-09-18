import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/domain/chat_summary.dart';
import 'package:mobile_messenger/features/contact/contact_providers.dart';
import 'package:mobile_messenger/features/contact/domain/pending_invitation.dart';
import 'package:mobile_messenger/features/health/health_providers.dart';
import 'package:mobile_messenger/features/health/presentation/home_screen.dart';

import '../../support/fakes.dart';

void main() {
  final authenticatedOverride = authControllerProvider.overrideWith(
    () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
  );

  Finder badgeTextWithin(Key iconButtonKey) => find.descendant(
        of: find.byKey(iconButtonKey),
        matching: find.byType(Text),
      );

  testWidgets('shows no badges when there are no unread messages or pending invitations', (tester) async {
    final chatApi = FakeChatApi()..activeChatsResult = [];
    final contactApi = FakeContactApi()..pendingResult = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          healthApiProvider.overrideWithValue(FakeHealthApi()),
          chatApiProvider.overrideWithValue(chatApi),
          contactApiProvider.overrideWithValue(contactApi),
          chatWebSocketClientFactoryProvider.overrideWithValue(() => FakeChatWebSocketClient()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(badgeTextWithin(const Key('view_chats_button')), findsNothing);
    expect(badgeTextWithin(const Key('view_contacts_button')), findsNothing);
  });

  testWidgets('shows the total unread message count and pending invitation count as badges', (tester) async {
    final chatApi = FakeChatApi()
      ..activeChatsResult = [
        sampleChatSummary.copyWith(unreadCount: 2),
        ChatSummary(
          id: 'chat-2',
          otherUser: sampleContactUser,
          lastActivityAt: DateTime.utc(2026, 1, 2),
          archived: false,
          unreadCount: 3,
        ),
      ];
    final contactApi = FakeContactApi()
      ..pendingResult = [
        PendingInvitation(id: 'inv-1', sender: sampleContactUser, createdAt: DateTime.utc(2026, 1, 1)),
        PendingInvitation(id: 'inv-2', sender: sampleContactUser, createdAt: DateTime.utc(2026, 1, 1)),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          healthApiProvider.overrideWithValue(FakeHealthApi()),
          chatApiProvider.overrideWithValue(chatApi),
          contactApiProvider.overrideWithValue(contactApi),
          chatWebSocketClientFactoryProvider.overrideWithValue(() => FakeChatWebSocketClient()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Total unread across both chats (2 + 3 = 5).
    expect(
        find.descendant(of: find.byKey(const Key('view_chats_button')), matching: find.text('5')),
        findsOneWidget);
    // Two pending invitations.
    expect(
        find.descendant(of: find.byKey(const Key('view_contacts_button')), matching: find.text('2')),
        findsOneWidget);
  });

  testWidgets('shows the welcome message for the logged-in user', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, healthApiProvider.overrideWithValue(FakeHealthApi())],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Welcome, alice'), findsOneWidget);
  });

  testWidgets('never shows backend/server/technical status in the UI', (tester) async {
    // The home screen must read as a plain messenger app, not an internal
    // ops dashboard - no "Backend status" panel, no "Connected"/"Connection
    // failed" wording, regardless of whether the (unused) health check
    // would have succeeded or failed.
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

    expect(find.textContaining('Backend'), findsNothing);
    expect(find.textContaining('backend'), findsNothing);
    expect(find.textContaining('server'), findsNothing);
    expect(find.text('Connected'), findsNothing);
    expect(find.text('Connection failed'), findsNothing);
  });

  final unverifiedOverride = authControllerProvider.overrideWith(
    () => FakeAuthController(
      AuthAuthenticated(user: sampleUser.copyWith(emailVerified: false), token: 'tok'),
    ),
  );

  testWidgets('shows an unverified-email notice for an unverified account', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [unverifiedOverride, healthApiProvider.overrideWithValue(FakeHealthApi())],
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
          unverifiedOverride,
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
          unverifiedOverride,
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
      find.text('Unable to connect. Please try again.'),
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
