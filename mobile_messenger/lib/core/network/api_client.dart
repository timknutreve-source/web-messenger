import 'dart:io' show HttpClient;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../config/app_config.dart';
import 'hard_timeout_adapter.dart';

/// Builds the shared [Dio] instance used for all backend API calls.
class ApiClient {
  const ApiClient._();

  static Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: AppConfig.sendTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
      ),
    );

    // On the web there is no dart:io: [Dio]'s own default adapter
    // (`BrowserHttpClientAdapter`, i.e. the browser's XMLHttpRequest) is the
    // only option, and the browser - not this app - owns connection pooling.
    // The hard-timeout backstop below still applies to it.
    final HttpClientAdapter platformAdapter;
    if (kIsWeb) {
      platformAdapter = dio.httpClientAdapter;
    } else {
      // The underlying dart:io HttpClient otherwise keeps a request's TCP
      // connection alive and pools it for reuse (default idleTimeout: 15s).
      // If connectivity drops mid-request, that connection is left half-open
      // in the pool rather than immediately recognized as dead - a retry
      // issued shortly after connectivity returns can be handed that same
      // stale connection instead of opening a fresh one, so it fails again
      // (or hangs for another full timeout) even though the network is back.
      // A short idleTimeout forces the pool to discard it quickly, so retry
      // always gets a genuinely fresh connection.
      platformAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpClient()..idleTimeout = const Duration(seconds: 1),
      );
    }

    // A last-resort, platform-independent backstop: on some real devices,
    // disabling connectivity mid-request has been observed to leave the
    // underlying socket in limbo indefinitely, past the point where Dio's
    // own connect/send/receive timeouts should have fired - see
    // HardTimeoutHttpClientAdapter's doc comment. This guarantees every
    // request eventually resolves, one way or another.
    dio.httpClientAdapter = HardTimeoutHttpClientAdapter(platformAdapter);
    return dio;
  }
}
