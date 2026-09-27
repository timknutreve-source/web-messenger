import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_presenter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_states.dart';
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

    final c = context.colors;

    return Container(
      key: Key('chat_info_panel_$chatId'),
      color: c.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
        children: [
          if (onClose != null)
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(child: Text('Chat info', style: theme.textTheme.titleMedium)),
                  IconButton(
                    key: const Key('close_chat_info_button'),
                    tooltip: 'Close info',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          if (summary != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Center(child: ChatAvatar(chat: summary, token: token, radius: 44, ring: true)),
            const SizedBox(height: AppSpacing.md),
            Center(child: Text(summary.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center)),
            const SizedBox(height: 2),
            if (!summary.isGroup && summary.otherUser != null)
              Center(child: Text(summary.otherUser!.email, style: theme.textTheme.bodySmall))
            else if (summary.isGroup)
              Center(
                child: Text(
                  summary.memberCount == 1 ? 'Group · 1 member' : 'Group · ${summary.memberCount} members',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
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
    final c = context.colors;
    return Column(
      key: const Key('search_results_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          search.hasResults
              ? 'Search results (${search.results.length}${search.truncated ? '+' : ''})'
              : 'Search results',
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        ),
        if (search.noMatches)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.search_off_rounded, size: 18, color: c.textMuted),
                const SizedBox(width: AppSpacing.sm),
                Text('No matches', key: const Key('search_results_empty'), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        for (var i = 0; i < search.results.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: ListTile(
              key: Key('search_result_$i'),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
          ),
        const SizedBox(height: AppSpacing.sm),
        Divider(color: c.divider),
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
    final c = context.colors;

    return details.when(
      loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Column(
        children: [
          AppBanner(message: presentError(error).message, textKey: const Key('group_details_error')),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: () => ref.invalidate(groupDetailsProvider(chatId)), child: const Text('Retry')),
        ],
      ),
      data: (group) => Column(
        key: const Key('group_members_section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader('Members (${group.members.length})', padding: const EdgeInsets.fromLTRB(4, 4, 4, 8)),
          for (final member in group.members)
            ListTile(
              key: Key('group_member_${member.user.id}'),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              leading: ProfileAvatar(avatarFileName: member.user.avatarFileName, token: token, radius: 18, name: member.user.username),
              title: Text(member.user.username),
              trailing: member.isAdmin ? const StatusPill(label: 'Admin', icon: Icons.shield_rounded) : null,
            ),
          if (group.pendingInvitees.isNotEmpty) ...[
            AppSectionHeader('Invited (${group.pendingInvitees.length})', padding: const EdgeInsets.fromLTRB(4, 16, 4, 8)),
            for (final invitee in group.pendingInvitees)
              ListTile(
                key: Key('group_invitee_${invitee.id}'),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                leading: ProfileAvatar(avatarFileName: invitee.avatarFileName, token: token, radius: 18, name: invitee.username),
                title: Text(invitee.username),
                subtitle: const Text('Invitation pending'),
                trailing: Icon(Icons.hourglass_top_rounded, size: 16, color: c.warning),
              ),
          ],
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            key: const Key('invite_to_group_button'),
            icon: const Icon(Icons.person_add_alt_1_rounded),
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
