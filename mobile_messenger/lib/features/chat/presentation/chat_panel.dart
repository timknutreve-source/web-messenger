import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/error_presenter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_states.dart';
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
import 'widgets/typing_dots.dart';

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

  /// True while the newest messages are scrolled out of view - shows the
  /// "jump to latest" button.
  final _scrolledAway = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_maybeLoadOlder);
    _itemPositionsListener.itemPositions.addListener(_updateScrolledAway);
  }

  @override
  void dispose() {
    // No explicit stopTyping()/disconnect() here: chatRoomControllerProvider
    // is autoDispose, so once this panel (its only watcher) is gone, the
    // provider's own ref.onDispose tears down typing state and the socket.
    _itemPositionsListener.itemPositions.removeListener(_maybeLoadOlder);
    _itemPositionsListener.itemPositions.removeListener(_updateScrolledAway);
    _scrolledAway.dispose();
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

  void _updateScrolledAway() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final newest = positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    _scrolledAway.value = newest > 1;
  }

  void _jumpToLatest() {
    if (!_itemScrollController.isAttached) return;
    _itemScrollController.scrollTo(index: 0, duration: AppDurations.medium, curve: AppDurations.standard);
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
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final c = context.colors;
        Widget option({
          required Key key,
          required IconData icon,
          required Color tone,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) =>
            ListTile(
              key: key,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: c.isDark ? 0.16 : 0.14),
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(icon, color: tone),
              ),
              title: Text(title),
              subtitle: Text(subtitle),
              onTap: () {
                Navigator.pop(context);
                onTap();
              },
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Attach', style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
                option(
                  key: const Key('pick_image_gallery_action'),
                  icon: Icons.photo_library_rounded,
                  tone: c.accentGreen,
                  title: 'Photo from gallery',
                  subtitle: 'Choose an existing picture',
                  onTap: () => notifier.pickImage(ImageSource.gallery),
                ),
                option(
                  key: const Key('pick_image_camera_action'),
                  icon: Icons.photo_camera_rounded,
                  tone: c.primary,
                  title: 'Take photo',
                  subtitle: 'Use the camera',
                  onTap: () => notifier.pickImage(ImageSource.camera),
                ),
                option(
                  key: const Key('pick_video_gallery_action'),
                  icon: Icons.video_library_rounded,
                  tone: c.accentGreen,
                  title: 'Video from gallery',
                  subtitle: 'Choose an existing video',
                  onTap: () => notifier.pickVideo(ImageSource.gallery),
                ),
                option(
                  key: const Key('pick_video_camera_action'),
                  icon: Icons.videocam_rounded,
                  tone: c.primary,
                  title: 'Record video',
                  subtitle: 'Use the camera',
                  onTap: () => notifier.pickVideo(ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
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

  static const _groupGap = Duration(minutes: 5);

  static bool _sameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  static String _dayLabel(DateTime when) {
    final day = when.toLocal();
    final now = DateTime.now();
    if (_sameDay(day, now)) return 'Today';
    if (_sameDay(day, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final label = '${day.day} ${months[day.month - 1]}';
    return day.year == now.year ? label : '$label ${day.year}';
  }

  /// Two consecutive messages belong to one visual run when the same person
  /// sent both, on the same day, a few minutes apart.
  static bool _sameRun(Message a, Message b) =>
      a.sender.id == b.sender.id &&
      _sameDay(a.createdAt, b.createdAt) &&
      b.createdAt.difference(a.createdAt).abs() < _groupGap;

  /// Enter sends, Shift+Enter inserts a line break - the desktop convention.
  /// Ignored while an IME composition is active (Enter then confirms the
  /// composed text) and on soft keyboards, where Enter stays a line break.
  KeyEventResult _onComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter || HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    final composing = _controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
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
    final c = context.colors;

    return Container(
      color: c.background,
      child: Column(
        key: Key('chat_panel_$chatId'),
        children: [
          ?widget.header,
          if (search.active) ChatSearchBar(chatId: chatId),
          Expanded(
            child: roomState.when(
              loading: () => const MessagesSkeleton(),
              error: (error, stackTrace) => AppErrorState(
                message: error is AppException ? error.message : 'Something went wrong. Please try again.',
                onRetry: () => ref.invalidate(chatRoomControllerProvider(chatId)),
              ),
              data: (room) => Column(
                children: [
                  SizedBox(
                    height: 2,
                    child: room.loadingOlder
                        ? LinearProgressIndicator(
                            key: const Key('loading_older_indicator'),
                            minHeight: 2,
                            backgroundColor: Colors.transparent,
                            color: c.primary,
                          )
                        : null,
                  ),
                  Expanded(
                    child: room.messages.isEmpty
                        ? AppEmptyState(
                            key: const Key('messages_empty_view'),
                            icon: Icons.waving_hand_rounded,
                            title: 'No messages yet. Say hello!',
                            message: 'Your conversation starts with the first message.',
                          )
                        : Stack(
                            children: [
                              ScrollablePositionedList.builder(
                                key: const Key('message_list'),
                                reverse: true,
                                itemScrollController: _itemScrollController,
                                itemPositionsListener: _itemPositionsListener,
                                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
                                itemCount: room.messages.length,
                                itemBuilder: (context, index) {
                                  final position = room.messages.length - 1 - index;
                                  final message = room.messages[position];
                                  final older = position > 0 ? room.messages[position - 1] : null;
                                  final newer = position < room.messages.length - 1 ? room.messages[position + 1] : null;
                                  final current = search.current;
                                  final startsDay = older == null || !_sameDay(older.createdAt, message.createdAt);
                                  return MessageBubble(
                                    key: ValueKey('bubble_${message.id}'),
                                    message: message,
                                    isMine: myUserId != null && message.sender.id == myUserId,
                                    token: token,
                                    highlight: search.active && search.hasQuery ? search.query : null,
                                    isCurrentMatch: current != null && current.id == message.id,
                                    isGroup: isGroup,
                                    isFirstInGroup: older == null || startsDay || !_sameRun(older, message),
                                    isLastInGroup: newer == null || !_sameRun(message, newer),
                                    dayLabel: startsDay ? _dayLabel(message.createdAt) : null,
                                    onRetry: () => _room.retry(message.id),
                                    onEdit: (content) => _runAction(() => _room.edit(message.id, content)),
                                    onDelete: () => _runAction(() => _room.delete(message.id)),
                                    onSendTimeout: () => _room.forceFailIfStillSending(message.id),
                                    onVote: (poll, optionId) => _runAction(() => _room.votePoll(poll, optionId)),
                                    onRetractVote: (poll) => _runAction(() => _room.retractPollVote(poll)),
                                  );
                                },
                              ),
                              Positioned(
                                right: AppSpacing.lg,
                                bottom: AppSpacing.sm,
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _scrolledAway,
                                  builder: (context, away, _) => AnimatedSwitcher(
                                    duration: AppDurations.fast,
                                    transitionBuilder: (child, animation) => FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(animation), child: child),
                                    ),
                                    child: away
                                        ? _JumpToLatestButton(key: const Key('jump_to_latest_button'), onPressed: _jumpToLatest)
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ],
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
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xs),
                      child: Row(
                        children: [
                          Icon(Icons.mic_off_rounded, size: 16, color: c.error),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              room.audioRecordingError!,
                              key: const Key('audio_recording_error'),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
                      child: _Composer(
                        child: room.isRecordingAudio
                            ? _RecordingRow(
                                seconds: room.recordingSeconds,
                                onCancel: () => _room.cancelRecordingAudio(),
                                onStop: () => _room.stopRecordingAudioAndSend(),
                              )
                            : _composerRow(context, room, isGroup),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composerRow(BuildContext context, ChatRoomState room, bool isGroup) {
    final c = context.colors;
    final pending = room.pendingAttachment;
    final sendBlocked = pending != null && pending.state != PendingAttachmentState.uploaded;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _ComposerIconButton(
          key: const Key('attach_button'),
          tooltip: 'Attach photo or video',
          icon: Icons.add_photo_alternate_rounded,
          onPressed: pending != null ? null : _showAttachmentPicker,
        ),
        _ComposerIconButton(
          key: const Key('record_audio_button'),
          tooltip: 'Record voice message',
          icon: Icons.mic_rounded,
          onPressed: pending != null ? null : () => _room.startRecordingAudio(),
        ),
        if (isGroup)
          _ComposerIconButton(
            key: const Key('create_poll_button'),
            tooltip: 'Create poll',
            icon: Icons.poll_rounded,
            onPressed: _createPoll,
          ),
        Expanded(
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: _onComposerKey,
            child: TextField(
              key: const Key('message_input'),
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Message',
                hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.textMuted),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 12),
              ),
              onChanged: (text) => _room.onComposerChanged(text),
              onSubmitted: (_) => _send(),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final hasContent = _controller.text.trim().isNotEmpty || pending?.uploaded != null;
            return IconButton.filled(
              key: const Key('send_button'),
              tooltip: 'Send message',
              icon: const Icon(Icons.arrow_upward_rounded),
              onPressed: sendBlocked ? null : _send,
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                shape: const CircleBorder(),
                backgroundColor: hasContent ? c.primary : c.surfaceHover,
                foregroundColor: hasContent ? c.textOnPrimary : c.textMuted,
                disabledBackgroundColor: c.surfaceHover,
                disabledForegroundColor: c.textMuted.withValues(alpha: 0.6),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The floating, rounded composer surface: a soft elevated pill that lifts
/// and gains a gold edge while the field has focus.
class _Composer extends StatelessWidget {
  const _Composer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppDurations.standard,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
            decoration: BoxDecoration(
              color: c.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: focused ? c.primary.withValues(alpha: 0.7) : c.border),
              boxShadow: AppShadows.card(c),
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({super.key, required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: const CircleBorder(),
      ),
    );
  }
}

class _JumpToLatestButton extends StatelessWidget {
  const _JumpToLatestButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Jump to latest message',
      child: Tooltip(
        message: 'Jump to latest',
        child: Material(
          color: c.surfaceElevated,
          shape: CircleBorder(side: BorderSide(color: c.border)),
          elevation: 6,
          shadowColor: Colors.black54,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.keyboard_arrow_down_rounded, color: c.primary, size: 26),
            ),
          ),
        ),
      ),
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

/// Who and what a chat header shows: avatar, name and a live subtitle - the
/// typing cue while someone is typing, the member count for a group. Shared by
/// the page app bar and the wide layout's panel header.
class ChatHeaderTitle extends ConsumerWidget {
  const ChatHeaderTitle({super.key, required this.chatId, this.fallbackTitle, this.titleKey, this.avatarRadius = 20});

  final String chatId;
  final String? fallbackTitle;
  final Key? titleKey;
  final double avatarRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(chatSummaryProvider(chatId));
    final auth = ref.watch(authControllerProvider).value;
    final token = auth is AuthAuthenticated ? auth.token : null;
    final typing = ref.watch(chatRoomControllerProvider(chatId).select((s) => s.value?.typingUsername));
    final theme = Theme.of(context);
    final c = context.colors;

    Widget? subtitle;
    if (typing != null) {
      subtitle = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TypingDots(color: c.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$typing is typing...',
              key: const Key('typing_indicator'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: c.primary, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
    } else if (summary != null && summary.isGroup) {
      subtitle = Text(
        summary.memberCount == 1 ? '1 member' : '${summary.memberCount} members',
        style: theme.textTheme.bodySmall,
      );
    }

    return Row(
      children: [
        if (summary != null) ...[
          ChatAvatar(chat: summary, token: token, radius: avatarRadius),
          const SizedBox(width: AppSpacing.md),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary?.title ?? fallbackTitle ?? 'Chat',
                key: titleKey,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[const SizedBox(height: 1), subtitle],
            ],
          ),
        ),
      ],
    );
  }
}

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
    final c = context.colors;
    return Container(
      key: Key('chat_panel_header_$chatId'),
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      child: Row(
        children: [
          Expanded(child: ChatHeaderTitle(chatId: chatId, titleKey: Key('chat_panel_title_$chatId'))),
          const SizedBox(width: AppSpacing.sm),
          ...chatHeaderActions(context, ref, chatId, onInfo: onInfo, infoActive: infoActive),
          if (onClose != null)
            IconButton(
              key: Key('close_chat_panel_$chatId'),
              tooltip: 'Close chat',
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

/// The search and info buttons every chat header carries (page app bar and
/// panel header alike). A pressed toggle shows a gold wash *and* a different
/// icon, so the state never rests on colour alone.
List<Widget> chatHeaderActions(
  BuildContext context,
  WidgetRef ref,
  String chatId, {
  VoidCallback? onInfo,
  bool infoActive = false,
}) {
  final c = context.colors;
  final search = ref.watch(chatSearchControllerProvider(chatId));
  ButtonStyle toggleStyle(bool active) => IconButton.styleFrom(
        backgroundColor: active ? c.primarySoft : null,
        foregroundColor: active ? c.primary : c.textSecondary,
      );
  return [
    IconButton(
      key: const Key('chat_search_button'),
      tooltip: search.active ? 'Close search' : 'Search in chat',
      isSelected: search.active,
      icon: Icon(search.active ? Icons.search_off_rounded : Icons.search_rounded),
      style: toggleStyle(search.active),
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
        icon: Icon(infoActive ? Icons.info_rounded : Icons.info_outline_rounded),
        style: toggleStyle(infoActive),
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
    final c = context.colors;
    return Row(
      children: [
        IconButton(
          key: const Key('cancel_recording_button'),
          tooltip: 'Discard recording',
          icon: const Icon(Icons.delete_outline_rounded),
          style: IconButton.styleFrom(foregroundColor: c.error, shape: const CircleBorder()),
          onPressed: widget.onCancel,
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FadeTransition(
                opacity: _pulseController,
                child: Icon(Icons.fiber_manual_record_rounded, color: c.accentRed, size: 14),
              ),
              const SizedBox(width: AppSpacing.sm),
              Semantics(
                container: true,
                child: Text(
                  'Recording... ${_formatDuration(widget.seconds)}',
                  key: const Key('recording_indicator'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
            ],
          ),
        ),
        IconButton.filled(
          key: const Key('stop_recording_button'),
          tooltip: 'Stop recording',
          icon: const Icon(Icons.check_rounded),
          style: IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            shape: const CircleBorder(),
            backgroundColor: c.primary,
            foregroundColor: c.textOnPrimary,
          ),
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
    final c = context.colors;
    Widget tile(IconData icon) => Container(
          width: 56,
          height: 56,
          color: c.surfaceHover,
          child: Icon(icon, color: c.textSecondary),
        );
    return Container(
      key: const Key('pending_attachment_preview'),
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: pending.state == PendingAttachmentState.failed ? c.error.withValues(alpha: 0.5) : c.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadius.smAll,
            child: switch (pending.kind) {
              AttachmentKind.image => _PendingImageThumbnail(file: pending.file),
              AttachmentKind.video => tile(Icons.videocam_rounded),
              AttachmentKind.audio => tile(Icons.mic_rounded),
            },
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _statusContent(context, c)),
          IconButton(
            key: const Key('remove_pending_attachment_button'),
            tooltip: 'Remove attachment',
            icon: const Icon(Icons.close_rounded),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  Widget _statusContent(BuildContext context, AppColors c) {
    final style = Theme.of(context).textTheme.bodyMedium;
    switch (pending.state) {
      case PendingAttachmentState.uploading:
        return Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
            const SizedBox(width: AppSpacing.sm),
            Text('Uploading...', key: const Key('attachment_uploading_label'), style: style),
          ],
        );
      case PendingAttachmentState.uploaded:
        return Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.success, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text('Ready to send', key: const Key('attachment_uploaded_label'), style: style),
          ],
        );
      case PendingAttachmentState.failed:
        return Row(
          children: [
            Icon(Icons.error_rounded, color: c.error, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Upload failed',
                key: const Key('attachment_failed_label'),
                style: style?.copyWith(color: c.error),
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
