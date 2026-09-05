import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/error_presenter.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorView(
          message: error is AppException ? error.message : 'Something went wrong. Please try again.',
          onRetry: () => ref.read(archivedChatsControllerProvider.notifier).refresh(),
        ),
        data: (chats) {
          if (chats.isEmpty) {
            return const _EmptyView(
              key: Key('archived_chats_empty_view'),
              message: 'No archived chats.',
            );
          }
          return ListView.builder(
            key: const Key('archived_chats_list'),
            itemCount: chats.length,
            itemBuilder: (context, index) => _ArchivedChatTile(chat: chats[index], token: token),
          );
        },
      ),
    );
  }
}

class _ArchivedChatTile extends ConsumerStatefulWidget {
  const _ArchivedChatTile({required this.chat, required this.token});

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
        ListTile(
          key: Key('archived_chat_tile_${chat.id}'),
          leading: ProfileAvatar(avatarFileName: chat.otherUser.avatarFileName, token: widget.token, radius: 20),
          title: Text(chat.otherUser.username),
          subtitle: Text(chat.previewText, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: _isUnarchiving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  key: Key('unarchive_chat_button_${chat.id}'),
                  onPressed: _unarchive,
                  child: const Text('Unarchive'),
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text(
              _error!,
              key: Key('chat_unarchive_error_${chat.id}'),
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
            Icon(Icons.archive_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
