import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../../core/network/dio_exception_mapper.dart';
import '../../../core/network/multipart_helper.dart';
import '../../auth/domain/user.dart';

/// API service layer for `/api/profile*`.
class ProfileApi {
  ProfileApi(this._dio);

  final Dio _dio;

  Future<User> getProfile(String token) async {
    try {
      final response = await _dio.get<dynamic>('/api/profile', options: _authHeader(token));
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<User> updateProfile(
    String token, {
    required String username,
    required String email,
    required String aboutMe,
  }) async {
    try {
      final response = await _dio.put<dynamic>(
        '/api/profile',
        data: {'username': username, 'email': email, 'aboutMe': aboutMe},
        options: _authHeader(token),
      );
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<User> uploadAvatar(String token, XFile imageFile) async {
    try {
      final formData = FormData.fromMap({
        'file': await multipartFromXFile(imageFile),
      });
      final response = await _dio.post<dynamic>(
        '/api/profile/avatar',
        data: formData,
        options: _authHeader(token),
      );
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Options _authHeader(String token) => Options(headers: {'Authorization': 'Bearer $token'});
}
