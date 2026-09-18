import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart' show chatWebSocketClientFactoryProvider;
import 'package:mobile_messenger/features/chat/domain/chat_summary.dart';
import 'package:mobile_messenger/features/chat/presentation/chats_screen.dart';

import '../../support/fakes.dart';

void main() {
  final authenticatedOverride = authControllerProvider.overrideWith(
    () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
  );

  testWidgets('renders the chats screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, chatsControllerProvider.overrideWith(() => FakeChatsController([]))],
        child: const MaterialApp(home: ChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chats_screen')), findsOneWidget);
  });

  testWidgets('shows a loading indicator while chats are loading', (tester) async {
    final delay = Completer<List<ChatSummary>>();
    final chatApi = FakeChatApi()..activeChatsDelay = delay;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          chatApiProvider.overrideWithValue(chatApi),
          chatWebSocketClientFactoryProvider.overrideWithValue(() => FakeChatWebSocketClient()),
        ],
        child: const MaterialApp(home: ChatsScreen()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    delay.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('shows an empty state when there are no chats', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, chatsControllerProvider.overrideWith(() => FakeChatsController([]))],
        child: const MaterialApp(home: ChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chats_empty_view')), findsOneWidget);
  });

  testWidgets('renders a chat with the other user info once loaded', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          chatsControllerProvider.overrideWith(() => FakeChatsController([sampleChatSummary])),
        ],
        child: const MaterialApp(home: ChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('chat_tile_${sampleChatSummary.id}')), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('shows an error state with retry when loading chats fails', (tester) async {
    final chatApi = FakeChatApi()..activeChatsError = const NetworkUnavailableException();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          chatApiProvider.overrideWithValue(chatApi),
          chatWebSocketClientFactoryProvider.overrideWithValue(() => FakeChatWebSocketClient()),
        ],
        child: const MaterialApp(home: ChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(const NetworkUnavailableException().message), findsOneWidget);

    chatApi.activeChatsError = null;
    chatApi.activeChatsResult = [sampleChatSummary];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('chat_tile_${sampleChatSummary.id}')), findsOneWidget);
  });

  testWidgets('archiving a chat removes it from the active list', (tester) async {
    final chatApi = FakeChatApi();
    final container = ProviderContainer(
      overrides: [
        authenticatedOverride,
        chatApiProvider.overrideWithValue(chatApi),
        chatsControllerProvider.overrideWith(() => FakeChatsController([sampleChatSummary])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: ChatsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('chat_tile_${sampleChatSummary.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('archive_chat_button_${sampleChatSummary.id}')));
    await tester.pumpAndSettle();

    expect(chatApi.archivedChatIds, [sampleChatSummary.id]);
    expect(find.byKey(Key('chat_tile_${sampleChatSummary.id}')), findsNothing);
    expect(find.byKey(const Key('chats_empty_view')), findsOneWidget);
  });

  testWidgets('shows an error and keeps the chat when archiving fails', (tester) async {
    final chatApi = FakeChatApi()..archiveError = const NetworkUnavailableException();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedOverride,
          chatApiProvider.overrideWithValue(chatApi),
          chatsControllerProvider.overrideWith(() => FakeChatsController([sampleChatSummary])),
        ],
        child: const MaterialApp(home: ChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('archive_chat_button_${sampleChatSummary.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('chat_tile_${sampleChatSummary.id}')), findsOneWidget);
    expect(find.byKey(Key('chat_archive_error_${sampleChatSummary.id}')), findsOneWidget);
  });
}
