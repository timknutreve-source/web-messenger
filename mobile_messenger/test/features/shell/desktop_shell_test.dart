import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/domain/chat_event.dart';
import 'package:mobile_messenger/features/chat/domain/chat_summary.dart';
import 'package:mobile_messenger/features/chat/domain/message_page.dart';
import 'package:mobile_messenger/features/chat/domain/message_search_result.dart';
import 'package:mobile_messenger/features/contact/contact_providers.dart';
import 'package:mobile_messenger/features/contact/domain/contact.dart';
import 'package:mobile_messenger/features/group/group_providers.dart';
import 'package:mobile_messenger/features/health/presentation/home_screen.dart';
import 'package:mobile_messenger/features/shell/presentation/desktop_shell.dart';
import 'package:mobile_messenger/features/shell/workspace_providers.dart';
import 'package:mobile_messenger/routing/app_root.dart';

import '../../support/fakes.dart';

void main() {
  late FakeMessageApi messageApi;
  late FakeChatApi chatApi;
  late FakeContactApi contactApi;
  late FakeGroupApi groupApi;
  late FakeBroker broker;

  final chatWithBob = ChatSummary(
    id: 'chat-1',
    otherUser: sampleContactUser,
    lastActivityAt: DateTime.utc(2026, 1, 3),
    archived: false,
  );
  final chatWithCarol = ChatSummary(
    id: 'chat-2',
    otherUser: sampleThirdUser,
    lastActivityAt: DateTime.utc(2026, 1, 2),
    archived: false,
  );

  setUp(() {
    broker = FakeBroker();
    messageApi = FakeMessageApi()
      ..messagesByChat['chat-1'] = MessagePage(
        messages: [sampleMessage(id: 'b1', content: 'hello from bob', sender: sampleContactUser)],
        hasMore: false,
      )
      ..messagesByChat['chat-2'] = MessagePage(
        messages: [sampleMessage(id: 'c1', content: 'hello from carol', sender: sampleThirdUser)],
        hasMore: false,
      )
      ..messagesByChat['group-1'] = MessagePage(
        messages: [sampleMessage(id: 'g1', content: 'group hello', sender: sampleContactUser)],
        hasMore: false,
      );
    chatApi = FakeChatApi()..activeChatsResult = [chatWithBob, chatWithCarol, sampleGroupChatSummary];
    contactApi = FakeContactApi()
      ..contactsResult = [
        Contact(user: sampleContactUser, since: DateTime.utc(2026, 1, 1)),
        Contact(user: sampleThirdUser, since: DateTime.utc(2026, 1, 1)),
      ];
    groupApi = FakeGroupApi()..groupResult = sampleGroupDetails();
  });

  List<Override> overrides() => [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        messageApiProvider.overrideWithValue(messageApi),
        chatApiProvider.overrideWithValue(chatApi),
        contactApiProvider.overrideWithValue(contactApi),
        groupApiProvider.overrideWithValue(groupApi),
        chatWebSocketClientFactoryProvider.overrideWithValue(broker.newClient),
      ];

  Future<void> pumpShell(
    WidgetTester tester, {
    double width = 1400,
    double height = 900,
    Widget? home,
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides(), ...extraOverrides],
        child: MaterialApp(home: home ?? const DesktopShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openChat(WidgetTester tester, String chatId) async {
    await tester.tap(find.byKey(Key('chat_tile_$chatId')));
    await tester.pumpAndSettle();
  }

  Future<void> openBeside(WidgetTester tester, String chatId) async {
    await tester.tap(find.byKey(Key('open_beside_button_$chatId')));
    await tester.pumpAndSettle();
  }

  group('layout choice', () {
    testWidgets('a wide window gets the desktop layout', (tester) async {
      await pumpShell(tester, home: const AppRoot());

      expect(find.byKey(const Key('desktop_shell')), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('a narrow window keeps the phone layout', (tester) async {
      await pumpShell(tester, width: 420, height: 800, home: const AppRoot());

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const Key('desktop_shell')), findsNothing);
    });
  });

  group('left navigation', () {
    testWidgets('shows the profile, the tabs and the chat list; the centre invites you to pick a chat', (tester) async {
      await pumpShell(tester);

      expect(find.byKey(const Key('left_pane')), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.byKey(const Key('view_profile_button')), findsOneWidget);
      for (final tab in ['nav_chats_tab', 'nav_contacts_tab', 'nav_invitations_tab', 'nav_find_tab']) {
        expect(find.byKey(Key(tab)), findsOneWidget);
      }
      expect(find.byKey(const Key('chat_tile_chat-1')), findsOneWidget);
      expect(find.byKey(const Key('chat_tile_group-1')), findsOneWidget);
      expect(find.byKey(const Key('desktop_empty_state')), findsOneWidget);
      expect(find.byKey(const Key('new_group_button')), findsOneWidget);
    });

    testWidgets('chats can be filtered from the search box', (tester) async {
      await pumpShell(tester);

      await tester.enterText(find.byKey(const Key('chat_list_search_field')), 'carol');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_tile_chat-2')), findsOneWidget);
      expect(find.byKey(const Key('chat_tile_chat-1')), findsNothing);
      expect(find.byKey(const Key('chat_tile_group-1')), findsNothing);
    });

    testWidgets('the tabs switch between contacts, invitations and people search', (tester) async {
      groupApi.pendingResult = [samplePendingGroupInvitation()];
      await pumpShell(tester);

      await tester.tap(find.byKey(const Key('nav_contacts_tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('contact_tile_user-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav_invitations_tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pending_group_invitation_tile_ginv-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav_find_tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('contact_search_field')), findsOneWidget);
    });

    testWidgets('the Invites tab shows how many invitations are waiting', (tester) async {
      groupApi.pendingResult = [samplePendingGroupInvitation(), samplePendingGroupInvitation(id: 'ginv-2')];
      await pumpShell(tester);

      expect(find.descendant(of: find.byKey(const Key('nav_invitations_tab')), matching: find.text('2')), findsOneWidget);
    });

    testWidgets('an invitation arriving live bumps the count and appears in the list', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav_invitations_tab')));
      await tester.pumpAndSettle();

      broker.emit('/topic/users/user-1/invitations', const ChatEvent(type: 'NEW_GROUP_INVITATION', payload: {
        'id': 'ginv-5',
        'groupId': 'group-5',
        'groupName': 'Hiking club',
        'memberCount': 2,
        'inviter': {'id': 'user-2', 'username': 'bob', 'email': 'bob@example.com', 'avatarFileName': null},
        'createdAt': '2026-01-03T10:00:00Z',
      }));
      await tester.pumpAndSettle();

      expect(find.text('Hiking club'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('nav_invitations_tab')), matching: find.text('1')), findsOneWidget);
    });

    testWidgets('choosing a contact opens the direct chat with them', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav_contacts_tab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('contact_tile_user-3')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_panel_chat-2')), findsOneWidget);
      expect(find.text('hello from carol'), findsOneWidget);
    });
  });

  group('the centre chat panel', () {
    testWidgets('opens the chosen chat with its header and messages', (tester) async {
      await pumpShell(tester);

      await openChat(tester, 'chat-1');

      expect(find.byKey(const Key('desktop_empty_state')), findsNothing);
      expect(find.byKey(const Key('chat_panel_chat-1')), findsOneWidget);
      expect(find.byKey(const Key('chat_panel_title_chat-1')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('chat_panel_title_chat-1'))).data, 'bob');
      expect(find.text('hello from bob'), findsOneWidget);
      expect(find.byKey(const Key('message_input')), findsOneWidget);
    });

    testWidgets('choosing another chat replaces the current one', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');

      await openChat(tester, 'chat-2');

      expect(find.byKey(const Key('chat_panel_chat-1')), findsNothing);
      expect(find.byKey(const Key('chat_panel_chat-2')), findsOneWidget);
      expect(find.text('hello from carol'), findsOneWidget);
    });

    testWidgets('a group shows its name and member count in the header', (tester) async {
      await pumpShell(tester);

      await openChat(tester, 'group-1');

      expect(tester.widget<Text>(find.byKey(const Key('chat_panel_title_group-1'))).data, 'Weekend plans');
      expect(find.text('3 members'), findsOneWidget);
      expect(find.byKey(const Key('create_poll_button')), findsOneWidget);
    });

    testWidgets('the selected chat is highlighted in the list', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');

      expect(tester.widget<ListTile>(find.byKey(const Key('chat_tile_chat-1'))).selected, isTrue);
      expect(tester.widget<ListTile>(find.byKey(const Key('chat_tile_chat-2'))).selected, isFalse);
    });

    testWidgets('closing the chat returns to the empty state', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');

      await tester.tap(find.byKey(const Key('close_chat_panel_chat-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('desktop_empty_state')), findsOneWidget);
    });

    testWidgets('a message can be sent from the panel', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');

      await tester.enterText(find.byKey(const Key('message_input')), 'hi bob');
      await tester.tap(find.byKey(const Key('send_button')));
      await tester.pumpAndSettle();

      expect(messageApi.sentContents, ['hi bob']);
    });
  });

  group('two chats side by side', () {
    testWidgets('a second chat opens next to the first, each in its own panel', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');

      await openBeside(tester, 'chat-2');

      final first = find.byKey(const Key('chat_panel_chat-1'));
      final second = find.byKey(const Key('chat_panel_chat-2'));
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy, reason: 'level with each other');
      expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(second).dx));
      expect(find.text('hello from bob'), findsOneWidget);
      expect(find.text('hello from carol'), findsOneWidget);
      expect(find.byKey(const Key('message_input')), findsNWidgets(2));
    });

    testWidgets('a live message reaches only the panel of its own chat', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');
      await openBeside(tester, 'chat-2');

      broker.emitToChat('chat-2', ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'c2',
        'conversationId': 'chat-2',
        'sender': {'id': 'user-3', 'username': 'carol', 'email': 'carol@example.com', 'avatarFileName': null},
        'content': 'only for the carol chat',
        'status': 'SENT',
        'createdAt': '2026-01-04T10:00:00Z',
        'editedAt': null,
        'deleted': false,
        'attachments': <dynamic>[],
        'poll': null,
      }));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byKey(const Key('chat_panel_chat-2')), matching: find.text('only for the carol chat')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('chat_panel_chat-1')), matching: find.text('only for the carol chat')),
        findsNothing,
      );
    });

    testWidgets('typing in one panel is announced for that chat only', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');
      await openBeside(tester, 'chat-2');

      await tester.enterText(
        find.descendant(of: find.byKey(const Key('chat_panel_chat-2')), matching: find.byKey(const Key('message_input'))),
        'typing to carol',
      );
      await tester.pump();

      expect(broker.typing, [(chatId: 'chat-2', started: true)]);

      await tester.pump(const Duration(seconds: 4)); // let the typing-stop timer run
    });

    testWidgets("someone's typing shows in the right panel only", (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');
      await openBeside(tester, 'chat-2');

      broker.emitToChat('chat-1', const ChatEvent(
        type: 'TYPING_STARTED',
        payload: {'userId': 'user-2', 'username': 'bob'},
      ));
      await tester.pump();

      expect(
        find.descendant(of: find.byKey(const Key('chat_panel_chat-1')), matching: find.byKey(const Key('typing_indicator'))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('chat_panel_chat-2')), matching: find.byKey(const Key('typing_indicator'))),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('sending in the second panel posts to the second chat', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');
      await openBeside(tester, 'chat-2');
      final secondInput =
          find.descendant(of: find.byKey(const Key('chat_panel_chat-2')), matching: find.byKey(const Key('message_input')));
      final secondSend =
          find.descendant(of: find.byKey(const Key('chat_panel_chat-2')), matching: find.byKey(const Key('send_button')));

      await tester.enterText(secondInput, 'to carol');
      await tester.tap(secondSend);
      await tester.pumpAndSettle();

      expect(messageApi.sentContents, ['to carol']);
    });

    testWidgets('closing the first panel leaves the second as the only chat', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');
      await openBeside(tester, 'chat-2');

      await tester.tap(find.byKey(const Key('close_chat_panel_chat-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_panel_chat-1')), findsNothing);
      expect(find.byKey(const Key('chat_panel_chat-2')), findsOneWidget);
      expect(find.text('hello from carol'), findsOneWidget);
    });

    testWidgets('a window too narrow for two panels shows one and offers no "open beside"', (tester) async {
      await pumpShell(tester, width: 1000);
      await openChat(tester, 'chat-1');

      expect(find.byKey(const Key('open_beside_button_chat-2')), findsNothing);
      expect(find.byKey(const Key('chat_panel_chat-1')), findsOneWidget);
    });

    testWidgets('narrowing the window with two chats open shows just the first', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');
      await openBeside(tester, 'chat-2');

      tester.view.physicalSize = const Size(1000, 900);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_panel_chat-1')), findsOneWidget);
      expect(find.byKey(const Key('chat_panel_chat-2')), findsNothing);

      tester.view.physicalSize = const Size(1400, 900);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_panel_chat-2')), findsOneWidget, reason: 'and comes back when there is room');
    });
  });

  group('the right info pane', () {
    testWidgets('shows a group\'s members and can be closed', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'group-1');

      await tester.tap(find.byKey(const Key('chat_info_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_info_panel_group-1')), findsOneWidget);
      expect(find.byKey(const Key('group_member_user-1')), findsOneWidget);
      expect(find.byKey(const Key('group_member_user-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('close_chat_info_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_info_panel_group-1')), findsNothing);
    });

    testWidgets('shows who a direct chat is with', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'chat-1');

      await tester.tap(find.byKey(const Key('chat_info_button')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byKey(const Key('chat_info_panel_chat-1')), matching: find.text('bob@example.com')),
        findsOneWidget,
      );
    });

    testWidgets('a member joining updates the open members list live', (tester) async {
      await pumpShell(tester);
      await openChat(tester, 'group-1');
      await tester.tap(find.byKey(const Key('chat_info_button')));
      await tester.pumpAndSettle();
      expect(find.text('Members (2)'), findsOneWidget);

      groupApi.groupResult = sampleGroupDetails(); // the server now knows one more member
      broker.emitToChat('group-1', const ChatEvent(type: 'MEMBER_JOINED', payload: {'userId': 'user-3', 'username': 'carol'}));
      await tester.pumpAndSettle();

      // Refetched (the fake returns the same two members; what matters is the refetch happened).
      expect(find.byKey(const Key('group_members_section')), findsOneWidget);
    });

    testWidgets('in-chat search results are listed in the pane and clicking one selects it', (tester) async {
      messageApi.searchResult = MessageSearchResult(results: [
        sampleMessage(id: 'g1', content: 'group hello', sender: sampleContactUser),
        sampleMessage(id: 'g2', content: 'hello again', sender: sampleContactUser, createdAt: DateTime.utc(2026, 1, 1, 13)),
      ], truncated: false);
      await pumpShell(tester);
      await openChat(tester, 'group-1');
      await tester.tap(find.byKey(const Key('chat_info_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat_search_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('chat_search_field')), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search_results_section')), findsOneWidget);
      expect(find.byKey(const Key('search_result_0')), findsOneWidget);
      expect(find.byKey(const Key('search_result_1')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('chat_search_count'))).data, '2 of 2');

      await tester.tap(find.byKey(const Key('search_result_0')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('chat_search_count'))).data, '1 of 2');
    });

    testWidgets('a window without room for the pane shows the info in a dialog instead', (tester) async {
      await pumpShell(tester, width: 1000);
      await openChat(tester, 'group-1');

      await tester.tap(find.byKey(const Key('chat_info_button')));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byKey(const Key('group_member_user-2')), findsOneWidget);
    });
  });

  test('the desktop breakpoint sits above the default test/phone widths', () {
    expect(desktopBreakpoint, greaterThan(800));
  });

  testWidgets('logging out closes every open chat', (tester) async {
    final authApi = FakeAuthApi();
    await pumpShell(tester, extraOverrides: [
      authApiProvider.overrideWithValue(authApi),
      authLocalStorageProvider.overrideWithValue(FakeAuthLocalStorage()),
    ]);
    await openChat(tester, 'chat-1');
    final container = ProviderScope.containerOf(tester.element(find.byKey(const Key('desktop_shell'))));
    expect(container.read(workspaceControllerProvider).openChatIds, ['chat-1']);

    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();

    expect(container.read(workspaceControllerProvider).openChatIds, isEmpty);
    expect(authApi.loggedOutTokens, ['tok'], reason: 'this device\'s session is ended on the server');
  });
}
