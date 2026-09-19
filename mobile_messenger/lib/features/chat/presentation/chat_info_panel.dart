import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_presenter.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../group/group_providers.dart';
import '../../group/presentation/invite_to_group_dialog.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../chat_search_providers.dart';
import '../domain/chat_summary.dart';
import 'chat_panel.dart' show chatSummaryProvider;
import 'widgets/chat_avatar.dart';
import 'widgets/highlighted_text.dart';

/// Details about a chat: who is in it (and the option to invite more, for a
/// group), and - while an in-chat search is open - the list of its matches.
/// Shown as the right-hand pane of the wide layout, and as a page on a phone.
class ChatInfoPanel extends ConsumerWidget {
  const ChatInfoPanel({super.key, required this.chatId, this.onClose});

  final String chatId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(chatSummaryProvider(chatId));
    final search = ref.watch(chatSearchControllerProvider(chatId));
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;
    final theme = Theme.of(context);

    return Container(
      key: Key('chat_info_panel_$chatId'),
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (onClose != null)
            Row(
              children: [
                Expanded(child: Text('Chat info', style: theme.textTheme.titleMedium)),
                IconButton(
                  key: const Key('close_chat_info_button'),
                  tooltip: 'Close info',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
          if (summary != null) ...[
            Center(child: ChatAvatar(chat: summary, token: token, radius: 36)),
            const SizedBox(height: 8),
            Center(child: Text(summary.title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center)),
            if (!summary.isGroup && summary.otherUser != null)
              Center(child: Text(summary.otherUser!.email, style: theme.textTheme.bodySmall)),
            const SizedBox(height: 16),
          ],
          if (search.active && search.hasQuery) _SearchResultsSection(chatId: chatId, search: search),
          if (summary != null && summary.isGroup) _GroupMembersSection(chatId: chatId, summary: summary, token: token),
        ],
      ),
    );
  }
}

class _SearchResultsSection extends ConsumerWidget {
  const _SearchResultsSection({required this.chatId, required this.search});

  final String chatId;
  final ChatSearchState search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('search_results_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          search.hasResults ? 'Search results (${search.results.length}${search.truncated ? '+' : ''})' : 'Search results',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        if (search.noMatches) const Text('No matches', key: Key('search_results_empty')),
        for (var i = 0; i < search.results.length; i++)
          ListTile(
            key: Key('search_result_$i'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: i == search.currentIndex,
            title: HighlightedText(
              search.results[i].content ?? '',
              query: search.query,
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: Text(
              '${search.results[i].sender.username}  ${_formatDateTime(search.results[i].createdAt)}',
              style: theme.textTheme.labelSmall,
            ),
            onTap: () => ref.read(chatSearchControllerProvider(chatId).notifier).select(i),
          ),
        const Divider(),
      ],
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _GroupMembersSection extends ConsumerWidget {
  const _GroupMembersSection({required this.chatId, required this.summary, required this.token});

  final String chatId;
  final ChatSummary summary;
  final String? token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(groupDetailsProvider(chatId));
    final theme = Theme.of(context);

    return details.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Column(
        children: [
          Text(presentError(error).message, key: const Key('group_details_error')),
          TextButton(onPressed: () => ref.invalidate(groupDetailsProvider(chatId)), child: const Text('Retry')),
        ],
      ),
      data: (group) => Column(
        key: const Key('group_members_section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Members (${group.members.length})', style: theme.textTheme.titleSmall),
          for (final member in group.members)
            ListTile(
              key: Key('group_member_${member.user.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: ProfileAvatar(avatarFileName: member.user.avatarFileName, token: token, radius: 16),
              title: Text(member.user.username),
              trailing: member.isAdmin ? const Chip(label: Text('Admin'), visualDensity: VisualDensity.compact) : null,
            ),
          if (group.pendingInvitees.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Invited (${group.pendingInvitees.length})', style: theme.textTheme.titleSmall),
            for (final invitee in group.pendingInvitees)
              ListTile(
                key: Key('group_invitee_${invitee.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: ProfileAvatar(avatarFileName: invitee.avatarFileName, token: token, radius: 16),
                title: Text(invitee.username),
                subtitle: const Text('Invitation pending'),
              ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('invite_to_group_button'),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Invite contacts'),
            onPressed: () => InviteToGroupDialog.show(context, group),
          ),
        ],
      ),
    );
  }
}

/// [ChatInfoPanel] as a page (phone layout).
class ChatInfoScreen extends StatelessWidget {
  const ChatInfoScreen({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('chat_info_screen'),
      appBar: AppBar(title: const Text('Chat info')),
      body: ChatInfoPanel(chatId: chatId),
    );
  }
}
