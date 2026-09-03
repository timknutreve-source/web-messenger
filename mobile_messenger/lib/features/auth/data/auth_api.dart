import 'package:dio/dio.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/dio_exception_mapper.dart';
import '../domain/user.dart';

class AuthResult {
  const AuthResult({required this.token, required this.user});

  final String token;
  final User user;
}

/// API service layer for `/api/auth/*`.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
  }) {
    return _authRequest('/api/auth/register', {
      'username': username,
      'email': email,
      'password': password,
    });
  }

  Future<AuthResult> login({
    required String usernameOrEmail,
    required String password,
  }) {
    return _authRequest('/api/auth/login', {
      'usernameOrEmail': usernameOrEmail,
      'password': password,
    });
  }

  Future<User> fetchCurrentUser(String token) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapAuthDioException(e);
    }
  }

  Future<AuthResult> _authRequest(String path, Map<String, dynamic> body) async {
    try {
      final response = await _dio.post<dynamic>(path, data: body);
      final data = response.data as Map<String, dynamic>;
      return AuthResult(
        token: data['token'] as String,
        user: User.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _mapAuthDioException(e);
    }
  }

  AppException _mapAuthDioException(DioException e) {
    if (e.type != DioExceptionType.badResponse) {
      return mapConnectionDioException(e);
    }

    final statusCode = e.response?.statusCode ?? -1;
    final data = e.response?.data;
    final error = (data is Map && data['error'] is String)
        ? data['error'] as String
        : null;

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
      case >= 500:
        return const ServerErrorException();
      default:
        return UnexpectedStatusException(statusCode);
    }
  }
}
