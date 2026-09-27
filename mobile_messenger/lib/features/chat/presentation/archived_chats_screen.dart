import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/error_presenter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_states.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import 'widgets/chat_list_tile.dart';
import '../chat_providers.dart';
import '../domain/chat_summary.dart';

class ArchivedChatsScreen extends ConsumerWidget {
  const ArchivedChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedState = ref.watch(archivedChatsControllerProvider);
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;

    return Scaffold(
      key: const Key('archived_chats_screen'),
      appBar: AppBar(title: const Text('Archived Chats')),
      body: archivedState.when(
        loading: () => const ListSkeleton(),
        error: (error, stackTrace) => AppErrorState(
          message: error is AppException ? error.message : 'Something went wrong. Please try again.',
          onRetry: () => ref.read(archivedChatsControllerProvider.notifier).refresh(),
        ),
        data: (chats) {
          if (chats.isEmpty) {
            return const AppEmptyState(
              key: Key('archived_chats_empty_view'),
              icon: Icons.inventory_2_rounded,
              title: 'No archived chats.',
              message: 'Archive a chat to tuck it away here. It comes back the moment you unarchive it.',
            );
          }
          return ListView.builder(
            key: const Key('archived_chats_list'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              // Keyed by chat id (not list position) so Flutter doesn't
              // reuse this tile's State object - including its in-flight
              // _isUnarchiving flag - for a *different* chat that happens
              // to land at the same index after this one is removed from
              // the list, which otherwise left an unrelated tile stuck
              // showing a permanent spinner.
              return _ArchivedChatTile(key: ValueKey(chat.id), chat: chat, token: token);
            },
          );
        },
      ),
    );
  }
}

class _ArchivedChatTile extends ConsumerStatefulWidget {
  const _ArchivedChatTile({super.key, required this.chat, required this.token});

  final ChatSummary chat;
  final String? token;

  @override
  ConsumerState<_ArchivedChatTile> createState() => _ArchivedChatTileState();
}

class _ArchivedChatTileState extends ConsumerState<_ArchivedChatTile> {
  bool _isUnarchiving = false;
  String? _error;

  Future<void> _unarchive() async {
    setState(() {
      _isUnarchiving = true;
      _error = null;
    });
    try {
      await ref.read(archivedChatsControllerProvider.notifier).unarchive(widget.chat.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUnarchiving = false;
        _error = presentError(e).message;
      });
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat unarchived')));
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChatListTile(
          tileKey: Key('archived_chat_tile_${chat.id}'),
          chat: chat,
          token: widget.token,
          trailing: _isUnarchiving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : OutlinedButton(
                  key: Key('unarchive_chat_button_${chat.id}'),
                  onPressed: _unarchive,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                  child: const Text('Unarchive'),
                ),
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
                    key: Key('chat_unarchive_error_${chat.id}'),
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
