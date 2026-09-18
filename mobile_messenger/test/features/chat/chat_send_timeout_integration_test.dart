import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/config/app_config.dart';
import 'package:mobile_messenger/core/network/hard_timeout_adapter.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/chat_room_providers.dart';
import 'package:mobile_messenger/features/chat/data/message_api.dart';
import 'package:mobile_messenger/features/chat/domain/message.dart';
import 'package:mobile_messenger/features/chat/domain/message_page.dart';

import '../../support/fakes.dart';

/// A delegate [HttpClientAdapter] whose [fetch] never completes - the exact
/// behavior observed on a real device with Wi-Fi disabled mid-request: the
/// socket never reports success or failure on its own, at *any* layer
/// (connect, send, or reading the response afterward).
class _NeverCompletingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return Completer<ResponseBody>().future;
  }

  @override
  void close({bool force = false}) {}
}

/// The real [MessageApi] end-to-end, except [loadMessages] (used only by
/// `ChatRoomController.build()` to open the chat) resolves instantly with
/// no history - modeling "the chat was already open successfully before
/// connectivity was lost". [sendMessage] is untouched: it goes through
/// whatever real Dio pipeline the test wires up.
class _RealSendMessageApi extends MessageApi {
  _RealSendMessageApi(super.dio);

  @override
  Future<MessagePage> loadMessages(String token, String chatId, {String? before, int? limit}) async {
    return const MessagePage(messages: [], hasMore: false);
  }
}

/// Builds a container wired with a real [MessageApi] on a real [Dio], whose
/// [httpClientAdapter] is the one thing the caller controls - and drives a
/// real `send()` call through the real `ChatRoomController`, returning a
/// getter for the resulting message so the test can assert on its
/// `sendState` over simulated time.
Message Function() sendAndTrack(FakeAsync async, HttpClientAdapter socketAdapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://172.20.10.2:8080',
      connectTimeout: AppConfig.connectTimeout,
      sendTimeout: AppConfig.sendTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
    ),
  );
  dio.httpClientAdapter = socketAdapter;
  final realMessageApi = _RealSendMessageApi(dio);

  final chatApi = FakeChatApi()..activeChatsResult = [];
  final wsClient = FakeChatWebSocketClient();
  final container = ProviderContainer(
    overrides: [
      messageApiProvider.overrideWithValue(realMessageApi),
      chatApiProvider.overrideWithValue(chatApi),
      chatWebSocketClientFactoryProvider.overrideWithValue(() => wsClient),
      authControllerProvider.overrideWith(
        () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
      ),
    ],
  );

  // Keep the autoDispose chatRoomControllerProvider alive for the whole
  // test, matching the running app (the chat screen is open and watching
  // it the whole time the user waits for the send to fail).
  container.listen(chatRoomControllerProvider('chat-1'), (_, _) {});
  async.elapse(Duration.zero);

  container.read(chatRoomControllerProvider('chat-1').notifier).send('Hello');
  async.elapse(Duration.zero);

  return () => container.read(chatRoomControllerProvider('chat-1')).value!.messages.first;
}

/// These tests do NOT use [FakeMessageApi]. They build the *real*
/// [MessageApi]/[ChatRoomController]/`chatRoomControllerProvider` chain,
/// substituting only the innermost socket layer - which is what actually
/// differs between "network reachable" and "network gone". Every layer
/// above that - MessageApi's DioException mapping, ChatRoomController's
/// try/catch and sendState transitions, the provider the UI watches - is
/// exercised exactly as the shipped app runs it.
void main() {
  test(
    'defense layer 1 (HardTimeoutHttpClientAdapter): a message send turns failed within ~10s '
    'when the socket never responds, never stuck in "sending" forever',
    () {
      fakeAsync((async) {
        final sentMessage = sendAndTrack(async, HardTimeoutHttpClientAdapter(_NeverCompletingAdapter()));

        expect(sentMessage().content, 'Hello');
        expect(sentMessage().sendState, SendState.sending);

        async.elapse(const Duration(seconds: 10));

        expect(sentMessage().sendState, SendState.failed,
            reason: 'must be failed within 10s, never left spinning');
        expect(sentMessage().status, isNot(MessageStatus.delivered));
      });
    },
  );

  test(
    'defense layer 2 (ChatRoomController._submit\'s own hard timeout): a message send STILL turns '
    'failed within ~10s even with NO adapter-level protection at all - proves the controller-level '
    'backstop alone is sufficient, independent of anything Dio/adapter-specific',
    () {
      fakeAsync((async) {
        // Deliberately the *raw* never-completing adapter, wrapped by
        // nothing - if HardTimeoutHttpClientAdapter were somehow bypassed,
        // removed, or ineffective on some platform, this proves the
        // message still cannot get stuck forever.
        final sentMessage = sendAndTrack(async, _NeverCompletingAdapter());

        expect(sentMessage().sendState, SendState.sending);

        async.elapse(const Duration(seconds: 10));

        expect(sentMessage().sendState, SendState.failed,
            reason: 'the controller-level timeout must save this even without adapter-level help');
      });
    },
  );
}
