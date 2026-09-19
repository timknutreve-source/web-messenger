import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/domain/chat_event.dart';
import 'package:mobile_messenger/features/chat/domain/message_page.dart';
import 'package:mobile_messenger/features/chat/domain/poll.dart';
import 'package:mobile_messenger/features/chat/presentation/chat_screen.dart';
import 'package:mobile_messenger/features/contact/domain/contact_user_summary.dart';

import '../../support/fakes.dart';

const _pizza = 'opt-1';
const _sushi = 'opt-2';

/// A poll with the given per-option tallies (pizza, sushi).
Poll _poll({
  int pizza = 0,
  int sushi = 0,
  String? mine,
  bool anonymous = false,
  List<ContactUserSummary> pizzaVoters = const [],
}) =>
    samplePoll(
      anonymous: anonymous,
      myOptionId: mine,
      options: [
        PollOption(id: _pizza, text: 'Pizza', voteCount: pizza, voters: anonymous ? null : pizzaVoters),
        PollOption(id: _sushi, text: 'Sushi', voteCount: sushi, voters: anonymous ? null : const []),
      ],
    );

void main() {
  late FakeMessageApi messageApi;
  late FakeChatApi chatApi;
  late FakePollApi pollApi;
  late FakeChatWebSocketClient wsClient;

  setUp(() {
    messageApi = FakeMessageApi();
    chatApi = FakeChatApi()..activeChatsResult = [sampleGroupChatSummary];
    pollApi = FakePollApi();
    wsClient = FakeChatWebSocketClient();
  });

  List<Override> overrides() => [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        messageApiProvider.overrideWithValue(messageApi),
        chatApiProvider.overrideWithValue(chatApi),
        pollApiProvider.overrideWithValue(pollApi),
        chatWebSocketClientFactoryProvider.overrideWithValue(() => wsClient),
      ];

  Future<void> pumpGroupChat(WidgetTester tester, {String chatId = 'group-1'}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(home: ChatScreen(chatId: chatId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  void withPoll(Poll poll, {bool mine = false}) {
    messageApi.loadMessagesResult = MessagePage(
      messages: [samplePollMessage(poll: poll, sender: mine ? sampleUserContactSummary : sampleContactUser)],
      hasMore: false,
    );
  }

  String votesLabel(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('poll_total_votes'))).data!;

  group('showing a poll', () {
    testWidgets('renders the question, its options and their vote counts', (tester) async {
      withPoll(_poll(pizza: 2, sushi: 1));
      await pumpGroupChat(tester);

      expect(find.text('Where should we eat?'), findsOneWidget);
      expect(find.text('Pizza'), findsOneWidget);
      expect(find.text('Sushi'), findsOneWidget);
      expect(find.byKey(const Key('poll_option_count_$_pizza')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('poll_option_count_$_pizza'))).data, '2');
      expect(tester.widget<Text>(find.byKey(const Key('poll_option_count_$_sushi'))).data, '1');
      expect(votesLabel(tester), '3 votes');
    });

    testWidgets('a poll nobody has voted in yet says "0 votes" and offers no retract', (tester) async {
      withPoll(_poll());
      await pumpGroupChat(tester);

      expect(votesLabel(tester), '0 votes');
      expect(find.byKey(const Key('poll_retract_button')), findsNothing);
    });

    testWidgets('a public poll is labelled public and names who voted for an option', (tester) async {
      withPoll(_poll(pizza: 2, pizzaVoters: [sampleContactUser, sampleThirdUser]));
      await pumpGroupChat(tester);

      expect(find.text('Public poll'), findsOneWidget);
      expect(find.byKey(const Key('poll_option_voters_$_pizza')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('poll_option_voters_$_pizza'))).data, 'bob, carol');
      expect(find.byKey(const Key('poll_option_voters_$_sushi')), findsNothing);
    });

    testWidgets('an anonymous poll is labelled anonymous and never shows voters', (tester) async {
      withPoll(_poll(pizza: 2, sushi: 1, anonymous: true));
      await pumpGroupChat(tester);

      expect(find.text('Anonymous poll'), findsOneWidget);
      expect(find.byKey(const Key('poll_option_voters_$_pizza')), findsNothing);
      expect(find.byKey(const Key('poll_option_voters_$_sushi')), findsNothing);
      // ...but the totals are still there.
      expect(tester.widget<Text>(find.byKey(const Key('poll_option_count_$_pizza'))).data, '2');
    });

    testWidgets("the viewer's own vote is marked, and survives reopening the chat", (tester) async {
      withPoll(_poll(pizza: 1, mine: _pizza));
      await pumpGroupChat(tester);

      expect(
        find.descendant(of: find.byKey(const Key('poll_option_$_pizza')), matching: find.byKey(const Key('poll_option_selected_icon'))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('poll_option_$_sushi')), matching: find.byKey(const Key('poll_option_selected_icon'))),
        findsNothing,
      );
      expect(find.byKey(const Key('poll_retract_button')), findsOneWidget);
    });
  });

  group('voting', () {
    testWidgets('tapping an option votes for it and shows the new tally', (tester) async {
      withPoll(_poll());
      pollApi.onVote = (current, optionId) => _poll(pizza: 1, mine: optionId);
      await pumpGroupChat(tester);

      await tester.tap(find.byKey(const Key('poll_option_$_pizza')));
      await tester.pumpAndSettle();

      expect(pollApi.votedOptionIds, [_pizza]);
      expect(votesLabel(tester), '1 vote');
      expect(
        find.descendant(of: find.byKey(const Key('poll_option_$_pizza')), matching: find.byKey(const Key('poll_option_selected_icon'))),
        findsOneWidget,
      );
    });

    testWidgets('tapping a different option changes the vote', (tester) async {
      withPoll(_poll(pizza: 1, mine: _pizza));
      pollApi.onVote = (current, optionId) => _poll(sushi: 1, mine: optionId);
      await pumpGroupChat(tester);

      await tester.tap(find.byKey(const Key('poll_option_$_sushi')));
      await tester.pumpAndSettle();

      expect(pollApi.votedOptionIds, [_sushi]);
      expect(tester.widget<Text>(find.byKey(const Key('poll_option_count_$_pizza'))).data, '0');
      expect(tester.widget<Text>(find.byKey(const Key('poll_option_count_$_sushi'))).data, '1');
      expect(votesLabel(tester), '1 vote', reason: 'still one person, one vote');
    });

    testWidgets('tapping the option already chosen retracts the vote', (tester) async {
      withPoll(_poll(pizza: 1, mine: _pizza));
      pollApi.onRetract = (_) => _poll();
      await pumpGroupChat(tester);

      await tester.tap(find.byKey(const Key('poll_option_$_pizza')));
      await tester.pumpAndSettle();

      expect(pollApi.retractCount, 1);
      expect(pollApi.votedOptionIds, isEmpty);
      expect(votesLabel(tester), '0 votes');
      expect(find.byKey(const Key('poll_retract_button')), findsNothing);
    });

    testWidgets('the "Retract vote" button takes the vote back', (tester) async {
      withPoll(_poll(sushi: 1, mine: _sushi));
      pollApi.onRetract = (_) => _poll();
      await pumpGroupChat(tester);

      await tester.tap(find.byKey(const Key('poll_retract_button')));
      await tester.pumpAndSettle();

      expect(pollApi.retractCount, 1);
      expect(votesLabel(tester), '0 votes');
    });

    testWidgets('a failed vote shows an error and leaves the poll unchanged', (tester) async {
      withPoll(_poll());
      pollApi.voteError = const NetworkUnavailableException();
      await pumpGroupChat(tester);

      await tester.tap(find.byKey(const Key('poll_option_$_pizza')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_action_error_snackbar')), findsOneWidget);
      expect(votesLabel(tester), '0 votes');
    });
  });

  group('live updates', () {
    testWidgets("someone else's vote (POLL_UPDATED) refreshes the tally", (tester) async {
      withPoll(_poll());
      await pumpGroupChat(tester);
      expect(votesLabel(tester), '0 votes');
      pollApi.getResult = _poll(pizza: 3);

      wsClient.emit(const ChatEvent(type: 'POLL_UPDATED', payload: {'pollId': 'poll-1', 'messageId': 'poll-message-1'}));
      await tester.pumpAndSettle();

      expect(pollApi.getCount, 1);
      expect(votesLabel(tester), '3 votes');
    });

    testWidgets('a delivery/read status update does not wipe the poll off its message', (tester) async {
      withPoll(_poll(pizza: 1), mine: true);
      await pumpGroupChat(tester);

      wsClient.emit(ChatEvent(type: 'MESSAGE_STATUS_UPDATED', payload: {
        'id': 'poll-message-1',
        'conversationId': 'group-1',
        'sender': {'id': 'user-1', 'username': 'alice', 'email': 'alice@example.com', 'avatarFileName': null},
        'content': 'Where should we eat?',
        'status': 'DELIVERED',
        'createdAt': '2026-01-01T12:00:00Z',
        'editedAt': null,
        'deleted': false,
        'attachments': <dynamic>[],
        'poll': null,
      }));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('poll_poll-1')), findsOneWidget);
      expect(find.text('Pizza'), findsOneWidget);
    });

    testWidgets('a new poll posted by someone else appears in the chat', (tester) async {
      messageApi.loadMessagesResult = const MessagePage(messages: [], hasMore: false);
      await pumpGroupChat(tester);

      wsClient.emit(ChatEvent(type: 'NEW_MESSAGE', payload: {
        'id': 'poll-message-1',
        'conversationId': 'group-1',
        'sender': {'id': 'user-2', 'username': 'bob', 'email': 'bob@example.com', 'avatarFileName': null},
        'content': 'Where should we eat?',
        'status': 'SENT',
        'createdAt': '2026-01-01T12:00:00Z',
        'editedAt': null,
        'deleted': false,
        'attachments': <dynamic>[],
        'poll': {
          'id': 'poll-1',
          'messageId': 'poll-message-1',
          'question': 'Where should we eat?',
          'anonymous': false,
          'totalVotes': 0,
          'myOptionId': null,
          'options': [
            {'id': _pizza, 'text': 'Pizza', 'voteCount': 0, 'voters': <dynamic>[]},
            {'id': _sushi, 'text': 'Sushi', 'voteCount': 0, 'voters': <dynamic>[]},
          ],
        },
      }));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('poll_poll-1')), findsOneWidget);
      expect(find.text('Sushi'), findsOneWidget);
    });
  });

  group('creating a poll', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('create_poll_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create_poll_dialog')), findsOneWidget);
    }

    Future<void> fill(WidgetTester tester, {String question = '', List<String> options = const []}) async {
      await tester.enterText(find.byKey(const Key('poll_question_field')), question);
      for (var i = 0; i < options.length; i++) {
        await tester.enterText(find.byKey(Key('poll_option_field_$i')), options[i]);
      }
    }

    testWidgets('the poll button exists in a group chat but not in a direct chat', (tester) async {
      await pumpGroupChat(tester);
      expect(find.byKey(const Key('create_poll_button')), findsOneWidget);

      // A direct chat: 'chat-1' is not a group in the chat list.
      chatApi.activeChatsResult = [sampleChatSummary];
      await tester.pumpWidget(const SizedBox());
      await pumpGroupChat(tester, chatId: 'chat-1');
      expect(find.byKey(const Key('create_poll_button')), findsNothing);
    });

    testWidgets('creates a public poll and shows it in the chat', (tester) async {
      pollApi.createResult = samplePollMessage(poll: _poll(), sender: sampleUserContactSummary);
      await pumpGroupChat(tester);
      await openDialog(tester);

      await fill(tester, question: 'Where should we eat?', options: ['Pizza', 'Sushi']);
      await tester.tap(find.byKey(const Key('poll_create_submit')));
      await tester.pumpAndSettle();

      expect(pollApi.createdPolls.single.question, 'Where should we eat?');
      expect(pollApi.createdPolls.single.options, ['Pizza', 'Sushi']);
      expect(pollApi.createdPolls.single.anonymous, isFalse);
      expect(find.byKey(const Key('create_poll_dialog')), findsNothing);
      expect(find.byKey(const Key('poll_poll-1')), findsOneWidget);
    });

    testWidgets('the anonymous switch makes an anonymous poll', (tester) async {
      pollApi.createResult = samplePollMessage(poll: _poll(anonymous: true), sender: sampleUserContactSummary);
      await pumpGroupChat(tester);
      await openDialog(tester);

      await fill(tester, question: 'Secret?', options: ['Yes', 'No']);
      await tester.tap(find.byKey(const Key('poll_anonymous_switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('poll_create_submit')));
      await tester.pumpAndSettle();

      expect(pollApi.createdPolls.single.anonymous, isTrue);
      expect(find.text('Anonymous poll'), findsOneWidget);
    });

    testWidgets('requires a question and at least two different options', (tester) async {
      await pumpGroupChat(tester);
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('poll_create_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a question.'), findsOneWidget);

      await fill(tester, question: 'Q?', options: ['Only one']);
      await tester.tap(find.byKey(const Key('poll_create_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter at least 2 options.'), findsOneWidget);

      await fill(tester, question: 'Q?', options: ['Same', 'same']);
      await tester.tap(find.byKey(const Key('poll_create_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Options must all be different.'), findsOneWidget);

      expect(pollApi.createdPolls, isEmpty);
      expect(find.byKey(const Key('create_poll_dialog')), findsOneWidget, reason: 'stays open to correct');
    });

    testWidgets('options can be added up to ten and removed down to two', (tester) async {
      await pumpGroupChat(tester);
      await openDialog(tester);
      expect(find.byKey(const Key('poll_remove_option_0')), findsNothing, reason: 'two is the minimum');

      for (var i = 0; i < 8; i++) {
        await tester.ensureVisible(find.byKey(const Key('poll_add_option_button')));
        await tester.tap(find.byKey(const Key('poll_add_option_button')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('poll_option_field_9')), findsOneWidget);
      expect(find.byKey(const Key('poll_add_option_button')), findsNothing, reason: 'ten is the maximum');

      await tester.ensureVisible(find.byKey(const Key('poll_remove_option_9')));
      await tester.tap(find.byKey(const Key('poll_remove_option_9')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('poll_option_field_9')), findsNothing);
      expect(find.byKey(const Key('poll_add_option_button')), findsOneWidget);
    });

    testWidgets('cancelling creates nothing', (tester) async {
      await pumpGroupChat(tester);
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create_poll_dialog')), findsNothing);
      expect(pollApi.createdPolls, isEmpty);
    });

    testWidgets('a server rejection is shown and no poll appears', (tester) async {
      pollApi.createError = const ValidationException('Poll options must all be different', {});
      await pumpGroupChat(tester);
      await openDialog(tester);
      await fill(tester, question: 'Q?', options: ['A', 'B']);

      await tester.tap(find.byKey(const Key('poll_create_submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_action_error_snackbar')), findsOneWidget);
      expect(find.byKey(const Key('poll_poll-1')), findsNothing);
    });
  });

  group('managing a poll message', () {
    testWidgets("your own poll can be deleted but its question can't be edited", (tester) async {
      withPoll(_poll(), mine: true);
      await pumpGroupChat(tester);

      await tester.longPress(find.byKey(const Key('message_menu_poll-message-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_message_action_poll-message-1')), findsOneWidget);
      expect(find.byKey(const Key('edit_message_action_poll-message-1')), findsNothing);
    });
  });
}
