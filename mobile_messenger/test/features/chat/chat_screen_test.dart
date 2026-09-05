import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/domain/attachment.dart';
import 'package:mobile_messenger/features/chat/domain/chat_event.dart';
import 'package:mobile_messenger/features/chat/domain/message.dart';
import 'package:mobile_messenger/features/chat/domain/message_page.dart';
import 'package:mobile_messenger/features/chat/presentation/chat_screen.dart';

import '../../support/fakes.dart';

void main() {
  final authenticatedOverride = authControllerProvider.overrideWith(
    () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
  );

  late FakeMessageApi messageApi;
  late FakeChatWebSocketClient wsClient;
  late FakeAttachmentApi attachmentApi;
  late FakeAttachmentPicker attachmentPicker;
  late File pickedFile;

  setUp(() {
    messageApi = FakeMessageApi();
    wsClient = FakeChatWebSocketClient();
    attachmentApi = FakeAttachmentApi();
    attachmentPicker = FakeAttachmentPicker();
    pickedFile = File('${Directory.systemTemp.path}/chat_screen_test_pick.jpg')..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() {
    if (pickedFile.existsSync()) pickedFile.deleteSync();
  });

  List<Override> overrides() => [
        authenticatedOverride,
        messageApiProvider.overrideWithValue(messageApi),
        attachmentApiProvider.overrideWithValue(attachmentApi),
        attachmentPickerProvider.overrideWithValue(attachmentPicker),
        chatWebSocketClientFactoryProvider.overrideWithValue(() => wsClient),
      ];

  testWidgets('renders the chat screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat_screen')), findsOneWidget);
  });

  testWidgets('shows a loading indicator while messages load', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows an empty state for a conversation with no messages', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('messages_empty_view')), findsOneWidget);
  });

  testWidgets('renders messages in chronological order, own vs other distinguishable', (tester) async {
    messageApi.loadMessagesResult = MessagePage(
      messages: [
        sampleMessage(id: 'm1', sender: sampleUserContactSummary, content: 'from me'),
        sampleMessage(id: 'm2', sender: sampleContactUser, content: 'from bob'),
      ],
      hasMore: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const Key('message_list'));
    expect(listFinder, findsOneWidget);
    expect(find.text('from me'), findsOneWidget);
    expect(find.text('from bob'), findsOneWidget);
    // The other user's bubble shows their username above the content; mine doesn't.
    expect(find.text(sampleContactUser.username), findsOneWidget);
    expect(find.text(sampleUser.username), findsNothing);
  });

  testWidgets('shows an error state with retry when loading fails', (tester) async {
    messageApi.loadMessagesError = const NetworkUnavailableException();

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(const NetworkUnavailableException().message), findsOneWidget);

    messageApi.loadMessagesError = null;
    messageApi.loadMessagesResult = MessagePage(messages: [sampleMessage(id: 'm1')], hasMore: false);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message_bubble_m1')), findsOneWidget);
  });

  testWidgets('sending a valid message clears the input and shows it optimistically', (tester) async {
    messageApi.sendMessageResult =
        sampleMessage(id: 'server-1', sender: sampleUserContactSummary, content: 'hello there');

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('message_input')), 'hello there');
    await tester.tap(find.byKey(const Key('send_button')));
    await tester.pump();

    expect(find.text('hello there'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('message_input'))).controller!.text, isEmpty);

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('status_sent')), findsOneWidget);
  });

  testWidgets('blank text cannot be sent', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('message_input')), '   ');
    await tester.tap(find.byKey(const Key('send_button')));
    await tester.pumpAndSettle();

    expect(messageApi.sentContents, isEmpty);
    expect(find.byKey(const Key('messages_empty_view')), findsOneWidget);
  });

  testWidgets('a failed send shows a failed indicator with retry', (tester) async {
    messageApi.sendMessageError = const NetworkUnavailableException();

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('message_input')), 'will fail');
    await tester.tap(find.byKey(const Key('send_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('status_failed')), findsOneWidget);

    messageApi.sendMessageError = null;
    messageApi.sendMessageResult =
        sampleMessage(id: 'server-1', sender: sampleUserContactSummary, content: 'will fail');
    await tester.tap(find.byKey(const Key('status_failed')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('status_sent')), findsOneWidget);
    expect(find.byKey(const Key('status_failed')), findsNothing);
  });

  testWidgets('delivered and read statuses render distinct icons', (tester) async {
    messageApi.loadMessagesResult = MessagePage(
      messages: [
        sampleMessage(id: 'm1', sender: sampleUserContactSummary, status: MessageStatus.delivered),
        sampleMessage(id: 'm2', sender: sampleUserContactSummary, status: MessageStatus.read),
      ],
      hasMore: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('status_delivered')), findsOneWidget);
    expect(find.byKey(const Key('status_read')), findsOneWidget);
  });

  testWidgets('own message can be edited via long-press menu', (tester) async {
    messageApi.loadMessagesResult = MessagePage(
      messages: [sampleMessage(id: 'm1', sender: sampleUserContactSummary, content: 'typo')],
      hasMore: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message_bubble_m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit_message_action_m1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_message_action_m1')));
    await tester.pumpAndSettle();

    final editField = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(editField, 'fixed');
    messageApi.editMessageResult =
        sampleMessage(id: 'm1', sender: sampleUserContactSummary, content: 'fixed', editedAt: DateTime.now());
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('fixed'), findsOneWidget);
    expect(find.text('(edited)'), findsOneWidget);
    expect(messageApi.editedMessageIds, ['m1']);
  });

  testWidgets('another user\'s message has no edit/delete menu', (tester) async {
    messageApi.loadMessagesResult = MessagePage(
      messages: [sampleMessage(id: 'm1', sender: sampleContactUser, content: 'from bob')],
      hasMore: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message_bubble_m1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit_message_action_m1')), findsNothing);
    expect(find.byKey(const Key('delete_message_action_m1')), findsNothing);
  });

  testWidgets('own message can be deleted with confirmation, showing a neutral placeholder', (tester) async {
    messageApi.loadMessagesResult = MessagePage(
      messages: [sampleMessage(id: 'm1', sender: sampleUserContactSummary, content: 'secret')],
      hasMore: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message_bubble_m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_message_action_m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('secret'), findsNothing);
    expect(find.text('This message was deleted'), findsOneWidget);
    expect(messageApi.deletedMessageIds, ['m1']);
  });

  testWidgets('typing indicator appears on TYPING_STARTED and disappears on TYPING_STOPPED', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    wsClient.emit(const ChatEvent(type: 'TYPING_STARTED', payload: {'userId': 'user-2', 'username': 'bob'}));
    await tester.pump();

    expect(find.byKey(const Key('typing_indicator')), findsOneWidget);
    expect(find.text('bob is typing...'), findsOneWidget);

    wsClient.emit(const ChatEvent(type: 'TYPING_STOPPED', payload: {'userId': 'user-2', 'username': 'bob'}));
    await tester.pump();

    expect(find.byKey(const Key('typing_indicator')), findsNothing);
  });

  testWidgets('typing in the composer sends a typing-started event', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('message_input')), 'h');
    await tester.pump();

    expect(wsClient.typingCalls, [true]);
  });

  group('attachments', () {
    testWidgets('the attach button opens a picker with image/video/camera options', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('attach_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pick_image_gallery_action')), findsOneWidget);
      expect(find.byKey(const Key('pick_image_camera_action')), findsOneWidget);
      expect(find.byKey(const Key('pick_video_gallery_action')), findsOneWidget);
      expect(find.byKey(const Key('pick_video_camera_action')), findsOneWidget);
    });

    testWidgets('picking an image shows an uploading then a ready-to-send preview', (tester) async {
      attachmentPicker.imageResult = pickedFile;

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('attach_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick_image_gallery_action')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pending_attachment_preview')), findsOneWidget);
      expect(find.byKey(const Key('attachment_uploaded_label')), findsOneWidget);
      expect(attachmentPicker.imagePickSources, [ImageSource.gallery]);
    });

    testWidgets('an in-flight upload shows an uploading state and disables send', (tester) async {
      attachmentPicker.imageResult = pickedFile;
      attachmentApi.uploadDelay = Completer<Attachment>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('attach_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick_image_gallery_action')));
      await tester.pump();

      expect(find.byKey(const Key('attachment_uploading_label')), findsOneWidget);
      final sendButton = tester.widget<IconButton>(find.byKey(const Key('send_button')));
      expect(sendButton.onPressed, isNull);

      attachmentApi.uploadDelay!.complete(sampleAttachment());
      await tester.pumpAndSettle();
    });

    testWidgets('a failed upload shows an error with a retry action', (tester) async {
      attachmentPicker.imageResult = pickedFile;
      attachmentApi.uploadError = const NetworkUnavailableException();

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('attach_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick_image_gallery_action')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('attachment_failed_label')), findsOneWidget);

      attachmentApi.uploadError = null;
      await tester.tap(find.byKey(const Key('retry_attachment_upload_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('attachment_uploaded_label')), findsOneWidget);
    });

    testWidgets('removing a pending attachment clears the preview', (tester) async {
      attachmentPicker.imageResult = pickedFile;

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('attach_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick_image_gallery_action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pending_attachment_preview')), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove_pending_attachment_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pending_attachment_preview')), findsNothing);
    });

    testWidgets('an image message renders a tappable thumbnail', (tester) async {
      messageApi.loadMessagesResult = MessagePage(
        messages: [sampleMessage(id: 'm1', content: '', attachments: [sampleAttachment(id: 'att-1')])],
        hasMore: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('attachment_image_att-1')), findsOneWidget);
    });

    testWidgets('a video message renders a play icon and duration', (tester) async {
      messageApi.loadMessagesResult = MessagePage(
        messages: [
          sampleMessage(
            id: 'm1',
            content: '',
            attachments: [
              sampleAttachment(id: 'att-2', type: AttachmentKind.video, durationSeconds: 75, thumbnailUrl: null),
            ],
          ),
        ],
        hasMore: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('attachment_video_att-2')), findsOneWidget);
      expect(find.text('1:15'), findsOneWidget);
    });

    testWidgets('a deleted message with an attachment shows the neutral placeholder, not the media', (tester) async {
      messageApi.loadMessagesResult = MessagePage(
        messages: [
          sampleMessage(
            id: 'm1',
            content: null,
            deleted: true,
            attachments: const [],
          ),
        ],
        hasMore: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.byKey(const Key('attachment_image_att-1')), findsNothing);
    });

    testWidgets('a text-only message renders correctly with no attachments', (tester) async {
      messageApi.loadMessagesResult = MessagePage(messages: [sampleMessage(id: 'm1', content: 'hi')], hasMore: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('hi'), findsOneWidget);
      expect(find.byType(AspectRatio), findsNothing);
    });
  });
}
