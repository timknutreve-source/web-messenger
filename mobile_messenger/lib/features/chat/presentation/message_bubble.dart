import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart' show PlayerState;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/hover_reveal.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
import '../chat_room_providers.dart';
import '../data/chat_audio_player.dart';
import '../domain/attachment.dart';
import '../domain/message.dart';
import '../domain/poll.dart';
import 'image_viewer_screen.dart';
import 'poll_widgets.dart';
import 'video_player_screen.dart';
import 'widgets/highlighted_text.dart';

/// One message in a conversation: bubble (or poll card), sender, media,
/// timestamp and delivery status, plus the day separator above it when a new
/// day starts.
///
/// Consecutive messages from one sender are visually grouped: tighter spacing,
/// the sender name only on the first, the avatar only on the last.
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
    this.isGroup = false,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.dayLabel,
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

  /// In a group chat the sender's name and avatar are shown on incoming
  /// messages; in a direct chat they would be redundant.
  final bool isGroup;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  /// "Today", "Yesterday", "12 Mar" - set when this message starts a new day.
  final String? dayLabel;

  static const double _avatarSlot = 36;

  Future<void> _showEditDialog(BuildContext context) async {
    final controller = TextEditingController(text: message.content ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.edit_rounded),
        title: const Text('Edit message'),
        content: TextField(controller: controller, autofocus: true, maxLines: 4, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
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
    final c = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.delete_outline_rounded, color: c.error),
        title: const Text('Delete message?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.error,
              foregroundColor: Colors.white,
              minimumSize: const Size(88, 44),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete();
    }
  }

  void _showActionsSheet(BuildContext context) {
    final c = context.colors;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.poll == null)
                ListTile(
                  key: Key('edit_message_action_${message.id}'),
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditDialog(context);
                  },
                ),
              ListTile(
                key: Key('delete_message_action_${message.id}'),
                leading: Icon(Icons.delete_outline_rounded, color: c.error),
                title: Text('Delete', style: TextStyle(color: c.error)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poll = message.deleted ? null : message.poll;
    final canManage = isMine && !message.deleted && message.sendState == SendState.confirmed;
    final isWide = MediaQuery.sizeOf(context).width >= AppLayout.wideContent;
    final showAvatar = isGroup && !isMine;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - (showAvatar ? _avatarSlot : 0) - (canManage && isWide ? 44 : 0);
        final maxBubble = (available * 0.82).clamp(210.0, 560.0).toDouble();

        Widget body = poll != null
            ? _pollCard(context, poll, math.min(maxBubble, 400.0))
            : _bubble(context, maxBubble);

        if (canManage) {
          body = GestureDetector(
            key: Key('message_menu_${message.id}'),
            onLongPress: () => _showActionsSheet(context),
            // Right-click, the desktop equivalent of a long press.
            onSecondaryTap: () => _showActionsSheet(context),
            child: body,
          );
        }

        final row = HoverReveal(
          builder: (context, revealed) => Row(
            mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showAvatar)
                SizedBox(
                  width: _avatarSlot,
                  child: isLastInGroup
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ProfileAvatar(
                            avatarFileName: message.sender.avatarFileName,
                            token: token,
                            radius: 14,
                            name: message.sender.username,
                          ),
                        )
                      : null,
                ),
              if (canManage && isWide)
                AnimatedOpacity(
                  duration: AppDurations.fast,
                  opacity: revealed ? 1 : 0,
                  // Faded out, not removed: keyboard and screen-reader users still reach it.
                  alwaysIncludeSemantics: true,
                  child: IconButton(
                    key: Key('message_actions_button_${message.id}'),
                    tooltip: 'Message actions',
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: () => _showActionsSheet(context),
                  ),
                ),
              Flexible(child: body),
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (dayLabel != null) _DayChip(label: dayLabel!),
            Padding(
              padding: EdgeInsets.only(top: isFirstInGroup ? 9 : 2, bottom: 1),
              child: row,
            ),
          ],
        );
      },
    );
  }

  // ---- the standard bubble ----

  Widget _bubble(BuildContext context, double maxWidth) {
    final c = context.colors;
    final hasText = !message.deleted && (message.content?.isNotEmpty ?? false);
    final hasAttachments = !message.deleted && message.attachments.isNotEmpty;
    final mediaOnly = hasAttachments && !hasText;

    final failed = message.sendState == SendState.failed;
    final radius = _radius();
    final textColor = isMine ? c.bubbleOutgoingText : c.textPrimary;

    final Border? border = failed
        ? Border.all(color: c.error, width: 1.4)
        : isCurrentMatch
            ? Border.all(color: c.primary, width: 2)
            : isMine
                ? null
                : Border.all(color: c.bubbleIncomingBorder);

    return AnimatedContainer(
      key: Key('message_bubble_${message.id}'),
      duration: AppDurations.medium,
      curve: AppDurations.standard,
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.fromLTRB(mediaOnly ? 4 : 13, mediaOnly ? 4 : 9, mediaOnly ? 4 : 13, 7),
      decoration: BoxDecoration(
        gradient: isMine ? c.outgoingBubbleGradient : null,
        color: isMine ? null : c.bubbleIncoming,
        borderRadius: radius,
        border: border,
        boxShadow: isCurrentMatch ? AppShadows.glow(c.primary) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSenderName)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                message.sender.username,
                style: TextStyle(
                  color: _nameTone(message.sender.username, c),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          if (hasAttachments)
            Padding(
              padding: EdgeInsets.only(bottom: hasText ? 6 : 2, top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final attachment in message.attachments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _AttachmentBubbleContent(attachment: attachment, token: token, mine: isMine),
                    ),
                ],
              ),
            ),
          if (message.deleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded, size: 15, color: isMine ? c.bubbleOutgoingMeta : c.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'This message was deleted',
                    key: Key('message_content_${message.id}'),
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                      color: isMine ? c.bubbleOutgoingMeta : c.textMuted,
                    ),
                  ),
                ),
              ],
            )
          else if (hasText)
            Padding(
              padding: mediaOnly ? const EdgeInsets.symmetric(horizontal: 8) : EdgeInsets.zero,
              child: HighlightedText(
                message.content!,
                key: Key('message_content_${message.id}'),
                query: highlight,
                emphasize: isCurrentMatch,
                style: TextStyle(color: textColor, fontSize: 15, height: 1.38),
              ),
            ),
          const SizedBox(height: 3),
          Padding(
            padding: mediaOnly ? const EdgeInsets.only(left: 8, right: 8, bottom: 2) : EdgeInsets.zero,
            child: _MetaRow(message: message, isMine: isMine, onRetry: onRetry, onSendTimeout: onSendTimeout),
          ),
        ],
      ),
    );
  }

  bool get showSenderName => isGroup && !isMine && isFirstInGroup && !message.deleted;

  BorderRadius _radius() {
    const big = Radius.circular(AppRadius.lg);
    const small = Radius.circular(6);
    const tail = Radius.circular(4);
    if (isMine) {
      return BorderRadius.only(
        topLeft: big,
        bottomLeft: big,
        topRight: isFirstInGroup ? big : small,
        bottomRight: isLastInGroup ? tail : small,
      );
    }
    return BorderRadius.only(
      topRight: big,
      bottomRight: big,
      topLeft: isFirstInGroup ? big : small,
      bottomLeft: isLastInGroup ? tail : small,
    );
  }

  // ---- poll card (a poll is its own surface, not a coloured bubble) ----

  Widget _pollCard(BuildContext context, Poll poll, double maxWidth) {
    final c = context.colors;
    return Container(
      key: Key('message_bubble_${message.id}'),
      constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 250),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: isCurrentMatch ? c.primary : c.border, width: isCurrentMatch ? 2 : 1),
        boxShadow: AppShadows.card(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSenderName || (isGroup && !isMine))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                message.sender.username,
                style: TextStyle(
                  color: _nameTone(message.sender.username, c),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          PollBubbleContent(
            key: Key('poll_${poll.id}'),
            poll: poll,
            highlight: highlight,
            onVote: (optionId) => onVote?.call(poll, optionId),
            onRetract: () => onRetractVote?.call(poll),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _MetaRow(
              message: message,
              isMine: isMine,
              onRetry: onRetry,
              onSendTimeout: onSendTimeout,
              onSurface: true,
            ),
          ),
        ],
      ),
    );
  }

  /// A readable, stable colour for a sender's name, derived from the name.
  static Color _nameTone(String name, AppColors c) {
    const hues = [152.0, 172.0, 96.0, 38.0, 14.0, 330.0, 200.0];
    final hue = hues[name.runes.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff) % hues.length];
    return HSLColor.fromAHSL(1, hue, 0.55, c.isDark ? 0.70 : 0.34).toColor();
  }
}

