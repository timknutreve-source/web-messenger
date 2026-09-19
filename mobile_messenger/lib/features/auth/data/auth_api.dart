import 'package:dio/dio.dart';

import '../../../core/network/dio_exception_mapper.dart';
import '../../../core/platform/device_label.dart';
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
      'deviceName': deviceLabel(),
    });
  }

  Future<AuthResult> login({
    required String usernameOrEmail,
    required String password,
  }) {
    return _authRequest('/api/auth/login', {
      'usernameOrEmail': usernameOrEmail,
      'password': password,
      'deviceName': deviceLabel(),
    });
  }

  /// Ends only *this* device's session on the server - the same account's
  /// sessions on other devices (say the phone while this is the web app)
  /// are unaffected.
  Future<void> logout(String token) async {
    try {
      await _dio.post<dynamic>(
        '/api/auth/logout',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
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

  /// Verifies the 6-digit code emailed to the currently signed-in user.
  /// Authenticated (unlike the old link-based flow) because the code alone
  /// isn't unique enough across accounts to identify whose it is - the
  /// caller's own auth token supplies that.
  Future<String> verifyEmail({required String authToken, required String code}) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/auth/verify-email',
        data: {'code': code},
        options: Options(headers: {'Authorization': 'Bearer $authToken'}),
      );
      return (response.data as Map<String, dynamic>)['message'] as String;
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
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

  /// Resets the password for the account identified by [email], if [code]
  /// matches its currently pending password-reset code.
  Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _messageRequest('/api/auth/reset-password', {
      'email': email,
      'code': code,
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
