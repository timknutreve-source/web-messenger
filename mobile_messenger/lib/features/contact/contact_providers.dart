import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import '../../core/network/no_auto_retry.dart';
import '../auth/auth_providers.dart';
import '../auth/domain/auth_state.dart';
import '../chat/chat_providers.dart';
import '../chat/chat_room_providers.dart' show chatWebSocketClientFactoryProvider;
import '../chat/data/chat_websocket_client.dart';
import '../group/group_providers.dart';
import '../chat/domain/chat_event.dart';
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
  retry: noAutoRetry,
);

/// Holds the current user's incoming pending invitations, and lets the UI
/// accept/decline them.
///
/// Accepting or declining removes the invitation from this list on success
/// (the caller is expected to catch and present any thrown error - this
/// class doesn't swallow failures into an error state, since a failed
/// accept/decline shouldn't blank out the rest of the pending list).
///
/// Besides the initial REST fetch, this also opens a live subscription to
/// the current user's own `/topic/users/{userId}/invitations` feed: without
/// it, an invitation sent while the recipient is already logged in and using
/// the app would never appear until their next login or app restart, since
/// nothing else would ever re-fetch this (non-autoDispose) list on its own.
class PendingInvitationsController extends AsyncNotifier<List<PendingInvitation>> {
  ChatWebSocketClient? _webSocket;

  @override
  Future<List<PendingInvitation>> build() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('PendingInvitationsController used while not authenticated');
    }
    final invitations = await ref.read(contactApiProvider).listPendingInvitations(authState.token);
    _connect(authState.token, authState.user.id);
    ref.onDispose(_disconnect);
    return invitations;
  }

  void _connect(String token, String userId) {
    final webSocket = ref.read(chatWebSocketClientFactoryProvider)();
    _webSocket = webSocket;
    webSocket.connect(
      token: token,
      onConnected: () => webSocket.subscribe('/topic/users/$userId/invitations', _handleEvent),
    );
  }

  void _handleEvent(ChatEvent event) {
    switch (event.type) {
      case 'NEW_INVITATION':
        final invitation = PendingInvitation.fromJson(event.payload);
        final current = state.value;
        if (current == null || current.any((i) => i.id == invitation.id)) return;
        state = AsyncData([invitation, ...current]);
      case 'INVITATION_RESOLVED':
        // Answered (or, for an invitation this user sent, accepted) on
        // another device or by the other person: drop it from pending and,
        // if accepted, pick up the new contact and chat.
        if (event.payload['kind'] == 'CONTACT') {
          _removeInvitation(event.payload['invitationId'] as String);
          if (event.payload['accepted'] == true) {
            ref.invalidate(contactsControllerProvider);
            ref.invalidate(chatsControllerProvider);
          }
        } else {
          ref.read(pendingGroupInvitationsControllerProvider.notifier).applyEvent(event);
        }
      case 'NEW_GROUP_INVITATION':
        ref.read(pendingGroupInvitationsControllerProvider.notifier).applyEvent(event);
    }
  }

  void _disconnect() {
    _webSocket?.disconnect();
    _webSocket = null;
  }

  Future<void> accept(String invitationId) async {
    final token = await _requireToken();
    await ref.read(contactApiProvider).acceptInvitation(token, invitationId);
    _removeInvitation(invitationId);
    ref.invalidate(contactsControllerProvider);
    // Accepting creates a new conversation server-side - without this, the
    // chat list (a non-autoDispose provider, cached for the app's session)
    // would keep showing its stale pre-accept state until the app restarts.
    ref.invalidate(chatsControllerProvider);
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
  retry: noAutoRetry,
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
