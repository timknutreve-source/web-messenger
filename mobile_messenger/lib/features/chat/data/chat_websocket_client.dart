import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../../../core/config/app_config.dart';
import '../domain/chat_event.dart';

/// Thin wrapper around [StompClient] for the app's WebSocket concerns: per-
/// conversation events and, since a user's own connection also carries their
/// personal invitation feed, arbitrary topic subscriptions in general.
/// Connects using the same JWT bearer token as every REST call, sent as an
/// HTTP header on the WebSocket handshake (see the backend's
/// `AuthHandshakeInterceptor`) - no second login system, no token inside a
/// STOMP frame.
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
        // A browser's WebSocket API cannot set request headers on the
        // handshake (unlike a native Dart/Android socket), so on the web the
        // same JWT travels as a query parameter instead - the backend's
        // JwtAuthenticationFilter accepts it for the /ws handshake only.
        url: kIsWeb ? AppConfig.websocketUrlWithToken(token) : AppConfig.websocketUrl,
        webSocketConnectHeaders: kIsWeb ? null : {'Authorization': 'Bearer $token'},
        // The package default (Duration.zero) applies no timeout at all to
        // the handshake, leaving a connection attempt on an unreachable
        // network to whatever (potentially very long) default the
        // underlying platform socket falls back to.
        connectionTimeout: AppConfig.websocketConnectTimeout,
        onConnect: (_) => onConnected?.call(),
        onWebSocketError: (error) => onError?.call(error),
        onStompError: (frame) => onError?.call(frame.body ?? 'STOMP error'),
      ),
    )..activate();
  }

  StompUnsubscribe subscribeToChat(String chatId, void Function(ChatEvent event) onEvent) {
    return subscribe('/topic/chats/$chatId', onEvent);
  }

  /// Subscribes to an arbitrary destination (e.g. a user's personal
  /// `/topic/users/{userId}/invitations` feed) - authorization for whether
  /// this connection's user is actually allowed to see it is enforced
  /// server-side (see `ChatSubscriptionInterceptor`), same as
  /// [subscribeToChat].
  StompUnsubscribe subscribe(String destination, void Function(ChatEvent event) onEvent) {
    final client = _client;
    if (client == null) {
      throw StateError('ChatWebSocketClient.connect() must be called first');
    }
    return client.subscribe(
      destination: destination,
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
