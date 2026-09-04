import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import '../auth/auth_providers.dart';
import '../auth/domain/auth_state.dart';
import 'data/contact_api.dart';
import 'domain/contact.dart';
import 'domain/contact_user_summary.dart';
import 'domain/pending_invitation.dart';

final contactApiProvider = Provider<ContactApi>((ref) => ContactApi(ref.watch(dioProvider)));

/// Holds the current user's accepted contacts.
class ContactsController extends AsyncNotifier<List<Contact>> {
  @override
  Future<List<Contact>> build() async {
    final token = await _requireToken();
    return ref.read(contactApiProvider).listContacts(token);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final token = await _requireToken();
      return ref.read(contactApiProvider).listContacts(token);
    });
  }

  Future<String> _requireToken() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('ContactsController used while not authenticated');
    }
    return authState.token;
  }
}

final contactsControllerProvider = AsyncNotifierProvider<ContactsController, List<Contact>>(
  ContactsController.new,
);

/// Holds the current user's incoming pending invitations, and lets the UI
/// accept/decline them.
///
/// Accepting or declining removes the invitation from this list on success
/// (the caller is expected to catch and present any thrown error - this
/// class doesn't swallow failures into an error state, since a failed
/// accept/decline shouldn't blank out the rest of the pending list).
class PendingInvitationsController extends AsyncNotifier<List<PendingInvitation>> {
  @override
  Future<List<PendingInvitation>> build() async {
    final token = await _requireToken();
    return ref.read(contactApiProvider).listPendingInvitations(token);
  }

  Future<void> accept(String invitationId) async {
    final token = await _requireToken();
    await ref.read(contactApiProvider).acceptInvitation(token, invitationId);
    _removeInvitation(invitationId);
    ref.invalidate(contactsControllerProvider);
  }

  Future<void> decline(String invitationId) async {
    final token = await _requireToken();
    await ref.read(contactApiProvider).declineInvitation(token, invitationId);
    _removeInvitation(invitationId);
  }

  void _removeInvitation(String invitationId) {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.where((invitation) => invitation.id != invitationId).toList());
    }
  }

  Future<String> _requireToken() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('PendingInvitationsController used while not authenticated');
    }
    return authState.token;
  }
}

final pendingInvitationsControllerProvider =
    AsyncNotifierProvider<PendingInvitationsController, List<PendingInvitation>>(
  PendingInvitationsController.new,
);

/// Holds the current contact search results. Starts empty (no search
/// performed yet) rather than eagerly loading anything on build.
class ContactSearchController extends AsyncNotifier<List<ContactUserSummary>> {
  @override
  Future<List<ContactUserSummary>> build() async => [];

  Future<void> search(String query) async {
    if (query.trim().length < 2) {
      state = const AsyncData([]);
      return;
    }
    final token = await _requireToken();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(contactApiProvider).search(token, query));
  }

  Future<String> _requireToken() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('ContactSearchController used while not authenticated');
    }
    return authState.token;
  }
}

final contactSearchControllerProvider =
    AsyncNotifierProvider<ContactSearchController, List<ContactUserSummary>>(
  ContactSearchController.new,
);