/// A centred "Today" / "Yesterday" / date pill between days.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: c.surfaceElevated.withValues(alpha: 0.9),
            borderRadius: AppRadius.pillAll,
            border: Border.all(color: c.divider),
          ),
          child: Text(
            label,
            style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3),
          ),
        ),
      ),
    );
  }
}

/// Time, "edited" marker and (for your own messages) the delivery status.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.message,
    required this.isMine,
    required this.onRetry,
    required this.onSendTimeout,
    this.onSurface = false,
  });

  final Message message;
  final bool isMine;
  final VoidCallback onRetry;
  final VoidCallback onSendTimeout;

  /// True when drawn on a neutral surface (a poll card) rather than a bubble.
  final bool onSurface;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = isMine && !onSurface ? c.bubbleOutgoingMeta : c.textMuted;
    final style = TextStyle(color: meta, fontSize: 11, height: 1.2, letterSpacing: 0.1);
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 5,
      runSpacing: 2,
      children: [
        if (message.edited && !message.deleted) Text('edited', style: style.copyWith(fontStyle: FontStyle.italic)),
        Text(_formatTime(message.createdAt), style: style),
        if (isMine)
          _StatusIndicator(
            message: message,
            onRetry: onRetry,
            onSendTimeout: onSendTimeout,
            metaColor: meta,
            onSurface: onSurface,
          ),
      ],
    );
  }

  static String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

