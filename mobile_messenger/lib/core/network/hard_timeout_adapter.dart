import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Wraps another [HttpClientAdapter] with an absolute, unconditional
/// deadline on every request.
///
/// Dio's own `connectTimeout`/`sendTimeout`/`receiveTimeout` are supposed to
/// bound each phase of a request, but they rely on the underlying platform
/// (here, `dart:io`'s `HttpClient`/raw sockets) actually reporting failure
/// promptly. On some real Android devices/network states - observed
/// concretely: disabling Wi-Fi entirely while a request is in flight - the
/// OS-level socket can sit in limbo indefinitely (waiting for a network
/// that Android itself may briefly keep advertising as "about to come
/// back", or a route that never resolves as unreachable), and Dio's
/// per-phase timeouts never get the chance to fire because the phase they'd
/// bound never definitively starts or ends.
///
/// This adapter doesn't trust that layer at all: it races the delegate's
/// [fetch] against a plain [Timer], independent of sockets, DNS, or
/// anything platform-specific. Past [timeout], it unconditionally raises a
/// [DioException] of type [DioExceptionType.connectionTimeout] - which
/// every API service in this app already maps to a friendly, generic
/// "unable to connect" message - so a request can never be stuck showing a
/// spinner forever, no matter what the platform does underneath.
class HardTimeoutHttpClientAdapter implements HttpClientAdapter {
  HardTimeoutHttpClientAdapter(this._delegate, {this.buffer = const Duration(seconds: 2)});

  final HttpClientAdapter _delegate;

  /// Slack added on top of the request's own configured timeouts, so this
  /// backstop only ever fires *after* the normal, better-mapped Dio-level
  /// timeout would have - it only matters when that one didn't.
  final Duration buffer;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    // Derived per-request from whatever connect/send/receive timeouts that
    // request actually configured (a plain JSON call vs. a multi-minute
    // attachment upload need very different backstops). Uses the largest
    // single configured phase, not the sum of all three: a real request
    // only ever gets stuck in *one* phase at a time (e.g. offline means
    // connect never completes - send and receive never even begin), so
    // summing every phase as if all three could hang in sequence only
    // inflates the worst case for no reason - for a plain JSON call with
    // 5s connect/send/receive, that's the difference between a ~7s and a
    // ~20s wait before the user sees anything.
    final configured = [options.connectTimeout, options.sendTimeout, options.receiveTimeout]
        .whereType<Duration>()
        .fold(Duration.zero, (max, d) => d > max ? d : max);
    final deadline = configured + buffer;

    return _delegate.fetch(options, requestStream, cancelFuture).timeout(
      deadline,
      onTimeout: () => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        error: TimeoutException('Request exceeded the hard timeout of $deadline', deadline),
      ),
    );
  }

  @override
  void close({bool force = false}) => _delegate.close(force: force);
}
