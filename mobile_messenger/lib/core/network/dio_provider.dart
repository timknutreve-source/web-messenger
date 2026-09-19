import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_providers.dart';
import 'api_client.dart';

/// The shared [Dio] instance used by every feature's API service layer.
///
/// Any *authenticated* call the server answers with 401 means the session is
/// no longer valid (expired, or signed out from another device) - the user is
/// returned to the login screen with an explanation instead of every screen
/// separately failing with a confusing error. Requests without an
/// Authorization header (login, register, ...) are left alone: a 401 there
/// just means wrong credentials.
final dioProvider = Provider<Dio>((ref) {
  final dio = ApiClient.create();
  dio.interceptors.add(InterceptorsWrapper(
    onError: (error, handler) {
      final hadSession = error.requestOptions.headers.containsKey('Authorization');
      if (error.response?.statusCode == 401 && hadSession) {
        ref.read(authControllerProvider.notifier).handleSessionExpired();
      }
      handler.next(error);
    },
  ));
  return dio;
});