// ---------------------------------------------------------------------------
// Attachments
// ---------------------------------------------------------------------------

class _AttachmentBubbleContent extends StatelessWidget {
  const _AttachmentBubbleContent({required this.attachment, required this.token, required this.mine});

  final Attachment attachment;
  final String? token;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (attachment.type == AttachmentKind.image) {
      return GestureDetector(
        key: Key('attachment_image_${attachment.id}'),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => ImageViewerScreen(imageUrl: attachment.url)),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 380),
              child: AspectRatio(
                aspectRatio: (attachment.width != null && attachment.height != null && attachment.height! > 0)
                    ? attachment.width! / attachment.height!
                    : 4 / 3,
                child: token == null
                    ? ColoredBox(color: c.surfaceHover)
                    : Image.network(
                        AppConfig.resolve(attachment.thumbnailUrl ?? attachment.url),
                        headers: {'Authorization': 'Bearer $token'},
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) => progress == null
                            ? child
                            : ColoredBox(
                                color: c.surfaceHover,
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                        errorBuilder: (context, error, stackTrace) => ColoredBox(
                          color: c.surfaceHover,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined, key: const Key('attachment_image_error'), color: c.textMuted),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }

    if (attachment.type == AttachmentKind.audio) {
      return _AudioMessageBubble(attachment: attachment, token: token, mine: mine);
    }

    return GestureDetector(
      key: Key('attachment_video_${attachment.id}'),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => VideoPlayerScreen(videoUrl: attachment.url)),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 240,
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B2A22), Color(0xFF0A0F0C)],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
              ),
              if (attachment.durationSeconds != null)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatDuration(attachment.durationSeconds!),
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
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

/// A voice-message bubble: a play/pause button, a decorative waveform and (if
/// known) its duration. Genuinely plays the attachment's decrypted audio bytes
/// (see [ChatAudioPlayer]) - not a static mock - and reflects real play/pause/
/// completion state from the player, not merely a locally-toggled icon.
class _AudioMessageBubble extends ConsumerStatefulWidget {
  const _AudioMessageBubble({required this.attachment, required this.token, required this.mine});

