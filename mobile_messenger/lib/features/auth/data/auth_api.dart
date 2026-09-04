import 'package:dio/dio.dart';

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
      throw mapApiDioException(e);
    }
  }

  Future<String> verifyEmail(String token) {
    return _messageRequest('/api/auth/verify-email', {'token': token});
  }

  Future<String> resendVerification(String authToken) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/auth/resend-verification',
        options: Options(headers: {'Authorization': 'Bearer $authToken'}),
      );
      return (response.data as Map<String, dynamic>)['message'] as String;
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<String> forgotPassword(String email) {
    return _messageRequest('/api/auth/forgot-password', {'email': email});
  }

  Future<String> resetPassword({required String token, required String newPassword}) {
    return _messageRequest('/api/auth/reset-password', {
      'token': token,
      'newPassword': newPassword,
    });
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
      throw mapApiDioException(e);
    }
  }

  Future<String> _messageRequest(String path, Map<String, dynamic> body) async {
    try {
      final response = await _dio.post<dynamic>(path, data: body);
      return (response.data as Map<String, dynamic>)['message'] as String;
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }
}
