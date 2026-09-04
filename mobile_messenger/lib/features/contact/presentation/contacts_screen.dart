import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/error_presenter.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../contact_providers.dart';
import '../domain/contact.dart';
import '../domain/contact_user_summary.dart';
import '../domain/pending_invitation.dart';

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
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('contacts_tab'), text: 'Contacts'),
              Tab(key: Key('pending_tab'), text: 'Requests'),
              Tab(key: Key('search_tab'), text: 'Find People'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ContactsTab(), _PendingInvitationsTab(), _SearchTab()],
        ),
      ),
    );
  }
}

String? _currentToken(WidgetRef ref) {
  final authState = ref.watch(authControllerProvider).value;
  return authState is AuthAuthenticated ? authState.token : null;
}

class _ContactsTab extends ConsumerWidget {
  const _ContactsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsState = ref.watch(contactsControllerProvider);
    final token = _currentToken(ref);

    return contactsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _ErrorView(
        message: error is AppException ? error.message : 'Something went wrong. Please try again.',
        onRetry: () => ref.read(contactsControllerProvider.notifier).refresh(),
      ),
      data: (contacts) {
        if (contacts.isEmpty) {
          return const _EmptyView(
            key: Key('contacts_empty_view'),
            icon: Icons.people_outline,
            message: 'No contacts yet. Find people to add them.',
          );
        }
        return ListView.builder(
          key: const Key('contacts_list'),
          itemCount: contacts.length,
          itemBuilder: (context, index) => _ContactTile(contact: contacts[index], token: token),
        );
      },
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.token});

  final Contact contact;
  final String? token;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('contact_tile_${contact.user.id}'),
      leading: ProfileAvatar(avatarFileName: contact.user.avatarFileName, token: token, radius: 20),
      title: Text(contact.user.username),
      subtitle: Text(contact.user.email),
    );
  }
}

class _PendingInvitationsTab extends ConsumerWidget {
  const _PendingInvitationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingState = ref.watch(pendingInvitationsControllerProvider);
    final token = _currentToken(ref);

    return pendingState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _ErrorView(
        message: error is AppException ? error.message : 'Something went wrong. Please try again.',
        onRetry: () => ref.invalidate(pendingInvitationsControllerProvider),
      ),
      data: (invitations) {
        if (invitations.isEmpty) {
          return const _EmptyView(
            key: Key('pending_empty_view'),
            icon: Icons.mail_outline,
            message: 'No pending invitations.',
          );
        }
        return ListView.builder(
          key: const Key('pending_invitations_list'),
          itemCount: invitations.length,
          itemBuilder: (context, index) => _PendingInvitationTile(invitation: invitations[index], token: token),
        );
      },
    );
  }
}

class _PendingInvitationTile extends ConsumerStatefulWidget {
  const _PendingInvitationTile({required this.invitation, required this.token});

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ProfileAvatar(avatarFileName: invitation.sender.avatarFileName, token: widget.token, radius: 20),
            title: Text(invitation.sender.username),
            subtitle: Text(invitation.sender.email),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: Key('pending_invitation_error_${invitation.id}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_isProcessing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                TextButton(
                  key: Key('decline_invitation_button_${invitation.id}'),
                  onPressed: () => _respond(notifier.decline),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: Key('accept_invitation_button_${invitation.id}'),
                  onPressed: () => _respond(notifier.accept),
                  child: const Text('Accept'),
                ),
              ],
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }
}

class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab();

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
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
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const Key('contact_search_field'),
            controller: _controller,
            decoration: InputDecoration(
              labelText: 'Search by username or email',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                key: const Key('contact_search_submit_button'),
                icon: const Icon(Icons.search),
                onPressed: _submit,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        Expanded(
          child: searchState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _ErrorView(
              message: error is AppException ? error.message : 'Something went wrong. Please try again.',
              onRetry: _submit,
            ),
            data: (results) {
              if (results.isEmpty) {
                return const _EmptyView(
                  key: Key('search_empty_view'),
                  icon: Icons.person_search,
                  message: 'Search for people by username or email.',
                );
              }
              return ListView.builder(
                key: const Key('search_results_list'),
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
    return Column(
      key: Key('search_result_tile_${widget.user.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: ProfileAvatar(avatarFileName: widget.user.avatarFileName, token: widget.token, radius: 20),
          title: Text(widget.user.username),
          subtitle: Text(widget.user.email),
          trailing: _isSending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : _sent
                  ? Text(
                      'Invitation sent',
                      key: Key('invitation_sent_label_${widget.user.id}'),
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    )
                  : TextButton(
                      key: Key('send_invitation_button_${widget.user.id}'),
                      onPressed: _sendInvitation,
                      child: const Text('Send invitation'),
                    ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text(
              _error!,
              key: Key('send_invitation_error_${widget.user.id}'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
