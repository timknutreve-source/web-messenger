import 'package:dio/dio.dart';

import '../../../core/network/dio_exception_mapper.dart';
import '../domain/message.dart';
import '../domain/message_page.dart';
import '../domain/message_search_result.dart';

/// API service layer for `/api/chats/{chatId}/messages*`.
class MessageApi {
  MessageApi(this._dio);

  final Dio _dio;

  Future<MessagePage> loadMessages(String token, String chatId, {String? before, int? limit}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/chats/$chatId/messages',
        queryParameters: {
          'before': ?before,
          'limit': ?limit,
        },
        options: _authHeader(token),
      );
      return MessagePage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  /// Messages of one chat containing [query] (case-insensitive), oldest first.
  Future<MessageSearchResult> searchMessages(String token, String chatId, String query) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/chats/$chatId/messages/search',
        queryParameters: {'q': query},
        options: _authHeader(token),
      );
      return MessageSearchResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<Message> sendMessage(
    String token,
    String chatId,
    String? content, {
    List<String>? attachmentIds,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/chats/$chatId/messages',
        data: {'content': content, 'attachmentIds': attachmentIds},
        options: _authHeader(token),
      );
      return Message.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<Message> editMessage(String token, String chatId, String messageId, String content) async {
    try {
      final response = await _dio.put<dynamic>(
        '/api/chats/$chatId/messages/$messageId',
        data: {'content': content},
        options: _authHeader(token),
      );
      return Message.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<void> deleteMessage(String token, String chatId, String messageId) async {
    try {
      await _dio.delete<dynamic>('/api/chats/$chatId/messages/$messageId', options: _authHeader(token));
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<void> markRead(String token, String chatId) async {
    try {
      await _dio.post<dynamic>('/api/chats/$chatId/messages/read', options: _authHeader(token));
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<void> markDelivered(String token, String chatId, String messageId) async {
    try {
      await _dio.post<dynamic>(
        '/api/chats/$chatId/messages/$messageId/delivered',
        options: _authHeader(token),
      );
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Options _authHeader(String token) => Options(headers: {'Authorization': 'Bearer $token'});
}
