import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_presenter.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../contact/contact_providers.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../domain/group.dart';
import '../group_providers.dart';

/// Invite more of your contacts to an existing group. Contacts already in it
/// (or already invited) are not offered again.
class InviteToGroupDialog extends ConsumerStatefulWidget {
  const InviteToGroupDialog({super.key, required this.group});

  final GroupDetails group;

  static Future<bool?> show(BuildContext context, GroupDetails group) =>
      showDialog<bool>(context: context, builder: (_) => InviteToGroupDialog(group: group));

  @override
  ConsumerState<InviteToGroupDialog> createState() => _InviteToGroupDialogState();
}

class _InviteToGroupDialogState extends ConsumerState<InviteToGroupDialog> {
  final _selected = <String>{};
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      setState(() => _error = 'Choose at least one contact.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(groupActionsProvider).invite(widget.group.id, _selected.toList());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = presentError(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsControllerProvider);
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;
    final excluded = {
      ...widget.group.members.map((m) => m.user.id),
      ...widget.group.pendingInvitees.map((u) => u.id),
    };

    return AlertDialog(
      key: const Key('invite_to_group_dialog'),
      title: Text('Invite to ${widget.group.name}'),
      content: SizedBox(
        width: 420,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: contacts.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => const Center(child: Text('Could not load your contacts.')),
                data: (list) {
                  final candidates = list.where((c) => !excluded.contains(c.user.id)).toList();
                  if (candidates.isEmpty) {
                    return const Center(
                      child: Text(
                        'All of your contacts are already in this group or invited.',
                        key: Key('invite_no_candidates'),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      for (final contact in candidates)
                        CheckboxListTile(
                          key: Key('invite_contact_${contact.user.id}'),
                          contentPadding: EdgeInsets.zero,
                          secondary: ProfileAvatar(avatarFileName: contact.user.avatarFileName, token: token, radius: 16),
                          title: Text(contact.user.username),
                          value: _selected.contains(contact.user.id),
                          onChanged: (checked) => setState(() {
                            checked == true ? _selected.add(contact.user.id) : _selected.remove(contact.user.id);
                          }),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                key: const Key('invite_form_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('invite_submit'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Invite'),
        ),
      ],
    );
  }
}
