import 'package:dio/dio.dart';

import '../../../core/network/dio_exception_mapper.dart';
import '../domain/group.dart';

/// API service layer for `/api/groups*`.
class GroupApi {
  GroupApi(this._dio);

  final Dio _dio;

  Future<GroupDetails> createGroup(String token, String name, List<String> memberIds) =>
      _details(() => _dio.post<dynamic>(
            '/api/groups',
            data: {'name': name, 'memberIds': memberIds},
            options: _authHeader(token),
          ));

  Future<GroupDetails> getGroup(String token, String groupId) =>
      _details(() => _dio.get<dynamic>('/api/groups/$groupId', options: _authHeader(token)));

  Future<GroupDetails> invite(String token, String groupId, List<String> userIds) =>
      _details(() => _dio.post<dynamic>(
            '/api/groups/$groupId/invitations',
            data: {'userIds': userIds},
            options: _authHeader(token),
          ));

  Future<List<PendingGroupInvitation>> listPendingInvitations(String token) async {
    try {
      final response = await _dio.get<dynamic>('/api/groups/invitations/pending', options: _authHeader(token));
      return (response.data as List)
          .map((e) => PendingGroupInvitation.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<GroupDetails> acceptInvitation(String token, String invitationId) => _details(() =>
      _dio.post<dynamic>('/api/groups/invitations/$invitationId/accept', options: _authHeader(token)));

  Future<void> declineInvitation(String token, String invitationId) async {
    try {
      await _dio.post<dynamic>('/api/groups/invitations/$invitationId/decline', options: _authHeader(token));
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<GroupDetails> _details(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return GroupDetails.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Options _authHeader(String token) => Options(headers: {'Authorization': 'Bearer $token'});
}
