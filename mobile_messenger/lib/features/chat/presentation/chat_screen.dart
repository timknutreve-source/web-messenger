import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_exception.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../contact/domain/contact_user_summary.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../chat_room_providers.dart';
import '../domain/message.dart';

/// A single conversation: message history, composer, typing indicator, and
/// per-message status/edit/delete.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId, this.otherUser});

  final String chatId;
  final ContactUserSummary? otherUser;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadOlder);
  }

  @override
  void dispose() {
    // No explicit stopTyping()/disconnect() here: chatRoomControllerProvider
    // is autoDispose, so once this screen (its only watcher) is gone, the
    // provider's own ref.onDispose tears down typing state and the socket.
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadOlder() {
    if (_scrollController.position.pixels <= 40) {
      ref.read(chatRoomControllerProvider(widget.chatId).notifier).loadOlder();
    }
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    ref.read(chatRoomControllerProvider(widget.chatId).notifier).send(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(chatRoomControllerProvider(widget.chatId));
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;
    final myUserId = authState is AuthAuthenticated ? authState.user.id : null;

    return Scaffold(
      key: const Key('chat_screen'),
      appBar: AppBar(title: Text(widget.otherUser?.username ?? 'Chat')),
      body: roomState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorView(
          message: error is AppException ? error.message : 'Something went wrong. Please try again.',
          onRetry: () => ref.invalidate(chatRoomControllerProvider(widget.chatId)),
        ),
        data: (room) => Column(
          children: [
            if (room.loadingOlder)
              const LinearProgressIndicator(key: Key('loading_older_indicator'))
            else
              const SizedBox(height: 4),
            Expanded(
              child: room.messages.isEmpty
                  ? const _EmptyView()
                  : ListView.builder(
                      key: const Key('message_list'),
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: room.messages.length,
                      itemBuilder: (context, index) {
                        final message = room.messages[index];
                        return _MessageBubble(
                          message: message,
                          isMine: myUserId != null && message.sender.id == myUserId,
                          token: token,
                          onRetry: () =>
                              ref.read(chatRoomControllerProvider(widget.chatId).notifier).retry(message.id),
                          onEdit: (content) => ref
                              .read(chatRoomControllerProvider(widget.chatId).notifier)
                              .edit(message.id, content),
                          onDelete: () =>
                              ref.read(chatRoomControllerProvider(widget.chatId).notifier).delete(message.id),
                        );
                      },
                    ),
            ),
            if (room.typingUsername != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${room.typingUsername} is typing...',
                    key: const Key('typing_indicator'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
            const Divider(height: 1),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('message_input'),
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (text) =>
                            ref.read(chatRoomControllerProvider(widget.chatId).notifier).onComposerChanged(text),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('send_button'),
                      icon: const Icon(Icons.send),
                      onPressed: _send,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.token,
    required this.onRetry,
    required this.onEdit,
    required this.onDelete,
  });

  final Message message;
  final bool isMine;
  final String? token;
  final VoidCallback onRetry;
  final void Function(String content) onEdit;
  final VoidCallback onDelete;

  Future<void> _showEditDialog(BuildContext context) async {
    final controller = TextEditingController(text: message.content ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: controller, autofocus: true, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      onEdit(result);
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = isMine ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest;

    Widget bubble = Container(
      key: Key('message_bubble_${message.id}'),
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMine) Text(message.sender.username, style: Theme.of(context).textTheme.labelSmall),
          Text(
            message.deleted ? 'This message was deleted' : (message.content ?? ''),
            key: Key('message_content_${message.id}'),
            style: message.deleted
                ? TextStyle(fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant)
                : null,
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              if (message.edited && !message.deleted)
                Text('(edited)', style: Theme.of(context).textTheme.labelSmall),
              Text(
                _formatTime(message.createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (isMine) _StatusIndicator(message: message, onRetry: onRetry),
            ],
          ),
        ],
      ),
    );

    if (isMine && !message.deleted && message.sendState == SendState.confirmed) {
      bubble = GestureDetector(
        key: Key('message_menu_${message.id}'),
        onLongPress: () => showModalBottomSheet<void>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: Key('edit_message_action_${message.id}'),
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditDialog(context);
                  },
                ),
                ListTile(
                  key: Key('delete_message_action_${message.id}'),
                  leading: const Icon(Icons.delete),
                  title: const Text('Delete'),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(context);
                  },
                ),
              ],
            ),
          ),
        ),
        child: bubble,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            ProfileAvatar(avatarFileName: message.sender.avatarFileName, token: token, radius: 14),
            const SizedBox(width: 6),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }

  static String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.message, required this.onRetry});

  final Message message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (message.sendState) {
      case SendState.sending:
        return const SizedBox(
          key: Key('status_sending'),
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        );
      case SendState.failed:
        return InkWell(
          key: const Key('status_failed'),
          onTap: onRetry,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 2),
              Text('Failed, tap to retry', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11)),
            ],
          ),
        );
      case SendState.confirmed:
        return Icon(
          switch (message.status) {
            MessageStatus.sent => Icons.check,
            MessageStatus.delivered => Icons.done_all,
            MessageStatus.read => Icons.done_all,
          },
          key: Key('status_${message.status.name}'),
          size: 14,
          color: message.status == MessageStatus.read
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        );
    }
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

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
            const Text('No messages yet. Say hello!', key: Key('messages_empty_view'), textAlign: TextAlign.center),
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
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
