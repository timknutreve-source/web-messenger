import 'dart:async';

import 'package:audioplayers/audioplayers.dart' show PlayerState;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../chat_room_providers.dart';
import '../data/chat_audio_player.dart';
import '../domain/attachment.dart';
import '../domain/message.dart';
import '../domain/poll.dart';
import 'poll_widgets.dart';
import 'widgets/highlighted_text.dart';
import 'image_viewer_screen.dart';
import 'video_player_screen.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.token,
    required this.onRetry,
    required this.onEdit,
    required this.onDelete,
    required this.onSendTimeout,
    this.onVote,
    this.onRetractVote,
    this.highlight,
    this.isCurrentMatch = false,
  });

  final Message message;
  final bool isMine;
  final String? token;
  final VoidCallback onRetry;
  final void Function(String content) onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSendTimeout;

  /// Called with (poll, optionId) when the user picks an option of this
  /// message's poll, and with the poll when they take their vote back.
  final void Function(Poll poll, String optionId)? onVote;
  final void Function(Poll poll)? onRetractVote;

  /// The text being searched for, marked wherever it appears in this bubble;
  /// [isCurrentMatch] additionally outlines the bubble as the selected result.
  final String? highlight;
  final bool isCurrentMatch;

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

  void _showActionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.poll == null)
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = isMine ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest;
    final hasText = !message.deleted && (message.content?.isNotEmpty ?? false);
    final poll = message.deleted ? null : message.poll;
    final canManage = isMine && !message.deleted && message.sendState == SendState.confirmed;
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    Widget bubble = Container(
      key: Key('message_bubble_${message.id}'),
      constraints: BoxConstraints(maxWidth: poll != null ? 340 : (isWide ? 440 : 280)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(12),
        border: isCurrentMatch ? Border.all(color: colorScheme.tertiary, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMine) Text(message.sender.username, style: Theme.of(context).textTheme.labelSmall),
          if (!message.deleted && message.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: Column(
                children: [
                  for (final attachment in message.attachments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _AttachmentBubbleContent(attachment: attachment, token: token),
                    ),
                ],
              ),
            ),
          if (message.deleted)
            Text(
              'This message was deleted',
              key: Key('message_content_${message.id}'),
              style: TextStyle(fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
            )
          else if (poll != null)
            PollBubbleContent(
              key: Key('poll_${poll.id}'),
              poll: poll,
              highlight: highlight,
              onVote: (optionId) => onVote?.call(poll, optionId),
              onRetract: () => onRetractVote?.call(poll),
            )
          else if (hasText)
            HighlightedText(
              message.content!,
              key: Key('message_content_${message.id}'),
              query: highlight,
              emphasize: isCurrentMatch,
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
              if (isMine)
                _StatusIndicator(message: message, onRetry: onRetry, onSendTimeout: onSendTimeout),
            ],
          ),
        ],
      ),
    );

    if (canManage) {
      bubble = GestureDetector(
        key: Key('message_menu_${message.id}'),
        onLongPress: () => _showActionsSheet(context),
        // Right-click, the desktop equivalent of a long press.
        onSecondaryTap: () => _showActionsSheet(context),
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
          if (canManage && isWide)
            // A pointer user has no long press: an always-visible menu button
            // next to their own messages does the same job.
            IconButton(
              key: Key('message_actions_button_${message.id}'),
              tooltip: 'Message actions',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showActionsSheet(context),
            ),
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

class _AttachmentBubbleContent extends StatelessWidget {
  const _AttachmentBubbleContent({required this.attachment, required this.token});

  final Attachment attachment;
  final String? token;

  @override
  Widget build(BuildContext context) {
    if (attachment.type == AttachmentKind.image) {
      return GestureDetector(
        key: Key('attachment_image_${attachment.id}'),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => ImageViewerScreen(imageUrl: attachment.url)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: (attachment.width != null && attachment.height != null && attachment.height! > 0)
                ? attachment.width! / attachment.height!
                : 4 / 3,
            child: token == null
                ? const ColoredBox(color: Colors.black12)
                : Image.network(
                    AppConfig.resolve(attachment.thumbnailUrl ?? attachment.url),
                    headers: {'Authorization': 'Bearer $token'},
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.broken_image_outlined, key: Key('attachment_image_error')),
                    ),
                  ),
          ),
        ),
      );
    }

    if (attachment.type == AttachmentKind.audio) {
      return _AudioMessageBubble(attachment: attachment, token: token);
    }

    return GestureDetector(
      key: Key('attachment_video_${attachment.id}'),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => VideoPlayerScreen(videoUrl: attachment.url)),
      ),
      child: Container(
        width: 220,
        height: 140,
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
            if (attachment.durationSeconds != null)
              Positioned(
                bottom: 6,
                right: 8,
                child: Text(
                  _formatDuration(attachment.durationSeconds!),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

/// A voice-message bubble: a play/pause button and (if known) its duration.
/// Genuinely plays the attachment's decrypted audio bytes (see
/// [ChatAudioPlayer]) - not a static mock - and reflects real play/pause/
/// completion state from the player, not merely a locally-toggled icon.
class _AudioMessageBubble extends ConsumerStatefulWidget {
  const _AudioMessageBubble({required this.attachment, required this.token});

  final Attachment attachment;
  final String? token;

  @override
  ConsumerState<_AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends ConsumerState<_AudioMessageBubble> {
  ChatAudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<void>? _completeSubscription;
  bool _isPlaying = false;
  bool _isLoading = false;

  Future<void> _togglePlayback() async {
    final token = widget.token;
    if (token == null || _isLoading) return;

    if (_isPlaying) {
      await _player?.pause();
      return;
    }

    final player = _player ?? ref.read(chatAudioPlayerFactoryProvider)();
    if (_player == null) {
      _player = player;
      _stateSubscription = player.onPlayerStateChanged.listen((playerState) {
        if (!mounted) return;
        setState(() => _isPlaying = playerState == PlayerState.playing);
      });
      _completeSubscription = player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() => _isPlaying = false);
      });
    }

    setState(() => _isLoading = true);
    try {
      await player.playFromUrl(AppConfig.resolve(widget.attachment.url), token);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _completeSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final duration = widget.attachment.durationSeconds;
    return Container(
      key: Key('attachment_audio_${widget.attachment.id}'),
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('audio_play_pause_button'),
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Icon(
                    _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    key: Key(_isPlaying ? 'audio_playing_icon' : 'audio_paused_icon'),
                  ),
            onPressed: _isLoading ? null : _togglePlayback,
          ),
          Icon(Icons.graphic_eq, color: colorScheme.onSurfaceVariant, size: 20),
          const Spacer(),
          if (duration != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                  _AttachmentBubbleContent._formatDuration(duration), style: Theme.of(context).textTheme.labelSmall),
            ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.message, required this.onRetry, required this.onSendTimeout});

  final Message message;
  final VoidCallback onRetry;
  final VoidCallback onSendTimeout;

  @override
  Widget build(BuildContext context) {
    switch (message.sendState) {
      case SendState.sending:
        return _SendingIndicator(onTimeout: onSendTimeout);
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
        final isRead = message.status == MessageStatus.read;
        final color = isRead
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (message.status) {
                MessageStatus.sent => Icons.check,
                MessageStatus.delivered => Icons.done_all,
                MessageStatus.read => Icons.done_all,
              },
              key: Key('status_${message.status.name}'),
              size: 14,
              color: color,
            ),
            // Read is otherwise visually identical to delivered (same
            // double-check icon, only a subtle color difference) - this
            // small label is what actually makes "read" unambiguous at a
            // glance, without a new row or a large banner.
            if (isRead) ...[
              const SizedBox(width: 2),
              Text(
                'Read',
                key: const Key('status_read_label'),
                style: TextStyle(fontSize: 10, color: color),
              ),
            ],
          ],
        );
    }
  }
}

