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

  static const connectTimeout = Duration(seconds: 5);
  static const receiveTimeout = Duration(seconds: 5);

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
}
