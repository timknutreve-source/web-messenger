import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_presenter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_surface.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../contact/contact_providers.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../domain/group.dart';
import '../group_providers.dart';

/// Name a new group and choose which of your contacts to invite. Pops the
/// created [GroupDetails] (its members are invited, not yet joined), or null
/// if cancelled.
class CreateGroupDialog extends ConsumerStatefulWidget {
  const CreateGroupDialog({super.key});

  static Future<GroupDetails?> show(BuildContext context) =>
      showDialog<GroupDetails>(context: context, builder: (_) => const CreateGroupDialog());

  @override
  ConsumerState<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<CreateGroupDialog> {
  final _name = TextEditingController();
  final _selected = <String>{};
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the group a name.');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = 'Choose at least one contact to invite.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final group = await ref.read(groupActionsProvider).createGroup(name, _selected.toList());
      if (mounted) Navigator.pop(context, group);
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

    return AlertDialog(
      key: const Key('create_group_dialog'),
      title: const Text('New group'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('group_name_field'),
              controller: _name,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 4),
            Text('Invite contacts', style: Theme.of(context).textTheme.labelLarge),
            Expanded(
              child: contacts.when(
                loading: () => const ListSkeleton(rows: 4, padding: EdgeInsets.zero),
                error: (error, stackTrace) => const AppErrorState(
                  message: 'Could not load your contacts.',
                  compact: true,
                  title: 'Contacts unavailable',
                ),
                data: (list) => list.isEmpty
                    ? const Center(
                        child: Text(
                          'You have no contacts yet. Add some first, then start a group.',
                          key: Key('group_no_contacts'),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        children: [
                          for (final contact in list)
                            CheckboxListTile(
                              key: Key('group_contact_${contact.user.id}'),
                              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                              secondary: ProfileAvatar(
                                avatarFileName: contact.user.avatarFileName,
                                token: token,
                                radius: 18,
                                name: contact.user.username,
                              ),
                              title: Text(contact.user.username),
                              value: _selected.contains(contact.user.id),
                              selected: _selected.contains(contact.user.id),
                              onChanged: (checked) => setState(() {
                                checked == true ? _selected.add(contact.user.id) : _selected.remove(contact.user.id);
                              }),
                            ),
                        ],
                      ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 16, color: context.colors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        key: const Key('group_form_error'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.error),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('group_create_submit'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const ButtonSpinner(size: 16)
              : const Text('Create group'),
        ),
      ],
    );
  }
}
