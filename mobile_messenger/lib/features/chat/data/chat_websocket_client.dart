import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../../../core/config/app_config.dart';
import '../domain/chat_event.dart';

/// Thin wrapper around [StompClient] for the app's one WebSocket concern:
/// per-conversation events. Connects using the same JWT bearer token as
/// every REST call, sent as an HTTP header on the WebSocket handshake (see
/// the backend's `AuthHandshakeInterceptor`) - no second login system, no
/// token inside a STOMP frame.
class ChatWebSocketClient {
  StompClient? _client;

  bool get isConnected => _client?.connected ?? false;

  void connect({
    required String token,
    void Function()? onConnected,
    void Function(Object error)? onError,
  }) {
    _client = StompClient(
      config: StompConfig(
        url: AppConfig.websocketUrl,
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        onConnect: (_) => onConnected?.call(),
        onWebSocketError: (error) => onError?.call(error),
        onStompError: (frame) => onError?.call(frame.body ?? 'STOMP error'),
      ),
    )..activate();
  }

  StompUnsubscribe subscribeToChat(String chatId, void Function(ChatEvent event) onEvent) {
    final client = _client;
    if (client == null) {
      throw StateError('ChatWebSocketClient.connect() must be called first');
    }
    return client.subscribe(
      destination: '/topic/chats/$chatId',
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) return;
        onEvent(ChatEvent.fromJson(jsonDecode(body) as Map<String, dynamic>));
      },
    );
  }

  void sendTyping(String chatId, bool started) {
    _client?.send(
      destination: '/app/chats/$chatId/typing',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'started': started}),
    );
  }

  void disconnect() {
    _client?.deactivate();
    _client = null;
  }
}
