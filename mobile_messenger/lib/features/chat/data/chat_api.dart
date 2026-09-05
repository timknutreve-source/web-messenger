import 'package:dio/dio.dart';

import '../../../core/network/dio_exception_mapper.dart';
import '../domain/chat_summary.dart';

/// API service layer for `/api/chats*`.
class ChatApi {
  ChatApi(this._dio);

  final Dio _dio;

  Future<List<ChatSummary>> listActiveChats(String token) async {
    try {
      final response = await _dio.get<dynamic>('/api/chats', options: _authHeader(token));
      return (response.data as List)
          .map((e) => ChatSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<List<ChatSummary>> listArchivedChats(String token) async {
    try {
      final response = await _dio.get<dynamic>('/api/chats/archived', options: _authHeader(token));
      return (response.data as List)
          .map((e) => ChatSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<ChatSummary> archiveChat(String token, String chatId) async {
    try {
      final response =
          await _dio.post<dynamic>('/api/chats/$chatId/archive', options: _authHeader(token));
      return ChatSummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<ChatSummary> unarchiveChat(String token, String chatId) async {
    try {
      final response =
          await _dio.post<dynamic>('/api/chats/$chatId/unarchive', options: _authHeader(token));
      return ChatSummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Options _authHeader(String token) => Options(headers: {'Authorization': 'Bearer $token'});
}
