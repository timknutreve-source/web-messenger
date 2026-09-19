import 'package:dio/dio.dart';

import '../../../core/network/dio_exception_mapper.dart';
import '../domain/message.dart';
import '../domain/poll.dart';

/// API service layer for `/api/chats/{chatId}/polls*`.
class PollApi {
  PollApi(this._dio);

  final Dio _dio;

  /// Posts a new poll to a group; the server returns it as the new message.
  Future<Message> createPoll(
    String token,
    String chatId, {
    required String question,
    required List<String> options,
    required bool anonymous,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/chats/$chatId/polls',
        data: {'question': question, 'options': options, 'anonymous': anonymous},
        options: _authHeader(token),
      );
      return Message.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<Poll> getPoll(String token, String chatId, String pollId) async {
    try {
      final response = await _dio.get<dynamic>('/api/chats/$chatId/polls/$pollId', options: _authHeader(token));
      return Poll.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<Poll> vote(String token, String chatId, String pollId, String optionId) async {
    try {
      final response = await _dio.put<dynamic>(
        '/api/chats/$chatId/polls/$pollId/vote',
        data: {'optionId': optionId},
        options: _authHeader(token),
      );
      return Poll.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<Poll> retractVote(String token, String chatId, String pollId) async {
    try {
      final response = await _dio.delete<dynamic>(
        '/api/chats/$chatId/polls/$pollId/vote',
        options: _authHeader(token),
      );
      return Poll.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Options _authHeader(String token) => Options(headers: {'Authorization': 'Bearer $token'});
}
