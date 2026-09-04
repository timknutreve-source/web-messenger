import 'package:dio/dio.dart';

import '../../../core/network/dio_exception_mapper.dart';
import '../domain/contact.dart';
import '../domain/contact_user_summary.dart';
import '../domain/pending_invitation.dart';

/// API service layer for `/api/contacts*`.
class ContactApi {
  ContactApi(this._dio);

  final Dio _dio;

  Future<List<ContactUserSummary>> search(String token, String query) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/contacts/search',
        queryParameters: {'q': query},
        options: _authHeader(token),
      );
      return (response.data as List)
          .map((e) => ContactUserSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<List<Contact>> listContacts(String token) async {
    try {
      final response = await _dio.get<dynamic>('/api/contacts', options: _authHeader(token));
      return (response.data as List).map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<List<PendingInvitation>> listPendingInvitations(String token) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/contacts/invitations/pending',
        options: _authHeader(token),
      );
      return (response.data as List)
          .map((e) => PendingInvitation.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<void> sendInvitation(String token, String recipientId) async {
    try {
      await _dio.post<dynamic>(
        '/api/contacts/invitations',
        data: {'recipientId': recipientId},
        options: _authHeader(token),
      );
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<void> acceptInvitation(String token, String invitationId) async {
    try {
      await _dio.post<dynamic>(
        '/api/contacts/invitations/$invitationId/accept',
        options: _authHeader(token),
      );
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Future<void> declineInvitation(String token, String invitationId) async {
    try {
      await _dio.post<dynamic>(
        '/api/contacts/invitations/$invitationId/decline',
        options: _authHeader(token),
      );
    } on DioException catch (e) {
      throw mapApiDioException(e);
    }
  }

  Options _authHeader(String token) => Options(headers: {'Authorization': 'Bearer $token'});
}
