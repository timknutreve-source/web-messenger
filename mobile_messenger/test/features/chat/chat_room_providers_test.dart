import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/domain/attachment.dart';
import 'package:mobile_messenger/features/chat/domain/chat_event.dart';
import 'package:mobile_messenger/features/chat/domain/message.dart';
import 'package:mobile_messenger/features/chat/domain/message_page.dart';
import 'package:mobile_messenger/features/chat/domain/pending_attachment.dart';

import '../../support/fakes.dart';

void main() {
  late FakeMessageApi messageApi;
  late FakeChatApi chatApi;
  late FakeChatWebSocketClient wsClient;
  late FakeAttachmentApi attachmentApi;
  late FakeAttachmentPicker attachmentPicker;
  late FakeAudioRecorderService audioRecorder;
  late ProviderContainer container;
  late File pickedFile;

  setUp(() {
    messageApi = FakeMessageApi();
    // Defaults to an empty chat list, so chatsControllerProvider's own
    // WebSocket subscription (opened as a side effect of ChatRoomController's
    // _markRead() reaching into it - see markChatRead) has nothing to
    // subscribe to unless a specific test opts in.
    chatApi = FakeChatApi()..activeChatsResult = [];
    wsClient = FakeChatWebSocketClient();
    attachmentApi = FakeAttachmentApi();
    attachmentPicker = FakeAttachmentPicker();
    audioRecorder = FakeAudioRecorderService();
    pickedFile = File('${Directory.systemTemp.path}/chat_room_providers_test_pick.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    container = ProviderContainer(
      overrides: [
        messageApiProvider.overrideWithValue(messageApi),
        chatApiProvider.overrideWithValue(chatApi),
        attachmentApiProvider.overrideWithValue(attachmentApi),
        attachmentPickerProvider.overrideWithValue(attachmentPicker),
        audioRecorderServiceProvider.overrideWithValue(() => audioRecorder),
        chatWebSocketClientFactoryProvider.overrideWithValue(() => wsClient),
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      if (pickedFile.existsSync()) pickedFile.deleteSync();
    });
  });

  // chatRoomControllerProvider is autoDispose; a bare container.read() doesn't
  // keep it alive once a test awaits something that actually yields to the
  // event loop for a while (e.g. a real Future.delayed), so it can be torn
  // down and rebuilt mid-test. Call this to keep it alive for such a test's
  // duration - but only after any mock data those tests need is configured,
  // since starting it eagerly (e.g. from setUp, before the test body runs)
  // races the test's own mock-configuring statements against build()
  // actually starting.
  void keepChatRoomAlive() {
    container.listen(chatRoomControllerProvider('chat-1'), (_, _) {});
  }

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

  test('a network failure loading the chat surfaces as a persistent error immediately, '
      'without Riverpod\'s automatic retry storm', () {
    fakeAsync((async) {
      messageApi.loadMessagesError = const NetworkUnavailableException();
      keepChatRoomAlive();
      async.elapse(Duration.zero);

      expect(messageApi.loadMessagesCallCount, 1);
      expect(container.read(chatRoomControllerProvider('chat-1')).hasError, isTrue);

      // Riverpod's own default retry policy would otherwise keep silently
      // retrying for up to 10 attempts with backoff capped at 6.4s between
      // each - worst case, over a minute of hidden retries behind the
      // loading state before the UI would ever see a persistent error. None
      // of that may happen: a single failed attempt must be final.
      async.elapse(const Duration(minutes: 2));

      expect(messageApi.loadMessagesCallCount, 1);
      expect(container.read(chatRoomControllerProvider('chat-1')).hasError, isTrue);
    });
  });

  test('acknowledges delivery on build for still-SENT messages from the other participant', () async {
    messageApi.loadMessagesResult = MessagePage(
      messages: [sampleMessage(id: 'm1', status: MessageStatus.sent)],
      hasMore: false,
    );

    await container.read(chatRoomControllerProvider('chat-1').future);
    await Future<void>.delayed(Duration.zero);

    expect(messageApi.markedDeliveredMessageIds, ['m1']);
  });

  test('does not acknowledge delivery for our own messages, or ones already delivered/read on build',
      () async {
    messageApi.loadMessagesResult = MessagePage(
      messages: [
        sampleMessage(id: 'm1', sender: sampleUserContactSummary, status: MessageStatus.sent),
        sampleMessage(id: 'm2', status: MessageStatus.delivered),
        sampleMessage(id: 'm3', status: MessageStatus.read),
      ],
      hasMore: false,
    );

    await container.read(chatRoomControllerProvider('chat-1').future);
    await Future<void>.delayed(Duration.zero);

    expect(messageApi.markedDeliveredMessageIds, isEmpty);
  });

  test('marks the conversation read on build', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);
    expect(messageApi.markReadCallCount, 1);
  });

  test('opening a chat zeroes its unread count on the chat list (badge)', () async {
    // Reproduces the fix for: the chat list's unread badge only ever went
    // down after a full list refetch, so it stayed stale while the user was
    // actively reading the very chat it counted.
    chatApi.activeChatsResult = [sampleChatSummary.copyWith(unreadCount: 3)];
    await container.read(chatsControllerProvider.future);
    expect(container.read(chatsControllerProvider).value!.first.unreadCount, 3);

    await container.read(chatRoomControllerProvider(sampleChatSummary.id).future);

    expect(container.read(chatsControllerProvider).value!.first.unreadCount, 0);
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

  test('a send that times out marks the message failed, never sent/delivered', () async {
    await container.read(chatRoomControllerProvider('chat-1').future);
    messageApi.sendMessageError = const RequestTimeoutException();

    await container.read(chatRoomControllerProvider('chat-1').notifier).send('hi');

    final message = container.read(chatRoomControllerProvider('chat-1')).value!.messages.first;
    expect(message.sendState, SendState.failed);
    expect(message.status, isNot(MessageStatus.delivered));
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

  test(
      'a NEW_MESSAGE broadcast for our own just-sent message arriving before '
      'the REST response does not duplicate it', () async {
    // Reproduces a real-device bug: the server broadcasts NEW_MESSAGE to
    // every participant - including the sender - and over a real network
    // that broadcast can reach the client before the REST response to the
    // very request that created it does. Both paths must converge on
    // exactly one copy of the message, regardless of which arrives first.
    await container.read(chatRoomControllerProvider('chat-1').future);
    keepChatRoomAlive();
    final gate = Completer<void>();
    messageApi.sendMessageGate = gate;
    messageApi.sendMessageResult = sampleMessage(id: 'server-1', content: 'jo', sender: sampleUserContactSummary);

    final sendFuture = container.read(chatRoomControllerProvider('chat-1').notifier).send('jo');
    // Let send() run up to (and block on) the gated REST call - it awaits
    // the auth token first, so this needs more than one microtask turn.
    await Future<void>.delayed(Duration.zero);

    // The optimistic placeholder is showing; the REST call is still pending.
    expect(container.read(chatRoomControllerProvider('chat-1')).value!.messages, hasLength(1));

    // The WebSocket broadcast for the same message wins the race.
    wsClient.emit(ChatEvent(
      type: 'NEW_MESSAGE',
      payload: incomingMessageJson(id: 'server-1', content: 'jo'),
    ));
    expect(container.read(chatRoomControllerProvider('chat-1')).value!.messages, hasLength(2),
        reason: 'the optimistic placeholder and the broadcast message coexist until the REST response settles');

    // Now let the REST response for the send() call complete.
    gate.complete();
    await sendFuture;

    final state = container.read(chatRoomControllerProvider('chat-1')).value!;
    expect(state.messages, hasLength(1));
    expect(state.messages.first.id, 'server-1');
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
    keepChatRoomAlive();

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

  group('attachments', () {
    test('picking an image uploads it and ends in the uploaded state', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);
      attachmentPicker.imageResult = pickedFile;
      attachmentApi.uploadResult = sampleAttachment(id: 'att-1');

      await container.read(chatRoomControllerProvider('chat-1').notifier).pickImage(ImageSource.gallery);

      final pending = container.read(chatRoomControllerProvider('chat-1')).value!.pendingAttachment;
      expect(pending, isNotNull);
      expect(pending!.state, PendingAttachmentState.uploaded);
      expect(pending.uploaded!.id, 'att-1');
      expect(attachmentApi.uploadedFilePaths, [pickedFile.path]);
    });

    test('picking a video records the gallery source and uploads it', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);
      attachmentPicker.videoResult = pickedFile;

      await container.read(chatRoomControllerProvider('chat-1').notifier).pickVideo(ImageSource.gallery);

      expect(attachmentPicker.videoPickSources, [ImageSource.gallery]);
      final pending = container.read(chatRoomControllerProvider('chat-1')).value!.pendingAttachment;
      expect(pending!.state, PendingAttachmentState.uploaded);
    });

    test('a cancelled pick (null result) leaves no pending attachment', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);
      attachmentPicker.imageResult = null;

      await container.read(chatRoomControllerProvider('chat-1').notifier).pickImage(ImageSource.camera);

      expect(container.read(chatRoomControllerProvider('chat-1')).value!.pendingAttachment, isNull);
    });

    test('a failed upload surfaces the failed state, and retry can recover it', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);
      attachmentPicker.imageResult = pickedFile;
      attachmentApi.uploadError = Exception('network down');

      final notifier = container.read(chatRoomControllerProvider('chat-1').notifier);
      await notifier.pickImage(ImageSource.gallery);

      expect(
        container.read(chatRoomControllerProvider('chat-1')).value!.pendingAttachment!.state,
        PendingAttachmentState.failed,
      );

      attachmentApi.uploadError = null;
      attachmentApi.uploadResult = sampleAttachment(id: 'att-recovered');
      await notifier.retryPendingAttachmentUpload();

      final pending = container.read(chatRoomControllerProvider('chat-1')).value!.pendingAttachment;
      expect(pending!.state, PendingAttachmentState.uploaded);
      expect(pending.uploaded!.id, 'att-recovered');
    });

    test('removePendingAttachment clears it', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);
      attachmentPicker.imageResult = pickedFile;
      final notifier = container.read(chatRoomControllerProvider('chat-1').notifier);
      await notifier.pickImage(ImageSource.gallery);

      notifier.removePendingAttachment();

      expect(container.read(chatRoomControllerProvider('chat-1')).value!.pendingAttachment, isNull);
    });

    test('send is a no-op while the attachment is still uploading', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);
      keepChatRoomAlive();
      attachmentPicker.imageResult = pickedFile;
      attachmentApi.uploadDelay = Completer<Attachment>();
      final notifier = container.read(chatRoomControllerProvider('chat-1').notifier);

      unawaited(notifier.pickImage(ImageSource.gallery));
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(chatRoomControllerProvider('chat-1')).value!.pendingAttachment!.state,
        PendingAttachmentState.uploading,
      );

      await notifier.send('hello');

      expect(container.read(chatRoomControllerProvider('chat-1')).value!.messages, isEmpty);
      expect(messageApi.sentContents, isEmpty);
    });

    test('sending with an uploaded attachment and no text works', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);
      attachmentPicker.imageResult = pickedFile;
      attachmentApi.uploadResult = sampleAttachment(id: 'att-2');
      messageApi.sendMessageResult = sampleMessage(id: 'server-1', attachments: [sampleAttachment(id: 'att-2')]);
      final notifier = container.read(chatRoomControllerProvider('chat-1').notifier);
      await notifier.pickImage(ImageSource.gallery);

      await notifier.send('');

      expect(messageApi.sentContents, [null]);
      expect(messageApi.sentAttachmentIds, [
        ['att-2'],
      ]);
      final state = container.read(chatRoomControllerProvider('chat-1')).value!;
      expect(state.messages, hasLength(1));
      expect(state.messages.first.attachments.single.id, 'att-2');
      // The composer's attachment preview is cleared once the message is sent.
      expect(state.pendingAttachment, isNull);
    });

    test('a NEW_MESSAGE websocket event with attachments is parsed correctly', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);

      wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'incoming-att',
        'conversationId': 'chat-1',
        'sender': {
          'id': sampleContactUser.id,
          'username': sampleContactUser.username,
          'email': sampleContactUser.email,
          'avatarFileName': null,
        },
        'content': '',
        'status': 'SENT',
        'createdAt': '2026-01-01T00:00:00Z',
        'editedAt': null,
        'deleted': false,
        'attachments': [
          {
            'id': 'att-3',
            'type': 'VIDEO',
            'mimeType': 'video/mp4',
            'fileSize': 5000,
            'width': null,
            'height': null,
            'durationSeconds': 12,
            'url': '/api/attachments/att-3',
            'thumbnailUrl': null,
          },
        ],
      }));

      final state = container.read(chatRoomControllerProvider('chat-1')).value!;
      expect(state.messages, hasLength(1));
      final attachment = state.messages.first.attachments.single;
      expect(attachment.id, 'att-3');
      expect(attachment.type, AttachmentKind.video);
      expect(attachment.durationSeconds, 12);
    });

    test('a text-only message still has no attachments', () async {
      messageApi.loadMessagesResult = MessagePage(messages: [sampleMessage(id: 'm1')], hasMore: false);
      final state = await container.read(chatRoomControllerProvider('chat-1').future);

      expect(state.messages.single.attachments, isEmpty);
    });
  });

  group('voice messages', () {
    test('starting a recording requests permission and flips isRecordingAudio', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);

      await container.read(chatRoomControllerProvider('chat-1').notifier).startRecordingAudio();

      final state = container.read(chatRoomControllerProvider('chat-1')).value!;
      expect(state.isRecordingAudio, isTrue);
      expect(audioRecorder.started, isTrue);
    });

    test('denied microphone permission surfaces an error instead of silently doing nothing', () async {
      audioRecorder.hasPermissionResult = false;
      await container.read(chatRoomControllerProvider('chat-1').future);

      await container.read(chatRoomControllerProvider('chat-1').notifier).startRecordingAudio();

      final state = container.read(chatRoomControllerProvider('chat-1')).value!;
      expect(state.isRecordingAudio, isFalse);
      expect(state.audioRecordingError, isNotNull);
      expect(audioRecorder.started, isFalse);
    });

    test('stopping a recording uploads it as a pending audio attachment', () async {
      attachmentApi.uploadResult = sampleAttachment(type: AttachmentKind.audio, mimeType: 'audio/wav');
      await container.read(chatRoomControllerProvider('chat-1').future);
      final notifier = container.read(chatRoomControllerProvider('chat-1').notifier);
      await notifier.startRecordingAudio();

      await notifier.stopRecordingAudioAndSend();

      expect(audioRecorder.stopCallCount, 1);
      final state = container.read(chatRoomControllerProvider('chat-1')).value!;
      expect(state.isRecordingAudio, isFalse);
      expect(state.pendingAttachment?.kind, AttachmentKind.audio);
      expect(state.pendingAttachment?.state, PendingAttachmentState.uploaded);
      expect(state.pendingAttachment?.uploaded?.type, AttachmentKind.audio);
    });

    test('cancelling a recording discards it - no pending attachment, no upload', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);
      final notifier = container.read(chatRoomControllerProvider('chat-1').notifier);
      await notifier.startRecordingAudio();

      await notifier.cancelRecordingAudio();

      expect(audioRecorder.cancelled, isTrue);
      final state = container.read(chatRoomControllerProvider('chat-1')).value!;
      expect(state.isRecordingAudio, isFalse);
      expect(state.pendingAttachment, isNull);
      expect(attachmentApi.uploadedFilePaths, isEmpty);
    });

    test('a sent voice message carries its recorded duration to the upload call', () async {
      await container.read(chatRoomControllerProvider('chat-1').future);
      keepChatRoomAlive();
      final notifier = container.read(chatRoomControllerProvider('chat-1').notifier);
      await notifier.startRecordingAudio();
      // Simulate the recording timer having ticked a few seconds.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await notifier.stopRecordingAudioAndSend();

      expect(attachmentApi.uploadedDurations, hasLength(1));
      expect(attachmentApi.uploadedDurations.single, isNotNull);
    });
  });
}
