import 'package:dio/dio.dart';

import '../../../core/network/app_exception.dart';

/// API service layer for the backend's `/api/health` endpoint.
class HealthApi {
  HealthApi(this._dio);

  final Dio _dio;

  /// Calls `GET /api/health` and throws an [AppException] describing what
  /// went wrong if the backend is unreachable or responds unexpectedly.
  Future<void> checkHealth() async {
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>('/api/health');
    } on DioException catch (e) {
      throw _mapDioException(e);
    }

    if (response.statusCode != 200) {
      throw UnexpectedStatusException(response.statusCode ?? -1);
    }

    final data = response.data;
    if (data is! Map || data['status'] != 'ok') {
      throw const InvalidResponseException();
    }
  }

  AppException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const RequestTimeoutException();
      case DioExceptionType.badResponse:
        return UnexpectedStatusException(e.response?.statusCode ?? -1);
      case DioExceptionType.connectionError:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return const NetworkUnavailableException();
    }
  }
}