  final Attachment attachment;
  final String? token;
  final bool mine;

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
    final c = context.colors;
    final duration = widget.attachment.durationSeconds;
    final mine = widget.mine;
    final accent = mine ? Colors.white : c.primary;
    final onAccent = mine ? const Color(0xFF14503A) : c.textOnPrimary;
    final barColor = mine ? Colors.white.withValues(alpha: 0.55) : c.textMuted.withValues(alpha: 0.7);
    const heights = <double>[10, 16, 22, 14, 26, 18, 10, 24, 28, 16, 12, 22, 18, 10, 20, 26, 14, 10, 18, 12];

    return Container(
      key: Key('attachment_audio_${widget.attachment.id}'),
      width: 236,
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: mine ? Colors.black.withValues(alpha: 0.16) : c.surfaceHover,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: IconButton(
              key: const Key('audio_play_pause_button'),
              tooltip: _isPlaying ? 'Pause voice message' : 'Play voice message',
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(backgroundColor: accent, foregroundColor: onAccent),
              icon: _isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: onAccent),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: Key(_isPlaying ? 'audio_playing_icon' : 'audio_paused_icon'),
                      size: 26,
                    ),
              onPressed: _isLoading ? null : _togglePlayback,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final h in heights)
                    AnimatedContainer(
                      duration: AppDurations.fast,
                      width: 3,
                      height: _isPlaying ? h : h * 0.7,
                      decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(2)),
                    ),
                ],
              ),
            ),
          ),
          if (duration != null) ...[
            const SizedBox(width: 10),
            Text(
              _AttachmentBubbleContent._formatDuration(duration),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: mine ? c.bubbleOutgoingMeta : c.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Delivery status
// ---------------------------------------------------------------------------

/// The delivery state of one of your own messages. Each state has its own
/// icon *and* meaning - sent (one check), delivered (two checks), read (two
/// checks in green plus the word "Read"), failed (red alert plus text) - so it
/// is never distinguished by colour alone.
class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.message,
    required this.onRetry,
    required this.onSendTimeout,
    required this.metaColor,
    required this.onSurface,
  });

  final Message message;
  final VoidCallback onRetry;
  final VoidCallback onSendTimeout;
  final Color metaColor;
  final bool onSurface;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    switch (message.sendState) {
      case SendState.sending:
        return Semantics(
          label: 'Sending',
          child: _SendingIndicator(onTimeout: onSendTimeout, color: metaColor),
        );
      case SendState.failed:
        return Semantics(
          button: true,
          label: 'Failed to send, tap to retry',
          child: InkWell(
            key: const Key('status_failed'),
            onTap: onRetry,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_rounded, size: 14, color: onSurface ? c.error : const Color(0xFFFFB4AE)),
                  const SizedBox(width: 3),
                  Text(
                    'Failed, tap to retry',
                    style: TextStyle(
                      color: onSurface ? c.error : const Color(0xFFFFB4AE),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case SendState.confirmed:
        final isRead = message.status == MessageStatus.read;
        final readTone = onSurface ? c.success : const Color(0xFF9BE8BE);
        final color = isRead ? readTone : metaColor;
        return Semantics(
          label: switch (message.status) {
            MessageStatus.sent => 'Sent',
            MessageStatus.delivered => 'Delivered',
            MessageStatus.read => 'Read',
          },
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: AppDurations.fast,
                child: Icon(
                  message.status == MessageStatus.sent ? Icons.check_rounded : Icons.done_all_rounded,
                  key: Key('status_${message.status.name}'),
                  size: 15,
                  color: color,
                ),
              ),
              // Read is otherwise visually close to delivered (same double
              // check) - the green tone plus this label is what makes it
              // unambiguous, without a new row or a large banner.
              if (isRead) ...[
                const SizedBox(width: 3),
                Text(
                  'Read',
                  key: const Key('status_read_label'),
                  style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
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
  const _SendingIndicator({required this.onTimeout, required this.color});

  final VoidCallback onTimeout;
  final Color color;

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
    return SizedBox(
      key: const Key('status_sending'),
      width: 11,
      height: 11,
      child: CircularProgressIndicator(strokeWidth: 1.6, color: widget.color),
    );
  }
}
