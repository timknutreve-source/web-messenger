import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/domain/chat_event.dart';

import '../../support/fakes.dart';

void main() {
  late FakeChatApi chatApi;
  late FakeChatWebSocketClient wsClient;
  late FakeMessageApi messageApi;
  late ProviderContainer container;

  setUp(() {
    chatApi = FakeChatApi();
    wsClient = FakeChatWebSocketClient();
    messageApi = FakeMessageApi();
    container = ProviderContainer(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        chatWebSocketClientFactoryProvider.overrideWithValue(() => wsClient),
        messageApiProvider.overrideWithValue(messageApi),
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  group('ChatsController', () {
    test('loads active chats on build', () async {
      chatApi.activeChatsResult = [sampleChatSummary];

      final chats = await container.read(chatsControllerProvider.future);

      expect(chats, hasLength(1));
      expect(chats.first.otherUser?.username, 'bob');
    });

    test('a network failure loading the chat list surfaces immediately, '
        'without Riverpod\'s automatic retry storm', () {
      fakeAsync((async) {
        chatApi.activeChatsError = const NetworkUnavailableException();

        container.listen(chatsControllerProvider, (_, _) {});
        async.elapse(Duration.zero);

        expect(chatApi.listActiveChatsCallCount, 1);
        expect(container.read(chatsControllerProvider).hasError, isTrue);

        // Riverpod's own default retry policy would otherwise silently
        // retry up to 10 times with backoff capped at 6.4s between
        // attempts - worst case, over a minute hidden behind the loading
        // state before the chat list ever showed a persistent error.
        async.elapse(const Duration(minutes: 2));

        expect(chatApi.listActiveChatsCallCount, 1);
        expect(container.read(chatsControllerProvider).hasError, isTrue);
      });
    });

    test('archive calls the API and removes the chat from state', () async {
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);

      await container.read(chatsControllerProvider.notifier).archive(sampleChatSummary.id);

      expect(chatApi.archivedChatIds, [sampleChatSummary.id]);
      expect(container.read(chatsControllerProvider).value, isEmpty);
    });

    test('a NEW_MESSAGE broadcast from the other participant increments the unread badge', () async {
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);

      wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'm1',
        'sender': {'id': sampleContactUser.id, 'username': sampleContactUser.username},
        'createdAt': '2026-01-02T00:00:00Z',
      }));

      expect(container.read(chatsControllerProvider).value!.first.unreadCount, 1);
    });

    test('a message arriving in a chat that is open on screen is not counted as unread', () async {
      // The open chat marks it read as it lands; the list (a separate socket)
      // must not count it afterwards, or the badge stays stuck on a chat the
      // user is looking at.
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);
      container.listen(chatRoomControllerProvider('chat-1'), (_, _) {});
      await container.read(chatRoomControllerProvider('chat-1').future);

      wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'm1',
        'conversationId': 'chat-1',
        'sender': {'id': sampleContactUser.id, 'username': sampleContactUser.username, 'email': sampleContactUser.email, 'avatarFileName': null},
        'content': 'hi',
        'status': 'SENT',
        'createdAt': '2026-01-02T00:00:00Z',
        'editedAt': null,
        'deleted': false,
        'attachments': <dynamic>[],
        'poll': null,
      }));

      expect(container.read(chatsControllerProvider).value!.first.unreadCount, 0);
    });

    test('once the chat is closed again, new messages count as unread', () async {
      // Uses a broker-backed fake so a closed chat really stops listening.
      final broker = FakeBroker();
      final local = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(chatApi),
          chatWebSocketClientFactoryProvider.overrideWithValue(broker.newClient),
          messageApiProvider.overrideWithValue(messageApi),
          authControllerProvider.overrideWith(
            () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
          ),
        ],
      );
      addTearDown(local.dispose);
      chatApi.activeChatsResult = [sampleChatSummary];
      await local.read(chatsControllerProvider.future);
      final subscription = local.listen(chatRoomControllerProvider('chat-1'), (_, _) {});
      await local.read(chatRoomControllerProvider('chat-1').future);
      expect(local.read(openChatRegistryProvider).isOpen('chat-1'), isTrue);

      subscription.close();
      await Future<void>.delayed(Duration.zero);
      expect(local.read(openChatRegistryProvider).isOpen('chat-1'), isFalse);

      broker.emitToChat('chat-1', ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'm2',
        'conversationId': 'chat-1',
        'sender': {'id': sampleContactUser.id, 'username': sampleContactUser.username, 'email': sampleContactUser.email, 'avatarFileName': null},
        'content': 'hi',
        'status': 'SENT',
        'createdAt': '2026-01-02T00:00:00Z',
        'editedAt': null,
        'deleted': false,
        'attachments': <dynamic>[],
        'poll': null,
      }));

      expect(local.read(chatsControllerProvider).value!.first.unreadCount, 1);
    });

    test('a NEW_MESSAGE broadcast for a message we sent ourselves does not increment the badge', () async {
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);

      wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'm1',
        'sender': {'id': sampleUser.id, 'username': sampleUser.username},
        'createdAt': '2026-01-02T00:00:00Z',
      }));

      expect(container.read(chatsControllerProvider).value!.first.unreadCount, 0);
    });

    test('sending a message ourselves still bumps lastActivityAt, moving the chat up the timeline',
        () async {
      // sampleChatSummary starts with an old lastActivityAt.
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);
      expect(container.read(chatsControllerProvider).value!.first.lastActivityAt, DateTime.utc(2026, 1, 1));

      // A message *we* sent arrives over our own WebSocket subscription
      // (the backend broadcasts NEW_MESSAGE to every participant, sender
      // included) - this must bump lastActivityAt exactly like a message
      // from the other participant would, so the chat sorts to the top of
      // the timeline. Only the unread badge should stay untouched.
      wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'm1',
        'sender': {'id': sampleUser.id, 'username': sampleUser.username},
        'createdAt': '2026-06-01T00:00:00Z',
      }));

      final chat = container.read(chatsControllerProvider).value!.first;
      expect(chat.lastActivityAt, DateTime.utc(2026, 6, 1));
      expect(chat.unreadCount, 0);
    });

    test('a NEW_MESSAGE from another participant acknowledges delivery, even without opening the chat',
        () async {
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);

      wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'm1',
        'sender': {'id': sampleContactUser.id, 'username': sampleContactUser.username},
        'createdAt': '2026-01-02T00:00:00Z',
      }));
      await Future<void>.delayed(Duration.zero);

      expect(messageApi.markedDeliveredMessageIds, ['m1']);
    });

    test('a NEW_MESSAGE we sent ourselves is never acknowledged as delivered', () async {
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);

      wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'm1',
        'sender': {'id': sampleUser.id, 'username': sampleUser.username},
        'createdAt': '2026-01-02T00:00:00Z',
      }));
      await Future<void>.delayed(Duration.zero);

      expect(messageApi.markedDeliveredMessageIds, isEmpty);
    });

    test('markChatRead zeroes a specific chat\'s unread count', () async {
      chatApi.activeChatsResult = [sampleChatSummary.copyWith(unreadCount: 4)];
      await container.read(chatsControllerProvider.future);

      container.read(chatsControllerProvider.notifier).markChatRead(sampleChatSummary.id);

      expect(container.read(chatsControllerProvider).value!.first.unreadCount, 0);
    });

    test('a failed archive throws and leaves the chat in state', () async {
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);

      chatApi.archiveError = Exception('boom');

      await expectLater(
        container.read(chatsControllerProvider.notifier).archive(sampleChatSummary.id),
        throwsException,
      );
      expect(container.read(chatsControllerProvider).value, hasLength(1));
    });
  });

  group('ArchivedChatsController', () {
    test('loads archived chats on build', () async {
      chatApi.archivedChatsResult = [sampleChatSummary];

      final chats = await container.read(archivedChatsControllerProvider.future);

      expect(chats, hasLength(1));
    });

    test('unarchive calls the API and removes the chat from state', () async {
      chatApi.archivedChatsResult = [sampleChatSummary];
      await container.read(archivedChatsControllerProvider.future);

      await container.read(archivedChatsControllerProvider.notifier).unarchive(sampleChatSummary.id);

      expect(chatApi.unarchivedChatIds, [sampleChatSummary.id]);
      expect(container.read(archivedChatsControllerProvider).value, isEmpty);
    });

    test('unarchive invalidates the active chats list', () async {
      chatApi.archivedChatsResult = [sampleChatSummary];
      chatApi.activeChatsResult = [];
      await container.read(archivedChatsControllerProvider.future);
      await container.read(chatsControllerProvider.future);

      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(archivedChatsControllerProvider.notifier).unarchive(sampleChatSummary.id);

      final chats = await container.read(chatsControllerProvider.future);
      expect(chats, hasLength(1));
    });
  });
}