/// The "sending" spinner for a message - and, deliberately, also this
/// message's own guarantee that it will not spin forever.
///
/// This does NOT rely on `dart:async` `Timer`/`Future.timeout()` (see
/// `ChatRoomController._submit`'s own watchdog, which already does exactly
/// that as a second, independent layer). Real-device testing kept showing
/// this spinner stay in "sending" indefinitely with no failure ever
/// surfacing, even with that Timer-based watchdog in place - while the
/// spinner itself visibly kept animating the whole time. A spinning
/// indeterminate `CircularProgressIndicator` only animates because
/// Flutter's own `Ticker`/`SchedulerBinding` is actively driving frames for
/// it; if that's demonstrably still running, hooking the "has this taken
/// too long?" check into a `Ticker` of our own - the same mechanism, not a
/// separate `dart:async` timer - means it can only ever fail to fire if
/// the UI has *itself* visibly stopped animating, which is not what was
/// observed.
class _SendingIndicator extends StatefulWidget {
  const _SendingIndicator({required this.onTimeout});

  final VoidCallback onTimeout;

  @override
  State<_SendingIndicator> createState() => _SendingIndicatorState();
}

class _SendingIndicatorState extends State<_SendingIndicator> with SingleTickerProviderStateMixin {
  static const _timeout = Duration(seconds: 5);

  late final DateTime _startedAt = DateTime.now();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();
  bool _timeoutDispatched = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_checkElapsed);
  }

  void _checkElapsed() {
    if (_timeoutDispatched) return;
    if (DateTime.now().difference(_startedAt) < _timeout) return;
    _timeoutDispatched = true;
    // Never mutate provider state synchronously from inside an animation
    // tick callback mid-build - defer to right after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTimeout();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: Key('status_sending'),
      width: 10,
      height: 10,
      child: CircularProgressIndicator(strokeWidth: 1.5),
    );
  }
}
