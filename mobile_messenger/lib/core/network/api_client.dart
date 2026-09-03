import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Builds the shared [Dio] instance used for all backend API calls.
class ApiClient {
  const ApiClient._();

  static Dio create() {
    return Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
      ),
    );
  }
}
