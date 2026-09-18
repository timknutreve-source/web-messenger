import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import '../../core/network/no_auto_retry.dart';
import '../auth/auth_providers.dart';
import '../auth/domain/auth_state.dart';
import 'chat_room_providers.dart' show chatWebSocketClientFactoryProvider, messageApiProvider;
import 'data/chat_api.dart';
import 'data/chat_websocket_client.dart';
import 'domain/chat_event.dart';
import 'domain/chat_summary.dart';

final chatApiProvider = Provider<ChatApi>((ref) => ChatApi(ref.watch(dioProvider)));

/// Holds the current user's active (non-archived) chats.
///
/// Besides the initial REST fetch, this subscribes to every one of those
/// chats' WebSocket topics purely to keep each chat's [ChatSummary.unreadCount]
/// live (for the chat-list unread badge) while the user is elsewhere in the
/// app - e.g. on this very list, not inside a specific conversation. This
/// deliberately never touches or duplicates any `Message`, only a per-chat
/// integer count, so it cannot reintroduce the message-duplication bug
/// `ChatRoomController._appendOrReplace` guards against - the two operate on
/// entirely separate state.
class ChatsController extends AsyncNotifier<List<ChatSummary>> {
  ChatWebSocketClient? _webSocket;
  String? _myUserId;
  String? _myToken;

  @override
  Future<List<ChatSummary>> build() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('ChatsController used while not authenticated');
    }
    _myUserId = authState.user.id;
    _myToken = authState.token;
    final chats = await ref.read(chatApiProvider).listActiveChats(authState.token);
    _connect(authState.token, chats);
    ref.onDispose(_disconnect);
    return chats;
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

  /// Zeroes a chat's unread count locally, in lockstep with the real
  /// mark-read REST call (see `ChatRoomController._markRead`) - waiting for
  /// a full list refetch instead would leave the badge showing a stale
  /// count for a chat the user is actively looking at right now.
  void markChatRead(String chatId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final chat in current)
        if (chat.id == chatId) chat.copyWith(unreadCount: 0) else chat,
    ]);
  }

  void _connect(String token, List<ChatSummary> chats) {
    final webSocket = ref.read(chatWebSocketClientFactoryProvider)();
    _webSocket = webSocket;
    webSocket.connect(
      token: token,
      onConnected: () {
        for (final chat in chats) {
          webSocket.subscribeToChat(chat.id, (event) => _handleEvent(chat.id, event));
        }
      },
    );
  }

  void _handleEvent(String chatId, ChatEvent event) {
    if (event.type != 'NEW_MESSAGE') return;
    final sender = event.payload['sender'] as Map<String, dynamic>?;
    if (sender == null) return;
    final isMine = sender['id'] == _myUserId;

    // Acknowledges delivery the moment this message reaches this device over
    // the live connection - regardless of whether its chat is the one
    // currently open (see `ChatRoomController._acknowledgeDelivery` for the
    // complementary "was offline, only seen once the chat is opened later"
    // case). Never gated on the sender actually seeing it, unlike read. Only
    // applies to messages from someone else - never "deliver" your own.
    if (!isMine) {
      final messageId = event.payload['id'] as String?;
      final token = _myToken;
      if (messageId != null && token != null) {
        unawaited(_acknowledgeDelivery(token, chatId, messageId));
      }
    }

    final current = state.value;
    if (current == null) return;
    final createdAtRaw = event.payload['createdAt'] as String?;
    final createdAt = createdAtRaw != null ? DateTime.parse(createdAtRaw) : null;

    // Every new message - including one this user just sent themselves -
    // bumps the conversation to the top of the list, timeline-style. Only
    // the unread badge is specific to messages from someone else.
    final updated = [
      for (final chat in current)
        if (chat.id == chatId)
          chat.copyWith(
            unreadCount: isMine ? chat.unreadCount : chat.unreadCount + 1,
            lastActivityAt: createdAt,
          )
        else
          chat,
    ]..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    state = AsyncData(updated);
  }

  Future<void> _acknowledgeDelivery(String token, String chatId, String messageId) async {
    try {
      await ref.read(messageApiProvider).markDelivered(token, chatId, messageId);
    } catch (_) {
      // Best-effort - a later reconnect/resync will catch up regardless.
    }
  }

  void _disconnect() {
    _webSocket?.disconnect();
    _webSocket = null;
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

final chatsControllerProvider = AsyncNotifierProvider<ChatsController, List<ChatSummary>>(
  ChatsController.new,
  retry: noAutoRetry,
);

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

final archivedChatsControllerProvider = AsyncNotifierProvider<ArchivedChatsController, List<ChatSummary>>(
  ArchivedChatsController.new,
  retry: noAutoRetry,
);
