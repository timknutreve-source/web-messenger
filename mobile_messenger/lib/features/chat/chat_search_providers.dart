import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/error_presenter.dart';
import '../auth/auth_providers.dart';
import '../auth/domain/auth_state.dart';
import 'chat_room_providers.dart' show messageApiProvider;
import 'domain/message.dart';

/// The state of searching inside one chat. Kept entirely apart from the
/// chat's own message state: opening, using and closing a search never
/// touches (let alone reloads) the conversation being searched.
class ChatSearchState {
  const ChatSearchState({
    this.active = false,
    this.query = '',
    this.results = const [],
    this.currentIndex = 0,
    this.truncated = false,
    this.loading = false,
    this.error,
  });

  /// Whether the search bar is open.
  final bool active;

  /// The text last searched for ('' when nothing has been searched).
  final String query;

  /// Matches, oldest first.
  final List<Message> results;

  /// Which of [results] is the current one (the one jumped to).
  final int currentIndex;

  /// More matches exist than are listed (only the most recent are returned).
  final bool truncated;
  final bool loading;
  final String? error;

  bool get hasQuery => query.isNotEmpty;
  bool get hasResults => results.isNotEmpty;
  Message? get current => hasResults ? results[currentIndex] : null;

  /// Search finished for a non-empty query and found nothing.
  bool get noMatches => active && hasQuery && !loading && error == null && results.isEmpty;

  ChatSearchState copyWith({
    bool? active,
    String? query,
    List<Message>? results,
    int? currentIndex,
    bool? truncated,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      ChatSearchState(
        active: active ?? this.active,
        query: query ?? this.query,
        results: results ?? this.results,
        currentIndex: currentIndex ?? this.currentIndex,
        truncated: truncated ?? this.truncated,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class ChatSearchController extends Notifier<ChatSearchState> {
  ChatSearchController(this.chatId);

  final String chatId;
  int _generation = 0;

  @override
  ChatSearchState build() => const ChatSearchState();

  void open() => state = state.copyWith(active: true);

  /// Closes the search and forgets its results.
  void close() {
    _generation++;
    state = const ChatSearchState();
  }

  /// Searches for [rawQuery]; an empty query clears the results. A search
  /// superseded by a newer one (or by [close]) is discarded when it returns.
  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    final generation = ++_generation;
    if (query.isEmpty) {
      state = state.copyWith(query: '', results: const [], currentIndex: 0, truncated: false, loading: false, clearError: true);
      return;
    }
    state = state.copyWith(query: query, loading: true, clearError: true);
    try {
      final authState = await ref.read(authControllerProvider.future);
      if (authState is! AuthAuthenticated) return;
      final result = await ref.read(messageApiProvider).searchMessages(authState.token, chatId, query);
      if (generation != _generation) return;
      state = state.copyWith(
        results: result.results,
        // Start on the most recent match - what people are usually after.
        currentIndex: result.results.isEmpty ? 0 : result.results.length - 1,
        truncated: result.truncated,
        loading: false,
      );
    } catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(results: const [], currentIndex: 0, loading: false, error: presentError(e).message);
    }
  }

  /// Moves to the next (newer) match, wrapping around to the oldest.
  void next() {
    if (!state.hasResults) return;
    state = state.copyWith(currentIndex: (state.currentIndex + 1) % state.results.length);
  }

  /// Moves to the previous (older) match, wrapping around to the newest.
  void previous() {
    if (!state.hasResults) return;
    final count = state.results.length;
    state = state.copyWith(currentIndex: (state.currentIndex - 1 + count) % count);
  }

  void select(int index) {
    if (index < 0 || index >= state.results.length) return;
    state = state.copyWith(currentIndex: index);
  }
}

final chatSearchControllerProvider =
    NotifierProvider.autoDispose.family<ChatSearchController, ChatSearchState, String>(
  (chatId) => ChatSearchController(chatId),
);
