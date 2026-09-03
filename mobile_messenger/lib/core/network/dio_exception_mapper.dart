import 'package:dio/dio.dart';

import 'app_exception.dart';

/// Maps the connection-level (non-HTTP-response) [DioException] cases shared
/// by every API service: timeouts, connection failures, cancellation.
///
/// Callers should handle [DioExceptionType.badResponse] themselves first,
/// since the right [AppException] for an HTTP error status is endpoint-specific.
AppException mapConnectionDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const RequestTimeoutException();
    case DioExceptionType.badResponse:
    case DioExceptionType.connectionError:
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return const NetworkUnavailableException();
  }
}
