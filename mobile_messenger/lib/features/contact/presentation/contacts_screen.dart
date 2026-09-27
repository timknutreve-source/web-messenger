import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/error_presenter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_surface.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../contact_providers.dart';
import '../domain/contact.dart';
import '../domain/contact_user_summary.dart';
import '../domain/pending_invitation.dart';
import '../../group/domain/group.dart';
import '../../group/group_providers.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: const Key('contacts_screen'),
        appBar: AppBar(
          title: const Text('Contacts'),
          titleTextStyle: Theme.of(context).textTheme.headlineMedium,
          toolbarHeight: 64,
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('contacts_tab'), text: 'Contacts'),
              Tab(key: Key('pending_tab'), text: 'Requests'),
              Tab(key: Key('search_tab'), text: 'Find People'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [ContactsTab(), PendingInvitationsTab(), FindPeopleTab()],
        ),
      ),
    );
  }
}

String? _currentToken(WidgetRef ref) {
  final authState = ref.watch(authControllerProvider).value;
  return authState is AuthAuthenticated ? authState.token : null;
}

class ContactsTab extends ConsumerWidget {
  const ContactsTab({super.key, this.onOpenContact});

  /// When given, tapping a contact calls it (e.g. to open their chat).
  final void Function(Contact contact)? onOpenContact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsState = ref.watch(contactsControllerProvider);
    final token = _currentToken(ref);

    return contactsState.when(
      loading: () => const ListSkeleton(),
      error: (error, stackTrace) => AppErrorState(
        message: error is AppException ? error.message : 'Something went wrong. Please try again.',
        onRetry: () => ref.read(contactsControllerProvider.notifier).refresh(),
      ),
      data: (contacts) {
        if (contacts.isEmpty) {
          return const AppEmptyState(
            key: Key('contacts_empty_view'),
            icon: Icons.people_rounded,
            title: 'No contacts yet',
            message: 'Find people to add them, and your conversations start here.',
          );
        }
        return ListView.builder(
          key: const Key('contacts_list'),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
          itemCount: contacts.length,
          itemBuilder: (context, index) => _ContactTile(
            contact: contacts[index],
            token: token,
            onTap: onOpenContact == null ? null : () => onOpenContact!(contacts[index]),
          ),
        );
      },
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.token, this.onTap});

  final Contact contact;
  final String? token;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('contact_tile_${contact.user.id}'),
      leading: ProfileAvatar(avatarFileName: contact.user.avatarFileName, token: token, radius: 22, name: contact.user.username),
      title: Text(contact.user.username),
      subtitle: Text(contact.user.email),
      trailing: onTap == null ? null : Icon(Icons.chat_bubble_outline_rounded, size: 18, color: context.colors.textMuted),
      onTap: onTap,
    );
  }
}

/// Everything awaiting the user's answer: contact invitations and group
/// invitations, each in its own labelled section.
class PendingInvitationsTab extends ConsumerWidget {
  const PendingInvitationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactState = ref.watch(pendingInvitationsControllerProvider);
    final groupState = ref.watch(pendingGroupInvitationsControllerProvider);
    final token = _currentToken(ref);

    if (contactState.isLoading && !contactState.hasValue || groupState.isLoading && !groupState.hasValue) {
      return const ListSkeleton(rows: 3);
    }
    final error = contactState.hasError ? contactState.error : (groupState.hasError ? groupState.error : null);
    if (error != null && !contactState.hasValue) {
      return AppErrorState(
        message: error is AppException ? error.message : 'Something went wrong. Please try again.',
        onRetry: () {
          ref.invalidate(pendingInvitationsControllerProvider);
          ref.invalidate(pendingGroupInvitationsControllerProvider);
        },
      );
    }

    final contactInvitations = contactState.value ?? const <PendingInvitation>[];
    final groupInvitations = groupState.value ?? const <PendingGroupInvitation>[];
    if (contactInvitations.isEmpty && groupInvitations.isEmpty) {
      return const AppEmptyState(
        key: Key('pending_empty_view'),
        icon: Icons.mark_email_read_rounded,
        title: 'No pending invitations.',
        message: 'When someone invites you - to be a contact or to join a group - it shows up here.',
      );
    }
    return ListView(
      key: const Key('pending_invitations_list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        if (contactInvitations.isNotEmpty) ...[
          const AppSectionHeader('Contact invitations'),
          for (final invitation in contactInvitations)
            _PendingInvitationTile(key: ValueKey(invitation.id), invitation: invitation, token: token),
        ],
        if (groupInvitations.isNotEmpty) ...[
          const AppSectionHeader('Group invitations'),
          for (final invitation in groupInvitations)
            _PendingGroupInvitationTile(key: ValueKey(invitation.id), invitation: invitation, token: token),
        ],
      ],
    );
  }
}

class _PendingGroupInvitationTile extends ConsumerStatefulWidget {
  const _PendingGroupInvitationTile({super.key, required this.invitation, required this.token});

  final PendingGroupInvitation invitation;
  final String? token;

  @override
  ConsumerState<_PendingGroupInvitationTile> createState() => _PendingGroupInvitationTileState();
}

class _PendingGroupInvitationTileState extends ConsumerState<_PendingGroupInvitationTile> {
  bool _isProcessing = false;
  String? _error;

