import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import '../auth/auth_providers.dart';
import '../auth/domain/auth_state.dart';
import '../contact/domain/contact_user_summary.dart';
import 'data/chat_websocket_client.dart';
import 'data/message_api.dart';
import 'domain/chat_event.dart';
import 'domain/message.dart';

final messageApiProvider = Provider<MessageApi>((ref) => MessageApi(ref.watch(dioProvider)));

/// A factory rather than a shared instance, since each chat room needs its
/// own [ChatWebSocketClient]. Overridable in tests to inject a fake.
final chatWebSocketClientFactoryProvider =
    Provider<ChatWebSocketClient Function()>((ref) => ChatWebSocketClient.new);

/// State for a single conversation screen: its messages (oldest-first,
/// including any not-yet-confirmed outgoing ones), whether an older page is
/// available, and who (if anyone) is currently typing.
class ChatRoomState {
  const ChatRoomState({
    required this.messages,
    required this.hasMoreOlder,
    this.typingUsername,
    this.loadingOlder = false,
  });

  final List<Message> messages;
  final bool hasMoreOlder;
  final String? typingUsername;
  final bool loadingOlder;

  ChatRoomState copyWith({
    List<Message>? messages,
    bool? hasMoreOlder,
    String? typingUsername,
    bool clearTyping = false,
    bool? loadingOlder,
  }) =>
      ChatRoomState(
        messages: messages ?? this.messages,
        hasMoreOlder: hasMoreOlder ?? this.hasMoreOlder,
        typingUsername: clearTyping ? null : (typingUsername ?? this.typingUsername),
        loadingOlder: loadingOlder ?? this.loadingOlder,
      );
}

/// Owns one conversation's message history plus its live WebSocket
/// subscription (new/updated/deleted messages, status changes, typing).
/// Scoped per chat id and auto-disposed when nothing is watching it anymore
/// (i.e. leaving the chat screen), which is what tears down the socket.
class ChatRoomController extends AsyncNotifier<ChatRoomState> {
  ChatRoomController(this.chatId);

  final String chatId;

  // Not `late final`: AsyncNotifier.build() can legitimately run more than
  // once over this controller's lifetime (e.g. Riverpod's automatic retry
  // after a failed build), which would otherwise throw
  // LateInitializationError on the second attempt.
  late ChatWebSocketClient _webSocket;
  Timer? _typingClearTimer;
  Timer? _typingStopTimer;
  bool _sentTypingStarted = false;
  int _localIdCounter = 0;

