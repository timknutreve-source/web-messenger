import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../../core/config/app_config.dart';
import '../../../core/network/dio_exception_mapper.dart';
import '../../../core/network/multipart_helper.dart';
import '../domain/attachment.dart';

/// API service layer for `/api/chats/{chatId}/attachments` (upload only -
/// downloading the actual media is done directly by [Image.network]/the
/// video player via [Attachment.url]/[Attachment.thumbnailUrl] plus an
/// Authorization header, not through this class).
class AttachmentApi {
  AttachmentApi(this._dio);

  final Dio _dio;

  Future<Attachment> upload(String token, String chatId, XFile file, {int? durationSeconds}) async {
    try {
      final formData = FormData.fromMap({
        'file': await multipartFromXFile(file),
        if (durationSeconds != null) 'durationSeconds': durationSeconds.toString(),
      });
      final response = await _dio.post<dynamic>(
        '/api/chats/$chatId/attachments',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: AppConfig.uploadSendTimeout,
          receiveTimeout: AppConfig.uploadReceiveTimeout,
        ),
      );
      return Attachment.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }
}
