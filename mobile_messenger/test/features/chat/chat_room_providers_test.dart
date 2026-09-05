import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/domain/chat_event.dart';
import 'package:mobile_messenger/features/chat/domain/message.dart';
import 'package:mobile_messenger/features/chat/domain/message_page.dart';

import '../../support/fakes.dart';

void main() {
  late FakeMessageApi messageApi;
  late FakeChatWebSocketClient wsClient;
  late ProviderContainer container;

  setUp(() {
    messageApi = FakeMessageApi();
    wsClient = FakeChatWebSocketClient();
    container = ProviderContainer(
      overrides: [
        messageApiProvider.overrideWithValue(messageApi),
        chatWebSocketClientFactoryProvider.overrideWithValue(() => wsClient),
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
      ],
    );
    addTearDown(container.dispose);
    // chatRoomControllerProvider is autoDispose; a bare container.read()
    // doesn't keep it alive once the test awaits something that actually
    // yields to the event loop (e.g. Future.delayed), so tests would see it
    // torn down and rebuilt mid-test. Keep it alive for the test's duration.
    container.listen(chatRoomControllerProvider('chat-1'), (_, _) {});
  });

  Map<String, dynamic> incomingMessageJson({
    String id = 'incoming-1',
    String content = 'hey',
    String status = 'SENT',
    String createdAt = '2026-01-01T00:00:00Z',
  }) =>
      {
        'id': id,
        'conversationId': 'chat-1',
        'sender': {
          'id': sampleContactUser.id,
          'username': sampleContactUser.username,
          'email': sampleContactUser.email,
          'avatarFileName': null,
        },
        'content': content,
        'status': status,
        'createdAt': createdAt,
        'editedAt': null,
        'deleted': false,
      };

  test('loads the initial page of messages on build', () async {
    messageApi.loadMessagesResult = MessagePage(messages: [sampleMessage()], hasMore: false);

    final state = await container.read(chatRoomControllerProvider('chat-1').future);

    expect(state.messages, hasLength(1));
    expect(state.hasMoreOlder, isFalse);
  });

  test('marks the conversation read on build', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);
    expect(messageApi.markReadCallCount, 1);
  });

  test('send adds an optimistic pending message then replaces it with the confirmed one', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);
    messageApi.sendMessageResult = sampleMessage(id: 'server-1', content: 'hi');

    await container.read(chatRoomControllerProvider('chat-1').notifier).send('hi');

    final state = container.read(chatRoomControllerProvider('chat-1')).value!;
    expect(state.messages, hasLength(1));
    expect(state.messages.first.id, 'server-1');
    expect(state.messages.first.sendState, SendState.confirmed);
  });

  test('blank content is not sent', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);

    await container.read(chatRoomControllerProvider('chat-1').notifier).send('   ');

    expect(messageApi.sentContents, isEmpty);
    expect(container.read(chatRoomControllerProvider('chat-1')).value!.messages, isEmpty);
  });

  test('a failed send marks the message failed rather than discarding it', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);
    messageApi.sendMessageError = Exception('boom');

    await container.read(chatRoomControllerProvider('chat-1').notifier).send('hi');

    final state = container.read(chatRoomControllerProvider('chat-1')).value!;
    expect(state.messages, hasLength(1));
    expect(state.messages.first.sendState, SendState.failed);
  });

  test('retry resends a failed message and confirms it on success', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);
    messageApi.sendMessageError = Exception('boom');
    await container.read(chatRoomControllerProvider('chat-1').notifier).send('hi');
    final failedId = container.read(chatRoomControllerProvider('chat-1')).value!.messages.first.id;

    messageApi.sendMessageError = null;
    messageApi.sendMessageResult = sampleMessage(id: 'server-2', content: 'hi');
    await container.read(chatRoomControllerProvider('chat-1').notifier).retry(failedId);

    final state = container.read(chatRoomControllerProvider('chat-1')).value!;
    expect(state.messages.first.id, 'server-2');
    expect(state.messages.first.sendState, SendState.confirmed);
  });

  test('edit updates content and edited state', () async {
    messageApi.loadMessagesResult =
        MessagePage(messages: [sampleMessage(id: 'm1', content: 'typo')], hasMore: false);
    await container.read(chatRoomControllerProvider('chat-1').future);

    messageApi.editMessageResult =
        sampleMessage(id: 'm1', content: 'fixed', editedAt: DateTime.utc(2026, 1, 1));
    await container.read(chatRoomControllerProvider('chat-1').notifier).edit('m1', 'fixed');

    final state = container.read(chatRoomControllerProvider('chat-1')).value!;
    expect(state.messages.first.content, 'fixed');
    expect(state.messages.first.edited, isTrue);
  });

  test('delete marks the message deleted and clears its content locally', () async {
    messageApi.loadMessagesResult =
        MessagePage(messages: [sampleMessage(id: 'm1', content: 'secret')], hasMore: false);
    await container.read(chatRoomControllerProvider('chat-1').future);

    await container.read(chatRoomControllerProvider('chat-1').notifier).delete('m1');

    final state = container.read(chatRoomControllerProvider('chat-1')).value!;
    expect(state.messages.first.deleted, isTrue);
    expect(state.messages.first.content, isNull);
  });

  test('a NEW_MESSAGE event from the other participant is appended', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);

    wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: incomingMessageJson()));

    final state = container.read(chatRoomControllerProvider('chat-1')).value!;
    expect(state.messages, hasLength(1));
    expect(state.messages.first.content, 'hey');
  });

  test('a NEW_MESSAGE event for an already-known id is not appended twice', () async {
    messageApi.loadMessagesResult = MessagePage(messages: [sampleMessage(id: 'm1')], hasMore: false);
    await container.read(chatRoomControllerProvider('chat-1').future);

    wsClient.emit(ChatEvent(
      type: 'NEW_MESSAGE',
      payload: incomingMessageJson(id: 'm1', createdAt: '2026-01-01T12:00:00Z'),
    ));

    final state = container.read(chatRoomControllerProvider('chat-1')).value!;
    expect(state.messages, hasLength(1));
  });

  test('MESSAGE_DELETED event marks the message deleted', () async {
    messageApi.loadMessagesResult = MessagePage(messages: [sampleMessage(id: 'm1')], hasMore: false);
    await container.read(chatRoomControllerProvider('chat-1').future);

    wsClient.emit(ChatEvent(type: 'MESSAGE_DELETED', payload: {'messageId': 'm1'}));

    expect(container.read(chatRoomControllerProvider('chat-1')).value!.messages.first.deleted, isTrue);
  });

  test('MESSAGES_READ event marks the listed messages read', () async {
    messageApi.loadMessagesResult =
        MessagePage(messages: [sampleMessage(id: 'm1', status: MessageStatus.sent)], hasMore: false);
    await container.read(chatRoomControllerProvider('chat-1').future);

    wsClient.emit(ChatEvent(type: 'MESSAGES_READ', payload: {
      'messageIds': ['m1'],
    }));

    expect(
      container.read(chatRoomControllerProvider('chat-1')).value!.messages.first.status,
      MessageStatus.read,
    );
  });

  test('TYPING_STARTED sets the typing username, TYPING_STOPPED clears it', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);

    wsClient.emit(ChatEvent(type: 'TYPING_STARTED', payload: {'userId': 'user-2', 'username': 'bob'}));
    expect(container.read(chatRoomControllerProvider('chat-1')).value!.typingUsername, 'bob');

    wsClient.emit(ChatEvent(type: 'TYPING_STOPPED', payload: {'userId': 'user-2', 'username': 'bob'}));
    expect(container.read(chatRoomControllerProvider('chat-1')).value!.typingUsername, isNull);
  });

  test('the typing indicator auto-clears even if TYPING_STOPPED never arrives', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);

    wsClient.emit(ChatEvent(type: 'TYPING_STARTED', payload: {'userId': 'user-2', 'username': 'bob'}));
    expect(container.read(chatRoomControllerProvider('chat-1')).value!.typingUsername, 'bob');

    await Future<void>.delayed(const Duration(seconds: 6));
    expect(container.read(chatRoomControllerProvider('chat-1')).value!.typingUsername, isNull);
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('onComposerChanged sends a single typing-started event per burst', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);
    final notifier = container.read(chatRoomControllerProvider('chat-1').notifier);

    notifier.onComposerChanged('h');
    notifier.onComposerChanged('he');
    notifier.onComposerChanged('hel');

    expect(wsClient.typingCalls, [true]);
  });

  test('stopTyping only sends typing-stopped if typing-started was sent', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);
    final notifier = container.read(chatRoomControllerProvider('chat-1').notifier);

    notifier.stopTyping();
    expect(wsClient.typingCalls, isEmpty);

    notifier.onComposerChanged('hi');
    notifier.stopTyping();
    expect(wsClient.typingCalls, [true, false]);
  });

  test('loadOlder prepends an older page in chronological order', () async {
    messageApi.loadMessagesResult = MessagePage(
      messages: [sampleMessage(id: 'm2', createdAt: DateTime.utc(2026, 1, 2))],
      hasMore: true,
    );
    await container.read(chatRoomControllerProvider('chat-1').future);

    messageApi.loadMessagesResult = MessagePage(
      messages: [sampleMessage(id: 'm1', createdAt: DateTime.utc(2026, 1, 1))],
      hasMore: false,
    );
    await container.read(chatRoomControllerProvider('chat-1').notifier).loadOlder();

    final state = container.read(chatRoomControllerProvider('chat-1')).value!;
    expect(state.messages.map((m) => m.id), ['m1', 'm2']);
    expect(state.hasMoreOlder, isFalse);
  });
}
