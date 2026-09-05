import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/error_presenter.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../chat_providers.dart';
import '../domain/chat_summary.dart';

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsState = ref.watch(chatsControllerProvider);
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;

    return Scaffold(
      key: const Key('chats_screen'),
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            key: const Key('view_archived_chats_button'),
            tooltip: 'Archived chats',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => context.push('/chats/archived'),
          ),
        ],
      ),
      body: chatsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorView(
          message: error is AppException ? error.message : 'Something went wrong. Please try again.',
          onRetry: () => ref.read(chatsControllerProvider.notifier).refresh(),
        ),
        data: (chats) {
          if (chats.isEmpty) {
            return const _EmptyView(
              key: Key('chats_empty_view'),
              message: 'No chats yet. Add a contact to start one.',
            );
          }
          return ListView.builder(
            key: const Key('chats_list'),
            itemCount: chats.length,
            itemBuilder: (context, index) => _ChatTile(chat: chats[index], token: token),
          );
        },
      ),
    );
  }
}

class _ChatTile extends ConsumerStatefulWidget {
  const _ChatTile({required this.chat, required this.token});

  final ChatSummary chat;
  final String? token;

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
          leading: ProfileAvatar(avatarFileName: chat.otherUser.avatarFileName, token: widget.token, radius: 20),
          title: Text(chat.otherUser.username),
          subtitle: Text(chat.previewText, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: _isArchiving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  key: Key('archive_chat_button_${chat.id}'),
                  tooltip: 'Archive',
                  icon: const Icon(Icons.archive_outlined),
                  onPressed: _archive,
                ),
          onTap: () => context.push('/chats/${chat.id}', extra: chat.otherUser),
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
