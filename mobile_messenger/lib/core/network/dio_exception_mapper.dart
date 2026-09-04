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

/// Maps any [DioException] from a JSON API call that follows this backend's
/// standard error shape (`{"error": "...", "fieldErrors": {...}}`) into the
/// matching [AppException]. Shared by every feature's API service so each
/// one doesn't have to re-implement the same status-code switch.
AppException mapApiDioException(DioException e) {
  if (e.type != DioExceptionType.badResponse) {
    return mapConnectionDioException(e);
  }

  final statusCode = e.response?.statusCode ?? -1;
  final data = e.response?.data;
  final error = (data is Map && data['error'] is String) ? data['error'] as String : null;

  switch (statusCode) {
    case 400:
      final rawFieldErrors = (data is Map ? data['fieldErrors'] : null);
      final fieldErrors = rawFieldErrors is Map
          ? rawFieldErrors.map((key, value) => MapEntry(key.toString(), value.toString()))
          : <String, String>{};
      return ValidationException(error ?? 'Validation failed.', fieldErrors);
    case 401:
      return InvalidCredentialsException(error);
    case 409:
      return DuplicateResourceException(error);
    case 413:
      return FileTooLargeException(error);
    case >= 500:
      return const ServerErrorException();
    default:
      return UnexpectedStatusException(statusCode);
  }
}
