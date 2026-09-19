import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/chat_search_providers.dart';
import 'package:mobile_messenger/features/chat/domain/message.dart';
import 'package:mobile_messenger/features/chat/domain/message_page.dart';
import 'package:mobile_messenger/features/chat/domain/message_search_result.dart';
import 'package:mobile_messenger/features/chat/presentation/chat_screen.dart';

import '../../support/fakes.dart';

/// A chat of 40 messages, "note 1" .. "note 40", except three that mention
/// "friday" (one in different case) - far enough apart that reaching one from
/// another means scrolling.
List<Message> _history({int from = 1, int to = 40}) => [
      for (var i = from; i <= to; i++)
        sampleMessage(
          id: 'm$i',
          content: switch (i) {
            5 => 'the deadline is friday',
            20 => 'friday standup moved',
            38 => 'Friday dinner?',
            _ => 'note $i',
          },
          createdAt: DateTime.utc(2026, 1, 1, 0, i),
        ),
    ];

/// The searchable subset, oldest first, as the server returns it.
MessageSearchResult _fridayResults({bool truncated = false}) => MessageSearchResult(
      results: _history().where((m) => m.content!.toLowerCase().contains('friday')).toList(),
      truncated: truncated,
    );

void main() {
  late FakeMessageApi messageApi;
  late FakeChatApi chatApi;
  late FakeChatWebSocketClient wsClient;

  setUp(() {
    messageApi = FakeMessageApi()
      ..loadMessagesResult = MessagePage(messages: _history(), hasMore: false);
    chatApi = FakeChatApi()..activeChatsResult = [];
    wsClient = FakeChatWebSocketClient();
  });

  List<Override> overrides() => [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        messageApiProvider.overrideWithValue(messageApi),
        chatApiProvider.overrideWithValue(chatApi),
        chatWebSocketClientFactoryProvider.overrideWithValue(() => wsClient),
      ];

  group('ChatSearchController', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      // autoDispose: keep it alive for the whole test.
      container.listen(chatSearchControllerProvider('chat-1'), (_, _) {});
    });

    ChatSearchController controller() => container.read(chatSearchControllerProvider('chat-1').notifier);
    ChatSearchState state() => container.read(chatSearchControllerProvider('chat-1'));

    test('starts closed with nothing searched', () {
      expect(state().active, isFalse);
      expect(state().hasQuery, isFalse);
      expect(state().hasResults, isFalse);
    });

    test('finding several matches selects the most recent one first', () async {
      messageApi.searchResult = _fridayResults();
      controller().open();

      await controller().search('friday');

      expect(messageApi.searchedQueries, ['friday']);
      expect(state().results.map((m) => m.id), ['m5', 'm20', 'm38']);
      expect(state().current!.id, 'm38');
      expect(state().currentIndex, 2);
    });

    test('previous and next move through the matches and wrap around at both ends', () async {
      messageApi.searchResult = _fridayResults();
      await controller().search('friday');

      controller().previous();
      expect(state().current!.id, 'm20');
      controller().previous();
      expect(state().current!.id, 'm5');
      controller().previous();
      expect(state().current!.id, 'm38', reason: 'wraps from the oldest to the newest');
      controller().next();
      expect(state().current!.id, 'm5', reason: 'wraps from the newest to the oldest');
      controller().next();
      expect(state().current!.id, 'm20');
    });

    test('a single match is its own next and previous', () async {
      messageApi.searchResult = MessageSearchResult(results: [_history()[4]], truncated: false);
      await controller().search('deadline');

      controller().next();
      expect(state().current!.id, 'm5');
      controller().previous();
      expect(state().current!.id, 'm5');
    });

    test('no matches is reported, not treated as an error', () async {
      controller().open();
      await controller().search('zebra');

      expect(state().noMatches, isTrue);
      expect(state().results, isEmpty);
      expect(state().error, isNull);
      controller().next(); // must not throw with nothing to move to
      controller().previous();
    });

    test('a blank query clears the results and never calls the server', () async {
      messageApi.searchResult = _fridayResults();
      await controller().search('friday');

      await controller().search('   ');

      expect(state().hasQuery, isFalse);
      expect(state().results, isEmpty);
      expect(messageApi.searchedQueries, ['friday']);
    });

    test('a failed search shows an error and no stale results', () async {
      messageApi.searchResult = _fridayResults();
      await controller().search('friday');
      messageApi.searchError = const NetworkUnavailableException();

      await controller().search('friday standup');

      expect(state().error, const NetworkUnavailableException().message);
      expect(state().results, isEmpty);
      expect(state().loading, isFalse);
    });

    test('a slow search that was superseded by a newer one is discarded', () async {
      final slow = Completer<MessageSearchResult>();
      messageApi.searchDelay = slow;
      final first = controller().search('friday');

      messageApi.searchDelay = null;
      messageApi.searchResult = MessageSearchResult(results: [_history()[19]], truncated: false);
      await controller().search('standup');
      slow.complete(_fridayResults());
      await first;

      expect(state().query, 'standup');
      expect(state().results.map((m) => m.id), ['m20']);
    });

    test('closing forgets the query and results', () async {
      messageApi.searchResult = _fridayResults();
      controller().open();
      await controller().search('friday');

      controller().close();

      expect(state().active, isFalse);
      expect(state().hasQuery, isFalse);
      expect(state().results, isEmpty);
    });

    test('the truncated flag from the server is kept', () async {
      messageApi.searchResult = _fridayResults(truncated: true);
      await controller().search('friday');
      expect(state().truncated, isTrue);
    });
  });

  group('in-chat search UI', () {
    Future<void> pumpChat(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(home: ChatScreen(chatId: 'chat-1')),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openSearch(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('chat_search_button')));
      await tester.pumpAndSettle();
    }

    Future<void> searchFor(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const Key('chat_search_field')), text);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    /// The text of every highlighted (marked) span inside a bubble's content.
    List<String> marks(WidgetTester tester, String messageId) {
      final richText = tester.widget<RichText>(find.descendant(
        of: find.byKey(Key('message_content_$messageId')),
        matching: find.byType(RichText),
      ));
      final marked = <String>[];
      richText.text.visitChildren((span) {
        if (span is TextSpan && span.style?.backgroundColor != null && span.text != null) {
          marked.add(span.text!);
        }
        return true;
      });
      return marked;
    }

    String countLabel(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('chat_search_count'))).data!;

    testWidgets('the search bar opens from the header and closes again', (tester) async {
      await pumpChat(tester);
      expect(find.byKey(const Key('chat_search_bar')), findsNothing);

      await openSearch(tester);
      expect(find.byKey(const Key('chat_search_bar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_search_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_search_bar')), findsNothing);
    });

    testWidgets('many matches: shows a count, highlights the text and starts on the newest', (tester) async {
      messageApi.searchResult = _fridayResults();
      await pumpChat(tester);
      await openSearch(tester);

      await searchFor(tester, 'friday');

      expect(countLabel(tester), '3 of 3');
      expect(find.byKey(const Key('message_bubble_m38')), findsOneWidget);
      expect(marks(tester, 'm38'), ['Friday'], reason: 'matching is case-insensitive and keeps the original case');
      expect(messageApi.searchedQueries, ['friday']);
    });

    testWidgets('previous/next jump to matches that were off-screen and wrap around', (tester) async {
      messageApi.searchResult = _fridayResults();
      await pumpChat(tester);
      await openSearch(tester);
      await searchFor(tester, 'friday');
      expect(find.byKey(const Key('message_bubble_m5')), findsNothing, reason: 'the oldest match starts off-screen');

      await tester.tap(find.byKey(const Key('chat_search_previous')));
      await tester.pumpAndSettle();
      expect(countLabel(tester), '2 of 3');
      expect(find.byKey(const Key('message_bubble_m20')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_search_previous')));
      await tester.pumpAndSettle();
      expect(countLabel(tester), '1 of 3');
      expect(find.byKey(const Key('message_bubble_m5')), findsOneWidget, reason: 'jumped back to the oldest match');
      expect(marks(tester, 'm5'), ['friday']);

      await tester.tap(find.byKey(const Key('chat_search_previous')));
      await tester.pumpAndSettle();
      expect(countLabel(tester), '3 of 3', reason: 'wraps around to the newest');
      expect(find.byKey(const Key('message_bubble_m38')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_search_next')));
      await tester.pumpAndSettle();
      expect(countLabel(tester), '1 of 3', reason: 'and forward again');
      expect(find.byKey(const Key('message_bubble_m5')), findsOneWidget);
    });

    testWidgets('a single match shows "1 of 1"', (tester) async {
      messageApi.searchResult = MessageSearchResult(results: [_history()[4]], truncated: false);
      await pumpChat(tester);
      await openSearch(tester);

      await searchFor(tester, 'deadline');

      expect(countLabel(tester), '1 of 1');
      expect(find.byKey(const Key('message_bubble_m5')), findsOneWidget);
      expect(marks(tester, 'm5'), ['deadline']);
    });

    testWidgets('no matches says so and disables the arrows', (tester) async {
      await pumpChat(tester);
      await openSearch(tester);

      await searchFor(tester, 'zebra');

      expect(find.byKey(const Key('chat_search_no_matches')), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('chat_search_next'))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const Key('chat_search_previous'))).onPressed, isNull);
    });

    testWidgets('clearing the query removes the count and the highlights', (tester) async {
      messageApi.searchResult = _fridayResults();
      await pumpChat(tester);
      await openSearch(tester);
      await searchFor(tester, 'friday');
      expect(marks(tester, 'm38'), isNotEmpty);

      await searchFor(tester, '');

      expect(find.byKey(const Key('chat_search_count')), findsNothing);
      expect(find.byKey(const Key('chat_search_no_matches')), findsNothing);
      // With no query the bubble is plain text again.
      expect(find.text('Friday dinner?'), findsOneWidget);
      expect(find.byKey(const Key('chat_search_bar')), findsOneWidget, reason: 'clearing does not close the bar');
    });

    testWidgets('typing searches on its own after a short pause', (tester) async {
      messageApi.searchResult = _fridayResults();
      await pumpChat(tester);
      await openSearch(tester);

      await tester.enterText(find.byKey(const Key('chat_search_field')), 'friday');
      expect(messageApi.searchedQueries, isEmpty, reason: 'not on every keystroke');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(messageApi.searchedQueries, ['friday']);
      expect(countLabel(tester), '3 of 3');
    });

    testWidgets('a search failure is shown in the bar', (tester) async {
      messageApi.searchError = const NetworkUnavailableException();
      await pumpChat(tester);
      await openSearch(tester);

      await searchFor(tester, 'friday');

      expect(find.byKey(const Key('chat_search_error')), findsOneWidget);
      expect(find.text(const NetworkUnavailableException().message), findsOneWidget);
    });

    testWidgets('searching and closing leaves the conversation as it was', (tester) async {
      messageApi.searchResult = _fridayResults();
      await pumpChat(tester);
      expect(messageApi.loadMessagesCallCount, 1);
      await openSearch(tester);
      await searchFor(tester, 'friday');

      await tester.tap(find.byKey(const Key('chat_search_close')));
      await tester.pumpAndSettle();

      expect(messageApi.loadMessagesCallCount, 1, reason: 'the chat was never reloaded');
      expect(find.byKey(const Key('message_list')), findsOneWidget);
      expect(find.text('Friday dinner?'), findsOneWidget, reason: 'newest messages still shown');
      expect(find.byKey(const Key('message_bubble_m38')), findsOneWidget);
    });

    testWidgets('jumping to a result older than what is loaded fetches older history first', (tester) async {
      messageApi.loadMessagesResult = MessagePage(messages: _history(from: 21), hasMore: true);
      messageApi.olderPages.add(MessagePage(messages: _history(to: 20), hasMore: false));
      messageApi.searchResult = _fridayResults();
      await pumpChat(tester);
      expect(messageApi.loadMessagesCallCount, 1);
      await openSearch(tester);
      await searchFor(tester, 'friday');

      // Go back to the oldest match (m5), which is not among the loaded messages.
      await tester.tap(find.byKey(const Key('chat_search_previous')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat_search_previous')));
      await tester.pumpAndSettle();

      expect(countLabel(tester), '1 of 3');
      expect(messageApi.loadMessagesCallCount, 2, reason: 'the older page was fetched to reach it');
      expect(find.byKey(const Key('message_bubble_m5')), findsOneWidget);
    });
  });
}
