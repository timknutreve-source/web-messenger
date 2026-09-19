import '../../contact/domain/contact_user_summary.dart';

class GroupMember {
  const GroupMember({required this.user, required this.isAdmin, required this.joinedAt});

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        user: ContactUserSummary.fromJson(json['user'] as Map<String, dynamic>),
        isAdmin: json['role'] == 'ADMIN',
        joinedAt: DateTime.parse(json['joinedAt'] as String),
      );

  final ContactUserSummary user;
  final bool isAdmin;
  final DateTime joinedAt;
}

/// A group's name, current members, and the contacts invited but not yet answered.
class GroupDetails {
  const GroupDetails({
    required this.id,
    required this.name,
    required this.members,
    required this.pendingInvitees,
  });

  factory GroupDetails.fromJson(Map<String, dynamic> json) => GroupDetails(
        id: json['id'] as String,
        name: json['name'] as String,
        members: (json['members'] as List).map((e) => GroupMember.fromJson(e as Map<String, dynamic>)).toList(),
        pendingInvitees: (json['pendingInvitees'] as List)
            .map((e) => ContactUserSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String name;
  final List<GroupMember> members;
  final List<ContactUserSummary> pendingInvitees;
}

/// An incoming, not-yet-answered invitation to join a group.
class PendingGroupInvitation {
  const PendingGroupInvitation({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.memberCount,
    required this.inviter,
    required this.createdAt,
  });

  factory PendingGroupInvitation.fromJson(Map<String, dynamic> json) => PendingGroupInvitation(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        groupName: json['groupName'] as String,
        memberCount: json['memberCount'] as int,
        inviter: ContactUserSummary.fromJson(json['inviter'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String groupId;
  final String groupName;
  final int memberCount;
  final ContactUserSummary inviter;
  final DateTime createdAt;
}
