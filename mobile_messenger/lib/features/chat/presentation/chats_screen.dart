import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/error_presenter.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../group/presentation/create_group_dialog.dart';
import 'widgets/chat_avatar.dart';
import '../chat_providers.dart';
import '../domain/chat_summary.dart';

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: const Key('chats_screen'),
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            key: const Key('new_group_button'),
            tooltip: 'New group',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () async {
              final group = await CreateGroupDialog.show(context);
              if (group != null && context.mounted) context.push('/chats/${group.id}');
            },
          ),
          IconButton(
            key: const Key('view_archived_chats_button'),
            tooltip: 'Archived chats',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => context.push('/chats/archived'),
          ),
        ],
      ),
      body: ChatListView(
        onOpen: (chat) => context.push('/chats/${chat.id}', extra: chat.otherUser),
      ),
    );
  }
}

/// The list of active chats, newest activity first. Used as the whole page on
/// a phone and as the chat tab of the wide layout's left pane.
class ChatListView extends ConsumerWidget {
  const ChatListView({
    super.key,
    required this.onOpen,
    this.onOpenBeside,
    this.selectedChatIds = const {},
    this.filter = '',
  });

  final void Function(ChatSummary chat) onOpen;

  /// When given, each tile offers "open beside" (the second panel).
  final void Function(ChatSummary chat)? onOpenBeside;
  final Set<String> selectedChatIds;

  /// Only chats whose name contains this (case-insensitive) are listed.
  final String filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsState = ref.watch(chatsControllerProvider);
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;

    return chatsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _ErrorView(
        message: error is AppException ? error.message : 'Something went wrong. Please try again.',
        onRetry: () => ref.read(chatsControllerProvider.notifier).refresh(),
      ),
      data: (allChats) {
        if (allChats.isEmpty) {
          return const _EmptyView(
            key: Key('chats_empty_view'),
            message: 'No chats yet. Add a contact to start one.',
          );
        }
        final needle = filter.trim().toLowerCase();
        final chats = needle.isEmpty
            ? allChats
            : allChats.where((c) => c.title.toLowerCase().contains(needle)).toList();
        if (chats.isEmpty) {
          return const _EmptyView(key: Key('chats_no_match_view'), message: 'No chats match your search.');
        }
        return ListView.builder(
          key: const Key('chats_list'),
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chat = chats[index];
            // Keyed by chat id (not list position) so Flutter doesn't
            // reuse this tile's State object - including its in-flight
            // _isArchiving flag - for a *different* chat that happens to
            // land at the same index after this one is removed from the
            // list, which otherwise left an unrelated tile stuck showing
            // a permanent spinner.
            return _ChatTile(
              key: ValueKey(chat.id),
              chat: chat,
              token: token,
              selected: selectedChatIds.contains(chat.id),
              onOpen: () => onOpen(chat),
              onOpenBeside: onOpenBeside == null ? null : () => onOpenBeside!(chat),
            );
          },
        );
      },
    );
  }
}

class _ChatTile extends ConsumerStatefulWidget {
  const _ChatTile({
    super.key,
    required this.chat,
    required this.token,
    required this.selected,
    required this.onOpen,
    this.onOpenBeside,
  });

  final ChatSummary chat;
  final String? token;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback? onOpenBeside;

  @override
  ConsumerState<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends ConsumerState<_ChatTile> {
  bool _isArchiving = false;
  String? _error;

  Future<void> _archive() async {
    setState(() {
      _isArchiving = true;
      _error = null;
    });
    try {
      await ref.read(chatsControllerProvider.notifier).archive(widget.chat.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isArchiving = false;
        _error = presentError(e).message;
      });
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat archived')));
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: Key('chat_tile_${chat.id}'),
          selected: widget.selected,
          leading: ChatAvatar(chat: chat, token: widget.token, radius: 20),
          title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(chat.previewText, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: _isArchiving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (chat.unreadCount > 0)
                      Badge(
                        key: Key('chat_unread_badge_${chat.id}'),
                        label: Text('${chat.unreadCount}'),
                      ),
                    if (widget.onOpenBeside != null)
                      IconButton(
                        key: Key('open_beside_button_${chat.id}'),
                        tooltip: 'Open side by side',
                        icon: const Icon(Icons.vertical_split_outlined),
                        onPressed: widget.onOpenBeside,
                      ),
                    IconButton(
                      key: Key('archive_chat_button_${chat.id}'),
                      tooltip: 'Archive',
                      icon: const Icon(Icons.archive_outlined),
                      onPressed: _archive,
                    ),
                  ],
                ),
          onTap: widget.onOpen,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text(
              _error!,
              key: Key('chat_archive_error_${chat.id}'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