  @override
  Future<ChatRoomState> build() async {
    _webSocket = ref.read(chatWebSocketClientFactoryProvider)();
    final token = await _requireToken();
    ref.onDispose(_disconnect);

    final page = await ref.read(messageApiProvider).loadMessages(token, chatId);
    _connect(token);
    unawaited(_markRead());
    return ChatRoomState(messages: page.messages, hasMoreOlder: page.hasMore);
  }

  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null || !current.hasMoreOlder || current.loadingOlder || current.messages.isEmpty) {
      return;
    }
    state = AsyncData(current.copyWith(loadingOlder: true));
    try {
      final token = await _requireToken();
      final oldestId = current.messages.first.id;
      final page = await ref.read(messageApiProvider).loadMessages(token, chatId, before: oldestId);
      final merged = state.value;
      if (merged == null) return;
      state = AsyncData(merged.copyWith(
        messages: [...page.messages, ...merged.messages],
        hasMoreOlder: page.hasMore,
        loadingOlder: false,
      ));
    } catch (_) {
      final current2 = state.value;
      if (current2 != null) {
        state = AsyncData(current2.copyWith(loadingOlder: false));
      }
    }
  }

  Future<void> send(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final token = await _requireToken();
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) return;

    final localId = 'local-${_localIdCounter++}';
    final pending = Message(
      id: localId,
      conversationId: chatId,
      sender: ContactUserSummary(
        id: authState.user.id,
        username: authState.user.username,
        email: authState.user.email,
        avatarFileName: authState.user.avatarFileName,
      ),
      content: trimmed,
      status: MessageStatus.sent,
      createdAt: DateTime.now().toUtc(),
      deleted: false,
      sendState: SendState.sending,
    );
    _appendOrReplace(pending, matchLocalId: null);
    stopTyping();

    try {
      final sent = await ref.read(messageApiProvider).sendMessage(token, chatId, trimmed);
      _appendOrReplace(sent, matchLocalId: localId);
    } catch (_) {
      _updateMessage(localId, (m) => m.copyWith(sendState: SendState.failed));
    }
  }

  Future<void> retry(String localId) async {
    final current = state.value;
    if (current == null) return;
    Message? failed;
    for (final m in current.messages) {
      if (m.id == localId) {
        failed = m;
        break;
      }
    }
    if (failed == null || failed.content == null) return;

    _updateMessage(localId, (m) => m.copyWith(sendState: SendState.sending));
    try {
      final token = await _requireToken();
      final sent = await ref.read(messageApiProvider).sendMessage(token, chatId, failed.content!);
      _appendOrReplace(sent, matchLocalId: localId);
    } catch (_) {
      _updateMessage(localId, (m) => m.copyWith(sendState: SendState.failed));
    }
  }

  Future<void> edit(String messageId, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final token = await _requireToken();
    final updated = await ref.read(messageApiProvider).editMessage(token, chatId, messageId, trimmed);
    _replaceById(updated);
  }

  Future<void> delete(String messageId) async {
    final token = await _requireToken();
    await ref.read(messageApiProvider).deleteMessage(token, chatId, messageId);
    _updateMessage(messageId, (m) => m.copyWith(deleted: true));
  }

  /// Called on every keystroke in the composer; debounces so a
  /// TYPING_STARTED event is sent at most once per burst of typing, and a
  /// TYPING_STOPPED event follows automatically after a short idle period.
  void onComposerChanged(String text) {
    _typingStopTimer?.cancel();
    if (text.isEmpty) {
      stopTyping();
      return;
    }
    if (!_sentTypingStarted) {
      _sentTypingStarted = true;
      _webSocket.sendTyping(chatId, true);
    }
    _typingStopTimer = Timer(const Duration(seconds: 3), stopTyping);
  }

  void stopTyping() {
    _typingStopTimer?.cancel();
    if (_sentTypingStarted) {
      _sentTypingStarted = false;
      _webSocket.sendTyping(chatId, false);
    }
  }

  void _connect(String token) {
    _webSocket.connect(
      token: token,
      onConnected: () => _webSocket.subscribeToChat(chatId, _handleEvent),
    );
  }

  void _handleEvent(ChatEvent event) {
    switch (event.type) {
      case 'NEW_MESSAGE':
        _appendOrReplace(Message.fromJson(event.payload), matchLocalId: null);
        unawaited(_markRead());
      case 'MESSAGE_UPDATED':
      case 'MESSAGE_STATUS_UPDATED':
        _replaceById(Message.fromJson(event.payload));
      case 'MESSAGE_DELETED':
        final id = event.payload['messageId'] as String?;
        if (id != null) {
          _updateMessage(id, (m) => m.copyWith(deleted: true));
        }
      case 'MESSAGES_READ':
        final ids = (event.payload['messageIds'] as List?)?.cast<String>() ?? const [];
        for (final id in ids) {
          _updateMessage(id, (m) => m.copyWith(status: MessageStatus.read));
        }
      case 'TYPING_STARTED':
        _typingClearTimer?.cancel();
        final username = event.payload['username'] as String?;
        final current = state.value;
        if (current != null) {
          state = AsyncData(current.copyWith(typingUsername: username));
        }
        _typingClearTimer = Timer(const Duration(seconds: 5), _clearTyping);
      case 'TYPING_STOPPED':
        _clearTyping();
    }
  }

  void _clearTyping() {
    _typingClearTimer?.cancel();
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(clearTyping: true));
    }
  }

  Future<void> _markRead() async {
    try {
      final token = await _requireToken();
      await ref.read(messageApiProvider).markRead(token, chatId);
    } catch (_) {
      // Best-effort - a reconnect/reload will resync state from the server.
    }
  }

  void _appendOrReplace(Message message, {required String? matchLocalId}) {
    final current = state.value;
    if (current == null) return;
    if (matchLocalId != null) {
      state = AsyncData(current.copyWith(
        messages: [
          for (final m in current.messages)
            if (m.id == matchLocalId) message else m,
        ],
      ));
      return;
    }
    if (current.messages.any((m) => m.id == message.id)) return;
    state = AsyncData(current.copyWith(messages: [...current.messages, message]));
  }

  void _replaceById(Message message) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      messages: [
        for (final m in current.messages)
          if (m.id == message.id) message else m,
      ],
    ));
  }

  void _updateMessage(String id, Message Function(Message) update) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      messages: [
        for (final m in current.messages)
          if (m.id == id) update(m) else m,
      ],
    ));
  }

  Future<String> _requireToken() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('ChatRoomController used while not authenticated');
    }
    return authState.token;
  }

  void _disconnect() {
    _typingClearTimer?.cancel();
    _typingStopTimer?.cancel();
    stopTyping();
    _webSocket.disconnect();
  }
}

final chatRoomControllerProvider =
    AsyncNotifierProvider.autoDispose.family<ChatRoomController, ChatRoomState, String>(
  (chatId) => ChatRoomController(chatId),
);
