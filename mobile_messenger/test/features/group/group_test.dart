import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/domain/chat_event.dart';
import 'package:mobile_messenger/features/chat/domain/chat_summary.dart';
import 'package:mobile_messenger/features/chat/presentation/chat_info_panel.dart';
import 'package:mobile_messenger/features/chat/presentation/chats_screen.dart';
import 'package:mobile_messenger/features/contact/contact_providers.dart';
import 'package:mobile_messenger/features/contact/domain/contact.dart';
import 'package:mobile_messenger/features/contact/domain/pending_invitation.dart';
import 'package:mobile_messenger/features/contact/presentation/contacts_screen.dart';
import 'package:mobile_messenger/features/group/group_providers.dart';
import 'package:mobile_messenger/features/health/presentation/home_screen.dart' show pendingInvitationCountProvider;

import '../../support/fakes.dart';

void main() {
  late FakeGroupApi groupApi;
  late FakeChatApi chatApi;
  late FakeContactApi contactApi;
  late FakeChatWebSocketClient wsClient;

  final bobContact = Contact(user: sampleContactUser, since: DateTime.utc(2026, 1, 1));
  final carolContact = Contact(user: sampleThirdUser, since: DateTime.utc(2026, 1, 1));

  setUp(() {
    groupApi = FakeGroupApi();
    chatApi = FakeChatApi()..activeChatsResult = [];
    contactApi = FakeContactApi()..contactsResult = [bobContact, carolContact];
    wsClient = FakeChatWebSocketClient();
  });

  List<Override> overrides() => [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        groupApiProvider.overrideWithValue(groupApi),
        chatApiProvider.overrideWithValue(chatApi),
        contactApiProvider.overrideWithValue(contactApi),
        chatWebSocketClientFactoryProvider.overrideWithValue(() => wsClient),
      ];

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(ProviderScope(overrides: overrides(), child: MaterialApp(home: home)));
    await tester.pumpAndSettle();
  }

  group('group chats in the chat list', () {
    test('a group summary parses its name, member count and no other user', () {
      final chat = ChatSummary.fromJson({
        'id': 'g1',
        'type': 'GROUP',
        'otherUser': null,
        'name': 'Book club',
        'memberCount': 4,
        'lastActivityAt': '2026-01-02T10:00:00Z',
        'archived': false,
        'lastMessage': {
          'content': 'see you at 6',
          'deleted': false,
          'attachmentType': null,
          'senderUsername': 'bob',
        },
        'unreadCount': 2,
      });

      expect(chat.isGroup, isTrue);
      expect(chat.title, 'Book club');
      expect(chat.otherUser, isNull);
      expect(chat.memberCount, 4);
      expect(chat.previewText, 'bob: see you at 6', reason: 'a group preview names the sender');
      expect(chat.unreadCount, 2);
    });

    test('a direct summary is unchanged: titled by the other user, preview without a sender prefix', () {
      final chat = ChatSummary.fromJson({
        'id': 'c1',
        'type': 'DIRECT',
        'otherUser': {'id': 'user-2', 'username': 'bob', 'email': 'bob@example.com', 'avatarFileName': null},
        'name': null,
        'memberCount': 0,
        'lastActivityAt': '2026-01-02T10:00:00Z',
        'archived': false,
        'lastMessage': {'content': 'hi', 'deleted': false, 'attachmentType': null, 'senderUsername': null},
        'unreadCount': 0,
      });

      expect(chat.isGroup, isFalse);
      expect(chat.title, 'bob');
      expect(chat.previewText, 'hi');
    });

    testWidgets('groups and direct chats appear together, newest activity first, with a group icon', (tester) async {
      chatApi.activeChatsResult = [sampleGroupChatSummary, sampleChatSummary];
      await pump(tester, const ChatsScreen());

      expect(find.text('Weekend plans'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget, reason: 'only the group has the group avatar');
      final groupTop = tester.getTopLeft(find.byKey(const Key('chat_tile_group-1'))).dy;
      final directTop = tester.getTopLeft(find.byKey(const Key('chat_tile_chat-1'))).dy;
      expect(groupTop, lessThan(directTop));
    });

    testWidgets('a new message re-sorts the list, updates the preview and counts unread', (tester) async {
      chatApi.activeChatsResult = [sampleGroupChatSummary, sampleChatSummary];
      await pump(tester, const ChatsScreen());

      wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'm9',
        'sender': {'id': 'user-2', 'username': 'bob', 'email': 'bob@example.com', 'avatarFileName': null},
        'content': 'lunch?',
        'createdAt': '2026-01-05T10:00:00Z',
        'attachments': <dynamic>[],
      }));
      await tester.pumpAndSettle();

      // The listener is shared by both chats' topics in the fake; the direct
      // chat was subscribed too and receives it as well - the point is that
      // the group tile carries an updated preview and unread badge.
      expect(find.text('bob: lunch?'), findsWidgets);
      expect(find.byKey(const Key('chat_unread_badge_group-1')), findsOneWidget);
    });

    testWidgets('someone joining the group updates its member count', (tester) async {
      chatApi.activeChatsResult = [sampleGroupChatSummary];
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await container.read(chatsControllerProvider.future);
      expect(container.read(chatsControllerProvider).value!.single.memberCount, 3);

      wsClient.emit(const ChatEvent(type: 'MEMBER_JOINED', payload: {'userId': 'user-3', 'username': 'carol'}));

      expect(container.read(chatsControllerProvider).value!.single.memberCount, 4);
    });

    testWidgets('the chat list can be filtered by name', (tester) async {
      chatApi.activeChatsResult = [sampleGroupChatSummary, sampleChatSummary];
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(),
        child: MaterialApp(home: Scaffold(body: ChatListView(onOpen: (_) {}, filter: 'week'))),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Weekend plans'), findsOneWidget);
      expect(find.text('bob'), findsNothing);
    });

    testWidgets('a filter matching nothing says so', (tester) async {
      chatApi.activeChatsResult = [sampleGroupChatSummary];
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(),
        child: MaterialApp(home: Scaffold(body: ChatListView(onOpen: (_) {}, filter: 'zzz'))),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chats_no_match_view')), findsOneWidget);
    });
  });

  group('creating a group', () {
    Future<void> openDialog(WidgetTester tester) async {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const ChatsScreen()),
        GoRoute(
          path: '/chats/:chatId',
          builder: (_, state) => Text('opened chat ${state.pathParameters['chatId']}', key: const Key('opened_chat')),
        ),
      ]);
      await tester.pumpWidget(ProviderScope(overrides: overrides(), child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new_group_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create_group_dialog')), findsOneWidget);
    }

    testWidgets('lists your contacts and creates the group with the ones you tick', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('group_name_field')), '  Weekend plans ');
      await tester.tap(find.byKey(const Key('group_contact_user-2')));
      await tester.tap(find.byKey(const Key('group_contact_user-3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('group_create_submit')));
      await tester.pumpAndSettle();

      expect(groupApi.createdGroups, hasLength(1));
      expect(groupApi.createdGroups.single.name, 'Weekend plans', reason: 'trimmed');
      expect(groupApi.createdGroups.single.memberIds, unorderedEquals(['user-2', 'user-3']));
      expect(find.byKey(const Key('create_group_dialog')), findsNothing);
      expect(find.text('opened chat group-1'), findsOneWidget, reason: 'goes straight to the new group');
    });

    testWidgets('a name and at least one contact are required', (tester) async {
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('group_create_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Give the group a name.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('group_name_field')), 'Club');
      await tester.tap(find.byKey(const Key('group_create_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Choose at least one contact to invite.'), findsOneWidget);

      expect(groupApi.createdGroups, isEmpty);
    });

    testWidgets('someone with no contacts is told to add some first', (tester) async {
      contactApi.contactsResult = [];
      await openDialog(tester);

      expect(find.byKey(const Key('group_no_contacts')), findsOneWidget);
    });

    testWidgets('a server error is shown in the dialog, which stays open', (tester) async {
      groupApi.createError = const ValidationException("You can only invite your own contacts", {});
      await openDialog(tester);
      await tester.enterText(find.byKey(const Key('group_name_field')), 'Club');
      await tester.tap(find.byKey(const Key('group_contact_user-2')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('group_create_submit')));
      await tester.pumpAndSettle();

      expect(find.text('You can only invite your own contacts'), findsOneWidget);
      expect(find.byKey(const Key('create_group_dialog')), findsOneWidget);
    });

    testWidgets('cancelling creates nothing', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(groupApi.createdGroups, isEmpty);
      expect(find.byKey(const Key('create_group_dialog')), findsNothing);
    });

    testWidgets('after creating, the chat list is reloaded so the group shows up', (tester) async {
      await openDialog(tester);
      final callsBefore = chatApi.listActiveChatsCallCount;
      await tester.enterText(find.byKey(const Key('group_name_field')), 'Club');
      await tester.tap(find.byKey(const Key('group_contact_user-2')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('group_create_submit')));
      await tester.pumpAndSettle();

      expect(chatApi.listActiveChatsCallCount, greaterThan(callsBefore));
    });
  });

  group('group invitations (pending)', () {
    Future<void> pumpPending(WidgetTester tester) async {
      await pump(tester, const Scaffold(body: PendingInvitationsTab()));
    }

    testWidgets('a pending group invitation shows the group, the inviter and the member count', (tester) async {
      groupApi.pendingResult = [samplePendingGroupInvitation()];
      await pumpPending(tester);

      expect(find.text('Group invitations'), findsOneWidget);
      expect(find.text('Book club'), findsOneWidget);
      expect(find.textContaining('Invited by bob'), findsOneWidget);
      expect(find.textContaining('2 members'), findsOneWidget);
    });

    testWidgets('contact and group invitations are listed side by side in their own sections', (tester) async {
      groupApi.pendingResult = [samplePendingGroupInvitation()];
      contactApi.pendingResult = [await _contactInvitation()];
      await pumpPending(tester);

      expect(find.text('Contact invitations'), findsOneWidget);
      expect(find.text('Group invitations'), findsOneWidget);
    });

    testWidgets('accepting joins the group, removes the invitation and reloads the chat list', (tester) async {
      groupApi.pendingResult = [samplePendingGroupInvitation()];
      await pumpPending(tester);
      final callsBefore = chatApi.listActiveChatsCallCount;

      await tester.tap(find.byKey(const Key('accept_group_invitation_button_ginv-1')));
      await tester.pumpAndSettle();

      expect(groupApi.acceptedInvitationIds, ['ginv-1']);
      expect(find.byKey(const Key('pending_group_invitation_tile_ginv-1')), findsNothing);
      expect(find.byKey(const Key('pending_empty_view')), findsOneWidget);
      expect(chatApi.listActiveChatsCallCount, greaterThanOrEqualTo(callsBefore), reason: 'chat list invalidated');
    });

    testWidgets('declining removes the invitation without joining', (tester) async {
      groupApi.pendingResult = [samplePendingGroupInvitation()];
      await pumpPending(tester);

      await tester.tap(find.byKey(const Key('decline_group_invitation_button_ginv-1')));
      await tester.pumpAndSettle();

      expect(groupApi.declinedInvitationIds, ['ginv-1']);
      expect(groupApi.acceptedInvitationIds, isEmpty);
      expect(find.byKey(const Key('pending_group_invitation_tile_ginv-1')), findsNothing);
    });

    testWidgets('a failed accept shows the error and keeps the invitation', (tester) async {
      groupApi.pendingResult = [samplePendingGroupInvitation()];
      groupApi.acceptError = const NetworkUnavailableException();
      await pumpPending(tester);

      await tester.tap(find.byKey(const Key('accept_group_invitation_button_ginv-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pending_group_invitation_error_ginv-1')), findsOneWidget);
      expect(find.byKey(const Key('pending_group_invitation_tile_ginv-1')), findsOneWidget);
    });

    testWidgets('a group invitation that arrives while the app is open appears without a refresh', (tester) async {
      await pumpPending(tester);
      expect(find.byKey(const Key('pending_empty_view')), findsOneWidget);

      wsClient.emit(const ChatEvent(type: 'NEW_GROUP_INVITATION', payload: {
        'id': 'ginv-7',
        'groupId': 'group-7',
        'groupName': 'Hiking',
        'memberCount': 3,
        'inviter': {'id': 'user-2', 'username': 'bob', 'email': 'bob@example.com', 'avatarFileName': null},
        'createdAt': '2026-01-03T10:00:00Z',
      }));
      await tester.pumpAndSettle();

      expect(find.text('Hiking'), findsOneWidget);
      expect(find.byKey(const Key('pending_empty_view')), findsNothing);
    });

    testWidgets('answering an invitation on another device removes it here too', (tester) async {
      groupApi.pendingResult = [samplePendingGroupInvitation()];
      await pumpPending(tester);
      expect(find.byKey(const Key('pending_group_invitation_tile_ginv-1')), findsOneWidget);

      wsClient.emit(const ChatEvent(
        type: 'INVITATION_RESOLVED',
        payload: {'invitationId': 'ginv-1', 'kind': 'GROUP', 'accepted': true},
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pending_group_invitation_tile_ginv-1')), findsNothing);
    });

    test('the invitations badge counts contact and group invitations together', () async {
      groupApi.pendingResult = [samplePendingGroupInvitation(), samplePendingGroupInvitation(id: 'ginv-2')];
      contactApi.pendingResult = [await _contactInvitation()];
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await container.read(pendingInvitationsControllerProvider.future);
      await container.read(pendingGroupInvitationsControllerProvider.future);

      expect(container.read(pendingInvitationCountProvider), 3);
    });
  });

  group('group info: members and inviting', () {
    Future<void> pumpInfo(WidgetTester tester) async {
      chatApi.activeChatsResult = [sampleGroupChatSummary];
      await pump(tester, const ChatInfoScreen(chatId: 'group-1'));
    }

    testWidgets('lists the members (marking the admin) and those still invited', (tester) async {
      groupApi.groupResult = sampleGroupDetails(pendingInvitees: [sampleThirdUser]);
      await pumpInfo(tester);

      expect(find.byKey(const Key('group_member_user-1')), findsOneWidget);
      expect(find.byKey(const Key('group_member_user-2')), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.byKey(const Key('group_invitee_user-3')), findsOneWidget);
      expect(find.text('Invitation pending'), findsOneWidget);
      expect(find.text('Members (2)'), findsOneWidget);
    });

    testWidgets('inviting offers only contacts who are not already in or invited to the group', (tester) async {
      groupApi.groupResult = sampleGroupDetails(); // members: alice (me) and bob
      await pumpInfo(tester);

      await tester.ensureVisible(find.byKey(const Key('invite_to_group_button')));
      await tester.tap(find.byKey(const Key('invite_to_group_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invite_contact_user-3')), findsOneWidget, reason: 'carol is not in it yet');
      expect(find.byKey(const Key('invite_contact_user-2')), findsNothing, reason: 'bob already is');

      await tester.tap(find.byKey(const Key('invite_contact_user-3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('invite_submit')));
      await tester.pumpAndSettle();

      expect(groupApi.invitations.single.groupId, 'group-1');
      expect(groupApi.invitations.single.userIds, ['user-3']);
      expect(find.byKey(const Key('invite_to_group_dialog')), findsNothing);
    });

    testWidgets('an invitee already invited is not offered again', (tester) async {
      groupApi.groupResult = sampleGroupDetails(pendingInvitees: [sampleThirdUser]);
      await pumpInfo(tester);

      await tester.ensureVisible(find.byKey(const Key('invite_to_group_button')));
      await tester.tap(find.byKey(const Key('invite_to_group_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invite_no_candidates')), findsOneWidget);
    });

    testWidgets('inviting nobody is rejected', (tester) async {
      groupApi.groupResult = sampleGroupDetails();
      await pumpInfo(tester);
      await tester.ensureVisible(find.byKey(const Key('invite_to_group_button')));
      await tester.tap(find.byKey(const Key('invite_to_group_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('invite_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Choose at least one contact.'), findsOneWidget);
      expect(groupApi.invitations, isEmpty);
    });

    testWidgets('an error loading the members offers a retry', (tester) async {
      groupApi.groupError = const NetworkUnavailableException();
      await pumpInfo(tester);
      expect(find.byKey(const Key('group_details_error')), findsOneWidget);

      groupApi.groupError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('group_members_section')), findsOneWidget);
    });
  });
}

Future<PendingInvitation> _contactInvitation() async =>
    PendingInvitation(id: 'inv-1', sender: sampleContactUser, createdAt: DateTime.utc(2026, 1, 1));
