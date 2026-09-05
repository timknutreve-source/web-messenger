import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import '../auth/auth_providers.dart';
import '../auth/domain/auth_state.dart';
import 'data/chat_api.dart';
import 'domain/chat_summary.dart';

final chatApiProvider = Provider<ChatApi>((ref) => ChatApi(ref.watch(dioProvider)));

/// Holds the current user's active (non-archived) chats.
class ChatsController extends AsyncNotifier<List<ChatSummary>> {
  @override
  Future<List<ChatSummary>> build() async {
    final token = await _requireToken();
    return ref.read(chatApiProvider).listActiveChats(token);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final token = await _requireToken();
      return ref.read(chatApiProvider).listActiveChats(token);
    });
  }

  /// Archives a chat, removing it from this list on success. The archived
  /// list is invalidated so it picks up the newly archived chat next time
  /// it's read.
  Future<void> archive(String chatId) async {
    final token = await _requireToken();
    await ref.read(chatApiProvider).archiveChat(token, chatId);
    _remove(chatId);
    ref.invalidate(archivedChatsControllerProvider);
  }

  void _remove(String chatId) {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.where((chat) => chat.id != chatId).toList());
    }
  }

  Future<String> _requireToken() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('ChatsController used while not authenticated');
    }
    return authState.token;
  }
}

final chatsControllerProvider = AsyncNotifierProvider<ChatsController, List<ChatSummary>>(ChatsController.new);

/// Holds the current user's archived chats.
class ArchivedChatsController extends AsyncNotifier<List<ChatSummary>> {
  @override
  Future<List<ChatSummary>> build() async {
    final token = await _requireToken();
    return ref.read(chatApiProvider).listArchivedChats(token);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final token = await _requireToken();
      return ref.read(chatApiProvider).listArchivedChats(token);
    });
  }

  /// Unarchives a chat, removing it from this list on success. The active
  /// list is invalidated so it picks up the newly restored chat next time
  /// it's read.
  Future<void> unarchive(String chatId) async {
    final token = await _requireToken();
    await ref.read(chatApiProvider).unarchiveChat(token, chatId);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.where((chat) => chat.id != chatId).toList());
    }
    ref.invalidate(chatsControllerProvider);
  }

  Future<String> _requireToken() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('ArchivedChatsController used while not authenticated');
    }
    return authState.token;
  }
}

final archivedChatsControllerProvider =
    AsyncNotifierProvider<ArchivedChatsController, List<ChatSummary>>(ArchivedChatsController.new);
