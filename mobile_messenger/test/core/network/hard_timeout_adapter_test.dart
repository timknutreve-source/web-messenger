import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/hard_timeout_adapter.dart';

/// A delegate adapter whose [fetch] never completes on its own - stands in
/// for a real socket stuck in limbo (e.g. Wi-Fi disabled mid-request),
/// which is exactly the real-device failure this adapter guards against.
class _NeverCompletingAdapter implements HttpClientAdapter {
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return Completer<ResponseBody>().future;
  }

  @override
  void close({bool force = false}) => closed = true;
}

class _ImmediateAdapter implements HttpClientAdapter {
  ResponseBody? result;
  Object? error;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (error != null) throw error!;
    return result!;
  }

  @override
  void close({bool force = false}) {}
}

RequestOptions _options({Duration? connect, Duration? send, Duration? receive}) => RequestOptions(
      path: '/test',
      connectTimeout: connect,
      sendTimeout: send,
      receiveTimeout: receive,
    );

void main() {
  test('never leaves a request unresolved: raises after the largest configured phase timeout '
      '+ buffer, even if the delegate never completes on its own', () {
    fakeAsync((async) {
      final adapter = HardTimeoutHttpClientAdapter(_NeverCompletingAdapter());
      final options = _options(
        connect: const Duration(seconds: 5),
        send: const Duration(seconds: 5),
        receive: const Duration(seconds: 5),
      );

      Object? capturedError;
      adapter.fetch(options, null, null).then((_) {}, onError: (Object e) {
        capturedError = e;
      });

      // Just under the deadline (max(5,5,5) + 2s buffer = 7s): still unresolved.
      async.elapse(const Duration(seconds: 6));
      expect(capturedError, isNull, reason: 'a plain text message send must not resolve before ~7s');

      async.elapse(const Duration(seconds: 2));
      expect(capturedError, isA<DioException>());
      expect((capturedError as DioException).type, DioExceptionType.connectionTimeout);
    });
  });

  test('a plain JSON request (5s connect/send/receive, matching the real text-message send '
      'path) is guaranteed to resolve well within 10s - not the ~20s a naive sum would give', () {
    fakeAsync((async) {
      final adapter = HardTimeoutHttpClientAdapter(_NeverCompletingAdapter());
      // Mirrors AppConfig.connectTimeout/sendTimeout/receiveTimeout exactly.
      final options = _options(
        connect: const Duration(seconds: 5),
        send: const Duration(seconds: 5),
        receive: const Duration(seconds: 5),
      );

      Object? capturedError;
      adapter.fetch(options, null, null).then((_) {}, onError: (Object e) {
        capturedError = e;
      });

      async.elapse(const Duration(seconds: 10));
      expect(capturedError, isNotNull, reason: 'must have failed by 10s, not still be pending');
    });
  });

  test('scales the backstop to whatever the single slowest configured phase is '
      '(a long attachment upload is not killed early)', () {
    fakeAsync((async) {
      final adapter = HardTimeoutHttpClientAdapter(_NeverCompletingAdapter());
      final options = _options(
        connect: const Duration(seconds: 5),
        send: const Duration(seconds: 60),
        receive: const Duration(seconds: 30),
      );

      Object? capturedError;
      adapter.fetch(options, null, null).then((_) {}, onError: (Object e) {
        capturedError = e;
      });

      // max(5, 60, 30) = 60s of configured timeouts - must not fire before that.
      async.elapse(const Duration(seconds: 59));
      expect(capturedError, isNull);

      // +2s buffer = 62s total.
      async.elapse(const Duration(seconds: 3));
      expect(capturedError, isA<DioException>());
    });
  });

  test('a delegate that resolves normally within the deadline is unaffected', () async {
    final delegate = _ImmediateAdapter()..result = ResponseBody(const Stream.empty(), 200);
    final adapter = HardTimeoutHttpClientAdapter(delegate);

    final result = await adapter.fetch(_options(connect: const Duration(seconds: 5)), null, null);

    expect(result.statusCode, 200);
  });

  test('a delegate error (e.g. an immediate DioException) still propagates as-is', () async {
    final delegate = _ImmediateAdapter()..error = const SocketExceptionStub();
    final adapter = HardTimeoutHttpClientAdapter(delegate);

    await expectLater(
      adapter.fetch(_options(connect: const Duration(seconds: 5)), null, null),
      throwsA(isA<SocketExceptionStub>()),
    );
  });

  test('close() delegates to the wrapped adapter', () {
    final delegate = _NeverCompletingAdapter();
    HardTimeoutHttpClientAdapter(delegate).close();
    expect(delegate.closed, isTrue);
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
