import 'dart:async';

import 'package:audioplayers/audioplayers.dart' show PlayerState;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/app_exception.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../contact/domain/contact_user_summary.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../chat_room_providers.dart';
import '../data/chat_audio_player.dart';
import '../domain/attachment.dart';
import '../domain/message.dart';
import '../domain/pending_attachment.dart';
import 'image_viewer_screen.dart';
import 'video_player_screen.dart';

/// A single conversation: message history, composer (text and/or an image
/// or video attachment), typing indicator, and per-message status/edit/delete.
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
    final room = ref.read(chatRoomControllerProvider(widget.chatId)).value;
    final pending = room?.pendingAttachment;
    // Blocked while an attachment is uploading or failed - the composer's
    // send button is already disabled in that state, this is just a guard.
    if (pending != null && pending.state != PendingAttachmentState.uploaded) return;
    if (text.trim().isEmpty && pending?.uploaded == null) return;

    ref.read(chatRoomControllerProvider(widget.chatId).notifier).send(text);
    _controller.clear();
  }

  Future<void> _showAttachmentPicker() async {
    final notifier = ref.read(chatRoomControllerProvider(widget.chatId).notifier);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('pick_image_gallery_action'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo from gallery'),
              onTap: () {
                Navigator.pop(context);
                notifier.pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              key: const Key('pick_image_camera_action'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(context);
                notifier.pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              key: const Key('pick_video_gallery_action'),
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Video from gallery'),
              onTap: () {
                Navigator.pop(context);
                notifier.pickVideo(ImageSource.gallery);
              },
            ),
            ListTile(
              key: const Key('pick_video_camera_action'),
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record video'),
              onTap: () {
                Navigator.pop(context);
                notifier.pickVideo(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// A highly visible, screen-level failure notice - deliberately separate
  /// from (and redundant with) the per-message failed icon/"tap to retry"
  /// text on the bubble itself. This only depends on the message list
  /// actually containing a message whose `sendState` is `failed`; it does
  /// not care why it got there or how long that took, so it works
  /// regardless of whichever specific timeout/watchdog mechanism is what
  /// actually caught the failure.
  void _notifyIfNewlyFailed(AsyncValue<ChatRoomState>? previous, AsyncValue<ChatRoomState> next) {
    final previousFailedIds =
        previous?.value?.messages.where((m) => m.sendState == SendState.failed).map((m) => m.id).toSet() ??
            const <String>{};
    final nextFailed = next.value?.messages.where((m) => m.sendState == SendState.failed) ?? const [];
    final newlyFailed = nextFailed.where((m) => !previousFailedIds.contains(m.id));
    if (newlyFailed.isEmpty) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        key: const Key('message_failed_snackbar'),
        content: const Text('Unable to send message. Check your connection and try again.'),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatRoomControllerProvider(widget.chatId), _notifyIfNewlyFailed);
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
                          onSendTimeout: () => ref
                              .read(chatRoomControllerProvider(widget.chatId).notifier)
                              .forceFailIfStillSending(message.id),
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
            if (room.pendingAttachment != null)
              _PendingAttachmentPreview(
                pending: room.pendingAttachment!,
                onRemove: () =>
                    ref.read(chatRoomControllerProvider(widget.chatId).notifier).removePendingAttachment(),
                onRetry: () => ref
                    .read(chatRoomControllerProvider(widget.chatId).notifier)
                    .retryPendingAttachmentUpload(),
              ),
            if (room.audioRecordingError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  room.audioRecordingError!,
                  key: const Key('audio_recording_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(height: 1),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: room.isRecordingAudio
                    ? _RecordingRow(
                        seconds: room.recordingSeconds,
                        onCancel: () => ref
                            .read(chatRoomControllerProvider(widget.chatId).notifier)
                            .cancelRecordingAudio(),
                        onStop: () => ref
                            .read(chatRoomControllerProvider(widget.chatId).notifier)
                            .stopRecordingAudioAndSend(),
                      )
                    : Row(
                        children: [
                          IconButton(
                            key: const Key('attach_button'),
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            onPressed: room.pendingAttachment != null ? null : _showAttachmentPicker,
                          ),
                          IconButton(
                            key: const Key('record_audio_button'),
                            icon: const Icon(Icons.mic_none_outlined),
                            onPressed: room.pendingAttachment != null
                                ? null
                                : () => ref
                                    .read(chatRoomControllerProvider(widget.chatId).notifier)
                                    .startRecordingAudio(),
                          ),
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
                              onChanged: (text) => ref
                                  .read(chatRoomControllerProvider(widget.chatId).notifier)
                                  .onComposerChanged(text),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const Key('send_button'),
                            icon: const Icon(Icons.send),
                            onPressed: room.pendingAttachment != null &&
                                    room.pendingAttachment!.state != PendingAttachmentState.uploaded
                                ? null
                                : _send,
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

/// Replaces the normal composer row while a voice message is being
/// recorded: a clear, unmistakable "recording" state (per-second timer, a
/// pulsing red dot) plus explicit cancel (discard) and stop-and-send actions
/// - never a bare mic icon with no feedback that anything is happening.
class _RecordingRow extends StatefulWidget {
  const _RecordingRow({required this.seconds, required this.onCancel, required this.onStop});

  final int seconds;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  @override
  State<_RecordingRow> createState() => _RecordingRowState();
}

class _RecordingRowState extends State<_RecordingRow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('cancel_recording_button'),
          icon: const Icon(Icons.delete_outline),
          onPressed: widget.onCancel,
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FadeTransition(
                opacity: _pulseController,
                child: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                'Recording... ${_formatDuration(widget.seconds)}',
                key: const Key('recording_indicator'),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('stop_recording_button'),
          icon: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
          onPressed: widget.onStop,
        ),
      ],
    );
  }
}

class _PendingAttachmentPreview extends StatelessWidget {
  const _PendingAttachmentPreview({required this.pending, required this.onRemove, required this.onRetry});

  final PendingAttachment pending;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('pending_attachment_preview'),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: switch (pending.kind) {
              AttachmentKind.image => Image.file(pending.file, width: 56, height: 56, fit: BoxFit.cover),
              AttachmentKind.video => Container(
                  width: 56,
                  height: 56,
                  color: colorScheme.surfaceContainerHigh,
                  child: const Icon(Icons.videocam_outlined),
                ),
              AttachmentKind.audio => Container(
                  width: 56,
                  height: 56,
                  color: colorScheme.surfaceContainerHigh,
                  child: const Icon(Icons.mic_none_outlined),
                ),
            },
          ),
          const SizedBox(width: 12),
          Expanded(child: _statusContent(context, colorScheme)),
          IconButton(
            key: const Key('remove_pending_attachment_button'),
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  Widget _statusContent(BuildContext context, ColorScheme colorScheme) {
    switch (pending.state) {
      case PendingAttachmentState.uploading:
        return const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Uploading...', key: Key('attachment_uploading_label')),
          ],
        );
      case PendingAttachmentState.uploaded:
        return const Text('Ready to send', key: Key('attachment_uploaded_label'));
      case PendingAttachmentState.failed:
        return Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 18),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Upload failed',
                key: const Key('attachment_failed_label'),
                style: TextStyle(color: colorScheme.error),
              ),
            ),
            TextButton(
              key: const Key('retry_attachment_upload_button'),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        );
    }
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
    required this.onSendTimeout,
  });

  final Message message;
  final bool isMine;
  final String? token;
  final VoidCallback onRetry;
  final void Function(String content) onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSendTimeout;

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
    final hasText = !message.deleted && (message.content?.isNotEmpty ?? false);

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
          else if (hasText)
            Text(message.content!, key: Key('message_content_${message.id}')),
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
