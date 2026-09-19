import 'package:flutter/foundation.dart';

/// Development-time configuration for the app.
///
/// The backend base URL can be overridden at build/run time with:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8080
class AppConfig {
  const AppConfig._();

  static const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// Base URL of the backend API.
  ///
  /// Defaults to `10.0.2.2`, the special alias the Android emulator uses to
  /// reach the host machine's `localhost`. All other platforms (web, iOS
  /// simulator, desktop) can reach the host directly via `localhost`.
  static String get apiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) {
      return _apiBaseUrlOverride;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  /// How long a plain JSON API call may take before it's treated as a
  /// network failure rather than left spinning - deliberately short (a few
  /// seconds) so an offline/unreachable backend fails fast with clear
  /// visual feedback instead of an indefinite spinner backed by a long
  /// platform-default socket timeout. Uploads use [uploadSendTimeout]/
  /// [uploadReceiveTimeout] instead, since a multi-megabyte attachment over
  /// a slow-but-working connection legitimately needs longer.
  static const connectTimeout = Duration(seconds: 5);
  static const sendTimeout = Duration(seconds: 5);
  static const receiveTimeout = Duration(seconds: 5);

  /// Generous timeouts for attachment uploads specifically (images/video/
  /// audio, up to several MB) - a slow-but-valid mobile connection must
  /// still be able to complete these, so they're not held to the same
  /// short bound as a plain JSON request.
  static const uploadSendTimeout = Duration(seconds: 60);
  static const uploadReceiveTimeout = Duration(seconds: 30);

  /// How long a WebSocket handshake may take before giving up. The
  /// `stomp_dart_client` default (`Duration.zero`) applies no timeout at
  /// all, leaving a connection attempt to whatever (potentially very long)
  /// default the underlying platform socket uses.
  static const websocketConnectTimeout = Duration(seconds: 8);

  /// Full URL to fetch a previously uploaded avatar by its server-generated
  /// file name (see [User.avatarFileName]). The endpoint requires auth, so
  /// callers must send the current session token as a header when loading it.
  static String avatarUrl(String avatarFileName) => '$apiBaseUrl/api/profile/avatar/$avatarFileName';

  /// Resolves a backend-relative path (e.g. one returned by the API, such as
  /// a chat attachment's `url`/`thumbnailUrl`) into a full URL.
  static String resolve(String path) => '$apiBaseUrl$path';

  /// WebSocket URL for the STOMP endpoint, derived from [apiBaseUrl] by
  /// swapping the `http`/`https` scheme for `ws`/`wss`.
  static String get websocketUrl => '${apiBaseUrl.replaceFirst('http', 'ws')}/ws';

  /// [websocketUrl] with the session token as a query parameter - only for
  /// the web, where a browser WebSocket cannot send an Authorization header.
  static String websocketUrlWithToken(String token) =>
      '$websocketUrl?access_token=${Uri.encodeQueryComponent(token)}';
}
