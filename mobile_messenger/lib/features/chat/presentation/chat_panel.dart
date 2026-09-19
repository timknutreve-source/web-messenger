import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/error_presenter.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../chat_providers.dart';
import '../chat_room_providers.dart';
import '../chat_search_providers.dart';
import '../domain/attachment.dart';
import '../domain/chat_summary.dart';
import '../domain/message.dart';
import '../domain/pending_attachment.dart';
import 'message_bubble.dart';
import 'poll_widgets.dart';
import 'widgets/chat_avatar.dart';
import 'widgets/chat_search_bar.dart';

/// One conversation's content: message history, search bar, composer (text
/// and/or an image, video or voice attachment; polls in a group), typing
/// indicator, and per-message status/edit/delete.
///
/// It is a plain widget with no page chrome of its own, so the same panel is
/// a full page on a phone (see `ChatScreen`) and one of up to two panels
/// side by side on a wide web layout. [header] is shown above the messages
/// when given (the wide layout passes its own; a page uses an app bar).
class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({super.key, required this.chatId, this.header});

  final String chatId;
  final Widget? header;

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _controller = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_maybeLoadOlder);
  }

  @override
  void dispose() {
    // No explicit stopTyping()/disconnect() here: chatRoomControllerProvider
    // is autoDispose, so once this panel (its only watcher) is gone, the
    // provider's own ref.onDispose tears down typing state and the socket.
    _itemPositionsListener.itemPositions.removeListener(_maybeLoadOlder);
    _controller.dispose();
    super.dispose();
  }

  ChatRoomController get _room => ref.read(chatRoomControllerProvider(widget.chatId).notifier);

  /// The list is reversed (index 0 = newest, shown at the bottom), so older
  /// history is at the high indexes: load more when the top nears the end.
  void _maybeLoadOlder() {
    final room = ref.read(chatRoomControllerProvider(widget.chatId)).value;
    final positions = _itemPositionsListener.itemPositions.value;
    if (room == null || positions.isEmpty) return;
    final highest = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    if (highest >= room.messages.length - 3) _room.loadOlder();
  }

  void _send() {
    final text = _controller.text;
    final room = ref.read(chatRoomControllerProvider(widget.chatId)).value;
    final pending = room?.pendingAttachment;
    // Blocked while an attachment is uploading or failed - the composer's
    // send button is already disabled in that state, this is just a guard.
    if (pending != null && pending.state != PendingAttachmentState.uploaded) return;
    if (text.trim().isEmpty && pending?.uploaded == null) return;

    _room.send(text);
    _controller.clear();
    _scrollToNewest();
  }

  void _scrollToNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _itemScrollController.isAttached) _itemScrollController.jumpTo(index: 0);
    });
  }

  /// Keeps the view where it was when a message arrives while the user is
  /// scrolled up reading history: a new item is inserted at index 0, so every
  /// index shifts by one and, uncorrected, the content would jump.
  void _keepPositionOnNewMessage(AsyncValue<ChatRoomState>? previous, AsyncValue<ChatRoomState> next) {
    final before = previous?.value?.messages;
    final after = next.value?.messages;
    if (before == null || after == null || before.isEmpty || after.isEmpty) return;
    final added = after.length - before.length;
    if (added <= 0 || after.last.id == before.last.id) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final newestVisible = positions.reduce((a, b) => a.index < b.index ? a : b);
    if (newestVisible.index == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached) return;
      _itemScrollController.jumpTo(index: newestVisible.index + added, alignment: newestVisible.itemLeadingEdge);
    });
  }

  /// Brings a search result into view, loading older history first if the
  /// message is further back than what is loaded.
  Future<void> _jumpToMessage(Message message) async {
    final loaded = await _room.ensureMessageLoaded(message.id);
    if (!loaded || !mounted) return;
    final messages = ref.read(chatRoomControllerProvider(widget.chatId)).value?.messages;
    if (messages == null) return;
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index < 0 || !_itemScrollController.isAttached) return;
    await _itemScrollController.scrollTo(
      index: messages.length - 1 - index,
      alignment: 0.4,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showAttachmentPicker() async {
    final notifier = _room;
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

  Future<void> _createPoll() async {
    final poll = await CreatePollDialog.show(context);
    if (poll == null || !mounted) return;
    try {
      await _room.createPoll(question: poll.question, options: poll.options, anonymous: poll.anonymous);
      _scrollToNewest();
    } catch (e) {
      _showError(presentError(e).message);
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _showError(presentError(e).message);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        key: const Key('chat_action_error_snackbar'),
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// A highly visible, panel-level failure notice - deliberately separate
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
    final chatId = widget.chatId;
    ref.listen(chatRoomControllerProvider(chatId), (previous, next) {
      _notifyIfNewlyFailed(previous, next);
      _keepPositionOnNewMessage(previous, next);
    });
    ref.listen(chatSearchControllerProvider(chatId), (previous, next) {
      final current = next.current;
      if (current == null) return;
      final changed = previous == null ||
          previous.current?.id != current.id ||
          previous.currentIndex != next.currentIndex ||
          previous.results != next.results;
      if (changed) _jumpToMessage(current);
    });
    final roomState = ref.watch(chatRoomControllerProvider(chatId));
    final search = ref.watch(chatSearchControllerProvider(chatId));
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;
    final myUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final summary = ref.watch(chatSummaryProvider(chatId));
    final isGroup = summary?.isGroup ?? false;

    return Column(
      key: Key('chat_panel_$chatId'),
      children: [
        ?widget.header,
        if (search.active) ChatSearchBar(chatId: chatId),
        Expanded(
          child: roomState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _ErrorView(
              message: error is AppException ? error.message : 'Something went wrong. Please try again.',
              onRetry: () => ref.invalidate(chatRoomControllerProvider(chatId)),
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
                      : ScrollablePositionedList.builder(
                          key: const Key('message_list'),
                          reverse: true,
                          itemScrollController: _itemScrollController,
                          itemPositionsListener: _itemPositionsListener,
                          padding: const EdgeInsets.all(12),
                          itemCount: room.messages.length,
                          itemBuilder: (context, index) {
                            final message = room.messages[room.messages.length - 1 - index];
                            final current = search.current;
                            return MessageBubble(
                              key: ValueKey('bubble_${message.id}'),
                              message: message,
                              isMine: myUserId != null && message.sender.id == myUserId,
                              token: token,
                              highlight: search.active && search.hasQuery ? search.query : null,
                              isCurrentMatch: current != null && current.id == message.id,
                              onRetry: () => _room.retry(message.id),
                              onEdit: (content) => _runAction(() => _room.edit(message.id, content)),
                              onDelete: () => _runAction(() => _room.delete(message.id)),
                              onSendTimeout: () => _room.forceFailIfStillSending(message.id),
                              onVote: (poll, optionId) => _runAction(() => _room.votePoll(poll, optionId)),
                              onRetractVote: (poll) => _runAction(() => _room.retractPollVote(poll)),
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
                    onRemove: () => _room.removePendingAttachment(),
                    onRetry: () => _room.retryPendingAttachmentUpload(),
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
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: room.isRecordingAudio
                        ? _RecordingRow(
                            seconds: room.recordingSeconds,
                            onCancel: () => _room.cancelRecordingAudio(),
                            onStop: () => _room.stopRecordingAudioAndSend(),
                          )
                        : Row(
                            children: [
                              IconButton(
                                key: const Key('attach_button'),
                                tooltip: 'Attach photo or video',
                                icon: const Icon(Icons.add_photo_alternate_outlined),
                                onPressed: room.pendingAttachment != null ? null : _showAttachmentPicker,
                              ),
                              IconButton(
                                key: const Key('record_audio_button'),
                                tooltip: 'Record voice message',
                                icon: const Icon(Icons.mic_none_outlined),
                                onPressed: room.pendingAttachment != null ? null : () => _room.startRecordingAudio(),
                              ),
                              if (isGroup)
                                IconButton(
                                  key: const Key('create_poll_button'),
                                  tooltip: 'Create poll',
                                  icon: const Icon(Icons.poll_outlined),
                                  onPressed: _createPoll,
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
                                  onChanged: (text) => _room.onComposerChanged(text),
                                  onSubmitted: (_) => _send(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                key: const Key('send_button'),
                                tooltip: 'Send message',
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
        ),
      ],
    );
  }
}

/// The chat's summary from the chat list (its name, whether it is a group),
/// or null while the list hasn't loaded or the chat isn't in it (archived).
final chatSummaryProvider = Provider.autoDispose.family<ChatSummary?, String>((ref, chatId) {
  final chats = ref.watch(chatsControllerProvider).value;
  if (chats == null) return null;
  for (final chat in chats) {
    if (chat.id == chatId) return chat;
  }
  return null;
});

/// The header of a chat when it is shown as a panel of the wide layout:
/// avatar, name, member count / typing, and the search, info and close actions.
class ChatPanelHeader extends ConsumerWidget {
  const ChatPanelHeader({
    super.key,
    required this.chatId,
    this.onInfo,
    this.infoActive = false,
    this.onClose,
  });

  final String chatId;
  final VoidCallback? onInfo;
  final bool infoActive;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(chatSummaryProvider(chatId));
    final token = ref.watch(authControllerProvider).value is AuthAuthenticated
        ? (ref.watch(authControllerProvider).value as AuthAuthenticated).token
        : null;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        key: Key('chat_panel_header_$chatId'),
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        child: Row(
          children: [
            if (summary != null) ChatAvatar(chat: summary, token: token, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary?.title ?? 'Chat',
                    key: Key('chat_panel_title_$chatId'),
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (summary != null && summary.isGroup)
                    Text(
                      summary.memberCount == 1 ? '1 member' : '${summary.memberCount} members',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            ...chatHeaderActions(ref, chatId, onInfo: onInfo, infoActive: infoActive),
            if (onClose != null)
              IconButton(
                key: Key('close_chat_panel_$chatId'),
                tooltip: 'Close chat',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}

/// The search and info buttons every chat header carries (page app bar and
/// panel header alike).
List<Widget> chatHeaderActions(WidgetRef ref, String chatId, {VoidCallback? onInfo, bool infoActive = false}) {
  final search = ref.watch(chatSearchControllerProvider(chatId));
  return [
    IconButton(
      key: const Key('chat_search_button'),
      tooltip: search.active ? 'Close search' : 'Search in chat',
      isSelected: search.active,
      icon: Icon(search.active ? Icons.search_off : Icons.search),
      onPressed: () {
        final controller = ref.read(chatSearchControllerProvider(chatId).notifier);
        search.active ? controller.close() : controller.open();
      },
    ),
    if (onInfo != null)
      IconButton(
        key: const Key('chat_info_button'),
        tooltip: 'Chat info',
        isSelected: infoActive,
        icon: const Icon(Icons.info_outline),
        onPressed: onInfo,
      ),
  ];
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
          tooltip: 'Discard recording',
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
          tooltip: 'Stop recording',
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
              AttachmentKind.image => _PendingImageThumbnail(file: pending.file),
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
            tooltip: 'Remove attachment',
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

/// A 56x56 preview of a picked (not yet sent) image. Reads the picked file's
/// bytes rather than using `Image.file`, since on the web a picked file has
/// no path on disk - only in-memory bytes.
class _PendingImageThumbnail extends StatefulWidget {
  const _PendingImageThumbnail({required this.file});

  final XFile file;

  @override
  State<_PendingImageThumbnail> createState() => _PendingImageThumbnailState();
}

class _PendingImageThumbnailState extends State<_PendingImageThumbnail> {
  late final Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox(width: 56, height: 56);
        return Image.memory(
          data,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const SizedBox(width: 56, height: 56, child: Icon(Icons.broken_image_outlined)),
        );
      },
    );
  }
}