  Future<void> _respond(Future<void> Function(String) action) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      await action(widget.invitation.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = presentError(e).message;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final invitation = widget.invitation;
    final notifier = ref.read(pendingGroupInvitationsControllerProvider.notifier);
    final c = context.colors;

    return Padding(
      key: Key('pending_group_invitation_tile_${invitation.id}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: AppSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [c.accentGreen.withValues(alpha: 0.85), const Color(0xFF14503A)],
                    ),
                  ),
                  child: Icon(Icons.groups_rounded, size: 23, color: Colors.white.withValues(alpha: 0.95)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invitation.groupName, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        'Invited by ${invitation.inviter.username} · '
                        '${invitation.memberCount} ${invitation.memberCount == 1 ? 'member' : 'members'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _InlineError(_error!, key: Key('pending_group_invitation_error_${invitation.id}')),
            ],
            const SizedBox(height: AppSpacing.md),
            _ResponseButtons(
              isProcessing: _isProcessing,
              declineKey: Key('decline_group_invitation_button_${invitation.id}'),
              acceptKey: Key('accept_group_invitation_button_${invitation.id}'),
              acceptLabel: 'Join',
              onDecline: () => _respond(notifier.decline),
              onAccept: () => _respond(notifier.accept),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingInvitationTile extends ConsumerStatefulWidget {
  const _PendingInvitationTile({super.key, required this.invitation, required this.token});

  final PendingInvitation invitation;
  final String? token;

  @override
  ConsumerState<_PendingInvitationTile> createState() => _PendingInvitationTileState();
}

class _PendingInvitationTileState extends ConsumerState<_PendingInvitationTile> {
  bool _isProcessing = false;
  String? _error;

  Future<void> _respond(Future<void> Function(String) action) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      await action(widget.invitation.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = presentError(e).message;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final invitation = widget.invitation;
    final notifier = ref.read(pendingInvitationsControllerProvider.notifier);

    return Padding(
      key: Key('pending_invitation_tile_${invitation.id}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: AppSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(
                  avatarFileName: invitation.sender.avatarFileName,
                  token: widget.token,
                  radius: 22,
                  name: invitation.sender.username,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invitation.sender.username, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(invitation.sender.email, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _InlineError(_error!, key: Key('pending_invitation_error_${invitation.id}')),
            ],
            const SizedBox(height: AppSpacing.md),
            _ResponseButtons(
              isProcessing: _isProcessing,
              declineKey: Key('decline_invitation_button_${invitation.id}'),
              acceptKey: Key('accept_invitation_button_${invitation.id}'),
              acceptLabel: 'Accept',
              onDecline: () => _respond(notifier.decline),
              onAccept: () => _respond(notifier.accept),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decline (quiet) and accept (gold) - or a spinner while the answer is in flight.
class _ResponseButtons extends StatelessWidget {
  const _ResponseButtons({
    required this.isProcessing,
    required this.declineKey,
    required this.acceptKey,
    required this.acceptLabel,
    required this.onDecline,
    required this.onAccept,
  });

  final bool isProcessing;
  final Key declineKey;
  final Key acceptKey;
  final String acceptLabel;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return const SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: declineKey,
            onPressed: onDecline,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton(
            key: acceptKey,
            onPressed: onAccept,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text(acceptLabel),
          ),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 16, color: c.error),
        const SizedBox(width: 6),
        Expanded(child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.error))),
      ],
    );
  }
}

class FindPeopleTab extends ConsumerStatefulWidget {
  const FindPeopleTab({super.key});

  @override
  ConsumerState<FindPeopleTab> createState() => _FindPeopleTabState();
}

class _FindPeopleTabState extends ConsumerState<FindPeopleTab> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(contactSearchControllerProvider.notifier).search(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(contactSearchControllerProvider);
    final token = _currentToken(ref);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          child: TextField(
            key: const Key('contact_search_field'),
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search by username or email',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                key: const Key('contact_search_submit_button'),
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: _submit,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        Expanded(
          child: searchState.when(
            loading: () => const ListSkeleton(rows: 4),
            error: (error, stackTrace) => AppErrorState(
              message: error is AppException ? error.message : 'Something went wrong. Please try again.',
              onRetry: _submit,
            ),
            data: (results) {
              if (results.isEmpty) {
                return const AppEmptyState(
                  key: Key('search_empty_view'),
                  icon: Icons.person_search_rounded,
                  title: 'Search for people',
                  message: 'Search for people by username or email.',
                  compact: true,
                );
              }
              return ListView.builder(
                key: const Key('search_results_list'),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                itemCount: results.length,
                itemBuilder: (context, index) => _SearchResultTile(user: results[index], token: token),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchResultTile extends ConsumerStatefulWidget {
  const _SearchResultTile({required this.user, required this.token});

  final ContactUserSummary user;
  final String? token;

  @override
  ConsumerState<_SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends ConsumerState<_SearchResultTile> {
  bool _isSending = false;
  bool _sent = false;
  String? _error;

  Future<void> _sendInvitation() async {
    final authState = ref.read(authControllerProvider).value;
    if (authState is! AuthAuthenticated) return;

    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await ref.read(contactApiProvider).sendInvitation(authState.token, widget.user.id);
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = presentError(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      key: Key('search_result_tile_${widget.user.id}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
      child: AppSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(
                  avatarFileName: widget.user.avatarFileName,
                  token: widget.token,
                  radius: 22,
                  name: widget.user.username,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.user.username, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        widget.user.email,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_isSending)
              const SizedBox(
                height: 40,
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_sent)
              SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: c.success),
                    const SizedBox(width: 6),
                    Text(
                      'Invitation sent',
                      key: Key('invitation_sent_label_${widget.user.id}'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.success),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                key: Key('send_invitation_button_${widget.user.id}'),
                onPressed: _sendInvitation,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Send invitation'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _InlineError(_error!, key: Key('send_invitation_error_${widget.user.id}')),
            ],
          ],
        ),
      ),
    );
  }
}
