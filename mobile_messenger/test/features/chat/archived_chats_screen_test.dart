import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/domain/chat_summary.dart';
import 'package:mobile_messenger/features/chat/presentation/archived_chats_screen.dart';
import 'package:mobile_messenger/features/contact/domain/contact_user_summary.dart';

import '../../support/fakes.dart';

void main() {
  final authenticatedOverride = authControllerProvider.overrideWith(
    () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
  );

  testWidgets('renders the archived chats screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          archivedChatsControllerProvider.overrideWith(() => FakeArchivedChatsController([])),
        ],
        child: const MaterialApp(home: ArchivedChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archived_chats_screen')), findsOneWidget);
  });

  testWidgets('shows a loading indicator while archived chats are loading', (tester) async {
    final delay = Completer<List<ChatSummary>>();
    final chatApi = FakeChatApi()..archivedChatsDelay = delay;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, chatApiProvider.overrideWithValue(chatApi)],
        child: const MaterialApp(home: ArchivedChatsScreen()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    delay.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('shows an empty state when there are no archived chats', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          archivedChatsControllerProvider.overrideWith(() => FakeArchivedChatsController([])),
        ],
        child: const MaterialApp(home: ArchivedChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archived_chats_empty_view')), findsOneWidget);
  });

  testWidgets('renders an archived chat once loaded', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          archivedChatsControllerProvider.overrideWith(() => FakeArchivedChatsController([sampleChatSummary])),
        ],
        child: const MaterialApp(home: ArchivedChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('archived_chat_tile_${sampleChatSummary.id}')), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets('shows an error state with retry when loading archived chats fails', (tester) async {
    final chatApi = FakeChatApi()..archivedChatsError = const NetworkUnavailableException();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, chatApiProvider.overrideWithValue(chatApi)],
        child: const MaterialApp(home: ArchivedChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(const NetworkUnavailableException().message), findsOneWidget);
  });

  testWidgets('unarchiving a chat removes it from the archived list', (tester) async {
    final chatApi = FakeChatApi();
    final container = ProviderContainer(
      overrides: [
        authenticatedOverride,
        chatApiProvider.overrideWithValue(chatApi),
        archivedChatsControllerProvider.overrideWith(() => FakeArchivedChatsController([sampleChatSummary])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: ArchivedChatsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('unarchive_chat_button_${sampleChatSummary.id}')));
    await tester.pumpAndSettle();

    expect(chatApi.unarchivedChatIds, [sampleChatSummary.id]);
    expect(find.byKey(Key('archived_chat_tile_${sampleChatSummary.id}')), findsNothing);
    expect(find.byKey(const Key('archived_chats_empty_view')), findsOneWidget);
  });

  testWidgets(
      'unarchiving one of two chats does not leave the other one stuck showing a spinner '
      '(regression: tiles must be keyed by chat id, not list position)', (tester) async {
    const secondUser = ContactUserSummary(
      id: 'user-3',
      username: 'carol',
      email: 'carol@example.com',
      avatarFileName: null,
    );
    final secondChat = ChatSummary(
      id: 'chat-2',
      otherUser: secondUser,
      lastActivityAt: DateTime.utc(2026, 1, 2),
      archived: true,
    );
    final chatApi = FakeChatApi();
    final container = ProviderContainer(
      overrides: [
        authenticatedOverride,
        chatApiProvider.overrideWithValue(chatApi),
        archivedChatsControllerProvider.overrideWith(
          () => FakeArchivedChatsController([sampleChatSummary, secondChat]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: ArchivedChatsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('unarchive_chat_button_${sampleChatSummary.id}')));
    await tester.pumpAndSettle();

    expect(chatApi.unarchivedChatIds, [sampleChatSummary.id]);
    expect(find.byKey(Key('archived_chat_tile_${sampleChatSummary.id}')), findsNothing);
    // The surviving chat must still show its normal "Unarchive" button, not
    // an indefinite spinner inherited from the tile that used to occupy the
    // same list position.
    expect(find.byKey(Key('unarchive_chat_button_${secondChat.id}')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows an error and keeps the chat when unarchiving fails', (tester) async {
    final chatApi = FakeChatApi()..unarchiveError = const NetworkUnavailableException();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          chatApiProvider.overrideWithValue(chatApi),
          archivedChatsControllerProvider.overrideWith(() => FakeArchivedChatsController([sampleChatSummary])),
        ],
        child: const MaterialApp(home: ArchivedChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('unarchive_chat_button_${sampleChatSummary.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('archived_chat_tile_${sampleChatSummary.id}')), findsOneWidget);
    expect(find.byKey(Key('chat_unarchive_error_${sampleChatSummary.id}')), findsOneWidget);
  });
}
