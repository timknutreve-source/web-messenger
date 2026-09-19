import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import '../../core/network/no_auto_retry.dart';
import '../auth/auth_providers.dart';
import '../auth/domain/auth_state.dart';
import '../chat/chat_providers.dart' show chatsControllerProvider;
import '../chat/domain/chat_event.dart';
import 'data/group_api.dart';
import 'domain/group.dart';

final groupApiProvider = Provider<GroupApi>((ref) => GroupApi(ref.watch(dioProvider)));

Future<String> _requireToken(Ref ref) async {
  final authState = await ref.read(authControllerProvider.future);
  if (authState is! AuthAuthenticated) {
    throw StateError('Group providers used while not authenticated');
  }
  return authState.token;
}

/// A group's members and pending invitees. Auto-disposed with whatever shows
/// it; a `MEMBER_JOINED` event (see `ChatRoomController`) invalidates it so an
/// open members list updates live.
final groupDetailsProvider = FutureProvider.autoDispose.family<GroupDetails, String>((ref, groupId) async {
  final token = await _requireToken(ref);
  return ref.read(groupApiProvider).getGroup(token, groupId);
});

/// The current user's incoming, unanswered group invitations.
///
/// It opens no WebSocket of its own: the user's personal invitations topic is
/// already subscribed to by `PendingInvitationsController`, which hands the
/// group-related events (`NEW_GROUP_INVITATION`, `INVITATION_RESOLVED`) over
/// through [applyEvent].
class PendingGroupInvitationsController extends AsyncNotifier<List<PendingGroupInvitation>> {
  @override
  Future<List<PendingGroupInvitation>> build() async {
    final token = await _requireToken(ref);
    return ref.read(groupApiProvider).listPendingInvitations(token);
  }

  void applyEvent(ChatEvent event) {
    final current = state.value;
    if (current == null) return;
    switch (event.type) {
      case 'NEW_GROUP_INVITATION':
        final invitation = PendingGroupInvitation.fromJson(event.payload);
        if (current.any((i) => i.id == invitation.id)) return;
        state = AsyncData([invitation, ...current]);
      case 'INVITATION_RESOLVED':
        if (event.payload['kind'] != 'GROUP') return;
        _remove(event.payload['invitationId'] as String);
        if (event.payload['accepted'] == true) {
          ref.invalidate(chatsControllerProvider);
        }
    }
  }

  Future<void> accept(String invitationId) async {
    final token = await _requireToken(ref);
    await ref.read(groupApiProvider).acceptInvitation(token, invitationId);
    _remove(invitationId);
    // Joining creates a chat (the group) for this user.
    ref.invalidate(chatsControllerProvider);
  }

  Future<void> decline(String invitationId) async {
    final token = await _requireToken(ref);
    await ref.read(groupApiProvider).declineInvitation(token, invitationId);
    _remove(invitationId);
  }

  void _remove(String invitationId) {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.where((i) => i.id != invitationId).toList());
    }
  }
}

final pendingGroupInvitationsControllerProvider =
    AsyncNotifierProvider<PendingGroupInvitationsController, List<PendingGroupInvitation>>(
  PendingGroupInvitationsController.new,
  retry: noAutoRetry,
);

/// Creating a group and inviting more contacts to one.
class GroupActions {
  GroupActions(this._ref);

  final Ref _ref;

  Future<GroupDetails> createGroup(String name, List<String> memberIds) async {
    final token = await _requireToken(_ref);
    final group = await _ref.read(groupApiProvider).createGroup(token, name, memberIds);
    _ref.invalidate(chatsControllerProvider);
    return group;
  }

  Future<GroupDetails> invite(String groupId, List<String> userIds) async {
    final token = await _requireToken(_ref);
    final group = await _ref.read(groupApiProvider).invite(token, groupId, userIds);
    _ref.invalidate(groupDetailsProvider(groupId));
    return group;
  }
}

final groupActionsProvider = Provider<GroupActions>(GroupActions.new);
