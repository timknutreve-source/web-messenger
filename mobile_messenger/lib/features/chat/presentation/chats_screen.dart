import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/network/error_presenter.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_states.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../group/presentation/create_group_dialog.dart';
import 'widgets/chat_list_tile.dart';
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
        titleTextStyle: Theme.of(context).textTheme.headlineMedium,
        toolbarHeight: 64,
        actions: [
          IconButton(
            key: const Key('new_group_button'),
            tooltip: 'New group',
            icon: const Icon(Icons.group_add_rounded),
            onPressed: () async {
              final group = await CreateGroupDialog.show(context);
              if (group != null && context.mounted) context.push('/chats/${group.id}');
            },
          ),
          IconButton(
            key: const Key('view_archived_chats_button'),
            tooltip: 'Archived chats',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => context.push('/chats/archived'),
          ),
          const SizedBox(width: 4),
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
      loading: () => const ListSkeleton(),
      error: (error, stackTrace) => AppErrorState(
        message: error is AppException ? error.message : 'Something went wrong. Please try again.',
        onRetry: () => ref.read(chatsControllerProvider.notifier).refresh(),
      ),
      data: (allChats) {
        if (allChats.isEmpty) {
          return const AppEmptyState(
            key: Key('chats_empty_view'),
            icon: Icons.forum_rounded,
            title: 'No chats yet',
            message: 'No chats yet. Add a contact to start one.',
          );
        }
        final needle = filter.trim().toLowerCase();
        final chats = needle.isEmpty
            ? allChats
            : allChats.where((c) => c.title.toLowerCase().contains(needle)).toList();
        if (chats.isEmpty) {
          return const AppEmptyState(
            key: Key('chats_no_match_view'),
            icon: Icons.search_off_rounded,
            title: 'No chats match your search.',
            compact: true,
          );
        }
        return ListView.builder(
          key: const Key('chats_list'),
          padding: const EdgeInsets.symmetric(vertical: 4),
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
        ChatListTile(
          tileKey: Key('chat_tile_${chat.id}'),
          chat: chat,
          token: widget.token,
          selected: widget.selected,
          onTap: widget.onOpen,
          busy: _isArchiving,
          unreadBadgeKey: Key('chat_unread_badge_${chat.id}'),
          actions: [
            if (widget.onOpenBeside != null)
              _TileAction(
                key: Key('open_beside_button_${chat.id}'),
                tooltip: 'Open side by side',
                icon: Icons.vertical_split_rounded,
                onPressed: widget.onOpenBeside,
              ),
            _TileAction(
              key: Key('archive_chat_button_${chat.id}'),
              tooltip: 'Archive',
              icon: Icons.inventory_2_outlined,
              onPressed: _archive,
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 16, color: context.colors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    key: Key('chat_archive_error_${chat.id}'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.error),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A compact icon button for the trailing actions of a chat row.
class _TileAction extends StatelessWidget {
  const _TileAction({super.key, required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        maximumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}
