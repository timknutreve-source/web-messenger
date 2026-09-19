import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/dio_provider.dart';
import '../../core/network/no_auto_retry.dart';
import '../auth/auth_providers.dart';
import '../auth/domain/auth_state.dart';
import '../contact/domain/contact_user_summary.dart';
import '../group/group_providers.dart' show groupDetailsProvider;
import 'chat_providers.dart' show chatsControllerProvider, openChatRegistryProvider;
import 'data/attachment_api.dart';
import 'data/attachment_picker.dart';
import 'data/audio_recorder_service.dart';
import 'data/chat_audio_player.dart';
import 'data/chat_websocket_client.dart';
import 'data/message_api.dart';
import 'data/poll_api.dart';
import 'domain/attachment.dart';
import 'domain/chat_event.dart';
import 'domain/message.dart';
import 'domain/pending_attachment.dart';
import 'domain/poll.dart';

final messageApiProvider = Provider<MessageApi>((ref) => MessageApi(ref.watch(dioProvider)));
final pollApiProvider = Provider<PollApi>((ref) => PollApi(ref.watch(dioProvider)));
final attachmentApiProvider = Provider<AttachmentApi>((ref) => AttachmentApi(ref.watch(dioProvider)));
final attachmentPickerProvider = Provider<AttachmentPicker>((ref) => AttachmentPicker());

/// A factory (like [chatWebSocketClientFactoryProvider]) rather than a
/// shared instance, so each chat room's recorder is independent and
/// overridable with a fake in tests (no real microphone/platform channel).
final audioRecorderServiceProvider =
    Provider<AudioRecorderService Function()>((ref) => AudioRecorderService.new);

/// A factory rather than a shared instance, since each rendered voice-message
/// bubble owns its own playback state independently of any other. Overridable
/// with a fake in tests (no real audio decoding/platform channel).
final chatAudioPlayerFactoryProvider =
    Provider<ChatAudioPlayer Function()>((ref) => () => ChatAudioPlayer(ref.watch(dioProvider)));

/// A factory rather than a shared instance, since each chat room needs its
/// own [ChatWebSocketClient]. Overridable in tests to inject a fake.
final chatWebSocketClientFactoryProvider =
    Provider<ChatWebSocketClient Function()>((ref) => ChatWebSocketClient.new);

/// State for a single conversation screen: its messages (oldest-first,
/// including any not-yet-confirmed outgoing ones), whether an older page is
/// available, who (if anyone) is currently typing, and any image/video
/// picked for the message currently being composed.
class ChatRoomState {
  const ChatRoomState({
    required this.messages,
    required this.hasMoreOlder,
    this.typingUsername,
    this.loadingOlder = false,
    this.pendingAttachment,
    this.isRecordingAudio = false,
    this.recordingSeconds = 0,
    this.audioRecordingError,
  });

  final List<Message> messages;
  final bool hasMoreOlder;
  final String? typingUsername;
  final bool loadingOlder;
  final PendingAttachment? pendingAttachment;

  /// Whether a voice-message recording is currently in progress - drives
  /// the composer swapping to the "recording..." row (see `ChatScreen`).
  final bool isRecordingAudio;

  /// Elapsed recording time, ticked once per second while [isRecordingAudio].
  final int recordingSeconds;

  /// Set (briefly) when starting a recording fails - e.g. the microphone
  /// permission was denied - so the UI can show it instead of silently
  /// doing nothing.
  final String? audioRecordingError;

  ChatRoomState copyWith({
    List<Message>? messages,
    bool? hasMoreOlder,
    String? typingUsername,
    bool clearTyping = false,
    bool? loadingOlder,
    PendingAttachment? pendingAttachment,
    bool clearPendingAttachment = false,
    bool? isRecordingAudio,
    int? recordingSeconds,
    String? audioRecordingError,
    bool clearAudioRecordingError = false,
  }) =>
      ChatRoomState(
        messages: messages ?? this.messages,
        hasMoreOlder: hasMoreOlder ?? this.hasMoreOlder,
        typingUsername: clearTyping ? null : (typingUsername ?? this.typingUsername),
        loadingOlder: loadingOlder ?? this.loadingOlder,
        pendingAttachment: clearPendingAttachment ? null : (pendingAttachment ?? this.pendingAttachment),
        isRecordingAudio: isRecordingAudio ?? this.isRecordingAudio,
        recordingSeconds: recordingSeconds ?? this.recordingSeconds,
        audioRecordingError:
            clearAudioRecordingError ? null : (audioRecordingError ?? this.audioRecordingError),
      );
}

/// Owns one conversation's message history plus its live WebSocket
/// subscription (new/updated/deleted messages, status changes, typing).
/// Scoped per chat id and auto-disposed when nothing is watching it anymore
/// (i.e. leaving the chat screen), which is what tears down the socket.
class ChatRoomController extends AsyncNotifier<ChatRoomState> {
  ChatRoomController(this.chatId);

  final String chatId;

  // Not `late final`: AsyncNotifier.build() can legitimately run more than
  // once over this controller's lifetime (e.g. Riverpod's automatic retry
  // after a failed build), which would otherwise throw
  // LateInitializationError on the second attempt.
  late ChatWebSocketClient _webSocket;
  Timer? _typingClearTimer;
  Timer? _typingStopTimer;
  bool _sentTypingStarted = false;
  int _localIdCounter = 0;
  AudioRecorderService? _audioRecorder;
  Timer? _recordingTimer;

  @override
  Future<ChatRoomState> build() async {
    _webSocket = ref.read(chatWebSocketClientFactoryProvider)();
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('ChatRoomController used while not authenticated');
    }
    final token = authState.token;
    final openChats = ref.read(openChatRegistryProvider);
    openChats.opened(chatId);
    ref.onDispose(() {
      openChats.closed(chatId);
      _disconnect();
    });

    final page = await ref.read(messageApiProvider).loadMessages(token, chatId);
    _connect(token);
    unawaited(_markRead());
    // Catches up delivery acknowledgment for messages that arrived while this
    // recipient's app wasn't connected to receive the live NEW_MESSAGE event
    // that normally triggers it (see `ChatsController._handleEvent`) - e.g.
    // sent while offline, only ever seen once the chat is opened later.
    unawaited(_acknowledgeDelivery(page.messages, authState.user.id, token));
    return ChatRoomState(messages: page.messages, hasMoreOlder: page.hasMore);
  }

  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null || !current.hasMoreOlder || current.loadingOlder || current.messages.isEmpty) {
      return;
    }
    state = AsyncData(current.copyWith(loadingOlder: true));
    try {
      final token = await _requireToken();
      final oldestId = current.messages.first.id;
      final page = await ref.read(messageApiProvider).loadMessages(token, chatId, before: oldestId);
      final merged = state.value;
      if (merged == null) return;
      state = AsyncData(merged.copyWith(
        messages: [...page.messages, ...merged.messages],
        hasMoreOlder: page.hasMore,
        loadingOlder: false,
      ));
    } catch (_) {
      final current2 = state.value;
      if (current2 != null) {
        state = AsyncData(current2.copyWith(loadingOlder: false));
      }
    }
  }

  /// Loads older pages until the message [messageId] is in the list (used to
  /// jump to a search result that is further back than what is loaded).
  /// Returns whether the message is now present.
  Future<bool> ensureMessageLoaded(String messageId) async {
    while (true) {
      final current = state.value;
      if (current == null) return false;
      if (current.messages.any((m) => m.id == messageId)) return true;
      if (!current.hasMoreOlder) return false;
      if (current.loadingOlder) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      final before = current.messages.length;
      await loadOlder();
      if ((state.value?.messages.length ?? before) == before) return false; // load failed - give up
    }
  }

  // ---- polls ----

  Future<void> createPoll({
    required String question,
    required List<String> options,
    required bool anonymous,
  }) async {
    final token = await _requireToken();
    final message = await ref
        .read(pollApiProvider)
        .createPoll(token, chatId, question: question, options: options, anonymous: anonymous);
    _appendOrReplace(message, matchLocalId: null);
  }

  Future<void> votePoll(Poll poll, String optionId) async {
    final token = await _requireToken();
    final updated = await ref.read(pollApiProvider).vote(token, chatId, poll.id, optionId);
    _updateMessage(poll.messageId, (m) => m.copyWith(poll: updated));
  }

  Future<void> retractPollVote(Poll poll) async {
    final token = await _requireToken();
    final updated = await ref.read(pollApiProvider).retractVote(token, chatId, poll.id);
    _updateMessage(poll.messageId, (m) => m.copyWith(poll: updated));
  }

  /// A poll's own vote state is personal to each viewer, so the broadcast
  /// only says *that* it changed; refetch to get this user's view of it.
  Future<void> _refreshPoll(String pollId, String messageId) async {
    try {
      final token = await _requireToken();
      final poll = await ref.read(pollApiProvider).getPoll(token, chatId, pollId);
      _updateMessage(messageId, (m) => m.copyWith(poll: poll));
    } catch (_) {
      // Best-effort - the next reload of the chat picks up the latest tally.
    }
  }

  // ---- attachments ----

  Future<void> pickImage(ImageSource source) async {
    final file = await ref.read(attachmentPickerProvider).pickImage(source);
    if (file == null) return;
    await _startAttachmentUpload(file, AttachmentKind.image);
  }

  Future<void> pickVideo(ImageSource source) async {
    final file = await ref.read(attachmentPickerProvider).pickVideo(source);
    if (file == null) return;
    await _startAttachmentUpload(file, AttachmentKind.video);
  }

  void removePendingAttachment() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(clearPendingAttachment: true));
  }

  Future<void> retryPendingAttachmentUpload() async {
    final pending = state.value?.pendingAttachment;
    if (pending == null || pending.state != PendingAttachmentState.failed) return;
    await _startAttachmentUpload(pending.file, pending.kind);
  }

  Future<void> _startAttachmentUpload(XFile file, AttachmentKind kind, {int? durationSeconds}) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      pendingAttachment: PendingAttachment(file: file, kind: kind, state: PendingAttachmentState.uploading),
    ));
    try {
      final token = await _requireToken();
      final uploaded = await ref
          .read(attachmentApiProvider)
          .upload(token, chatId, file, durationSeconds: durationSeconds);
      _updatePendingAttachment(
        (p) => p.copyWith(state: PendingAttachmentState.uploaded, uploaded: uploaded),
      );
    } catch (e) {
      _updatePendingAttachment((p) => p.copyWith(state: PendingAttachmentState.failed, error: e));
    }
  }

  // ---- voice messages ----

  /// Requests the microphone permission (if needed) and starts recording.
  /// On denial, [ChatRoomState.audioRecordingError] is set instead of
  /// silently doing nothing, so the UI has something real to show the user.
  Future<void> startRecordingAudio() async {
    final current = state.value;
    if (current == null || current.isRecordingAudio) return;

    final recorder = ref.read(audioRecorderServiceProvider)();
    _audioRecorder = recorder;
    final granted = await recorder.hasPermission();
    if (!granted) {
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(
          audioRecordingError: 'Microphone permission is required to record a voice message.',
        ));
      }
      _audioRecorder = null;
      return;
    }

    await recorder.start();
    final latest = state.value;
    if (latest == null) return;
    state = AsyncData(latest.copyWith(
      isRecordingAudio: true,
      recordingSeconds: 0,
      clearAudioRecordingError: true,
    ));
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final c = state.value;
      if (c == null) return;
      state = AsyncData(c.copyWith(recordingSeconds: c.recordingSeconds + 1));
    });
  }

  /// Stops recording and uploads the result as a pending attachment, exactly
  /// like an image/video pick - the same upload/retry/remove machinery
  /// already handles it from here on.
  Future<void> stopRecordingAudioAndSend() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final recorder = _audioRecorder;
    _audioRecorder = null;
    final current = state.value;
    if (recorder == null || current == null) return;

    final durationSeconds = current.recordingSeconds;
    final file = await recorder.stop();
    final latest = state.value;
    if (latest != null) {
      state = AsyncData(latest.copyWith(isRecordingAudio: false));
    }
    if (file == null) return;
    await _startAttachmentUpload(file, AttachmentKind.audio, durationSeconds: durationSeconds);
  }

  /// Stops recording and discards it - no upload, no pending attachment.
  Future<void> cancelRecordingAudio() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final recorder = _audioRecorder;
    _audioRecorder = null;
    if (recorder != null) {
      await recorder.cancel();
    }
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(isRecordingAudio: false, recordingSeconds: 0));
    }
  }

  void _updatePendingAttachment(PendingAttachment Function(PendingAttachment) update) {
    final current = state.value;
    final pending = current?.pendingAttachment;
    if (current == null || pending == null) return;
    state = AsyncData(current.copyWith(pendingAttachment: update(pending)));
  }

  // ---- sending ----

  Future<void> send(String content) async {
    final trimmed = content.trim();
    final pendingAttachment = state.value?.pendingAttachment;

    // Never send while an attachment is mid-upload or has failed to upload -
    // that would either reference an attachment id that doesn't exist yet
    // or silently drop the picked media.
    if (pendingAttachment != null && pendingAttachment.state != PendingAttachmentState.uploaded) {
      return;
    }
    final uploadedAttachment = pendingAttachment?.uploaded;
    if (trimmed.isEmpty && uploadedAttachment == null) return;

    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) return;

    final localId = 'local-${_localIdCounter++}';
    final attachments = uploadedAttachment == null ? const <Attachment>[] : [uploadedAttachment];
    final pending = Message(
      id: localId,
      conversationId: chatId,
      sender: ContactUserSummary(
        id: authState.user.id,
        username: authState.user.username,
        email: authState.user.email,
        avatarFileName: authState.user.avatarFileName,
      ),
      content: trimmed,
      status: MessageStatus.sent,
      createdAt: DateTime.now().toUtc(),
      deleted: false,
      sendState: SendState.sending,
      attachments: attachments,
    );
    debugPrint('[ChatRoomController] OPTIMISTIC MESSAGE CREATED localId=$localId chatId=$chatId');
    _appendOrReplace(pending, matchLocalId: null);
    removePendingAttachment();
    stopTyping();

    await _submit(localId, trimmed.isEmpty ? null : trimmed, attachments.map((a) => a.id).toList());
  }

  Future<void> retry(String localId) async {
    final current = state.value;
    if (current == null) return;
    Message? failed;
    for (final m in current.messages) {
      if (m.id == localId) {
        failed = m;
        break;
      }
    }
    if (failed == null) return;
    final hasContent = failed.content != null && failed.content!.isNotEmpty;
    if (!hasContent && failed.attachments.isEmpty) return;

    _updateMessage(localId, (m) => m.copyWith(sendState: SendState.sending));
    await _submit(
      localId,
      hasContent ? failed.content : null,
      failed.attachments.map((a) => a.id).toList(),
    );
  }

  /// Called from the message bubble's own widget-layer ticker (see
  /// `_SendingIndicator` in chat_screen.dart) - deliberately a completely
  /// different mechanism from the `dart:async` `Timer`-based watchdog in
  /// `_submit()` below. That watchdog and the adapter-level hard timeout
  /// were both verified correct in tests, using patterns already proven to
  /// work elsewhere in this exact class (the voice-recording countdown), yet
  /// real-device testing kept showing a message stuck in "sending"
  /// indefinitely with no failure ever surfacing. Since the spinner itself
  /// visibly animates in that stuck state, Flutter's rendering/ticker
  /// pipeline is demonstrably alive on the device even when something about
  /// `dart:async` Timers scheduled from within this notifier apparently is
  /// not firing (or a repeated WebSocket reconnect loop is starving
  /// whatever resource they depend on) - so this hooks the same guarantee
  /// into the one thing already proven to run: the frame ticker driving
  /// that very spinner. Idempotent and safe to call repeatedly.
  void forceFailIfStillSending(String localId) {
    final current = state.value;
    if (current == null) return;
    final stillSending = current.messages.any((m) => m.id == localId && m.sendState == SendState.sending);
    if (stillSending) {
      debugPrint('[ChatRoomController] TICKER WATCHDOG FORCING FAILED localId=$localId');
      _updateMessage(localId, (m) => m.copyWith(sendState: SendState.failed));
    }
  }

  /// Absolute upper bound on how long a message may show "sending" before
  /// the user gets feedback either way.
  static const _sendHardTimeout = Duration(seconds: 5);

  Future<void> _submit(String localId, String? content, List<String> attachmentIds) async {
    debugPrint('[ChatRoomController] SEND START localId=$localId chatId=$chatId');

    // An independent watchdog, deliberately NOT implemented as
    // Future.timeout()/Future.any() racing the network call below: it does
    // not await, wrap, or otherwise depend on that Future's fate at all.
    // It fires unconditionally at _sendHardTimeout and, if this message is
    // still "sending" at that moment, forces it to "failed" directly by
    // mutating state - the exact same mechanism onRetry/onDelete already
    // use. This means there is no chain of awaits or nested timeouts that
    // a hang anywhere below (Dio, its adapter, the socket, the response
    // stream, a STOMP reconnect loop, anything) has to cooperate with for
    // the user to get feedback - only this Timer has to fire, which
    // depends on nothing but this app's own isolate still running.
    var watchdogFired = false;
    final watchdog = Timer(_sendHardTimeout, () {
      watchdogFired = true;
      debugPrint('[ChatRoomController] WATCHDOG FIRED localId=$localId');
      final current = state.value;
      if (current == null) return;
      final stillSending = current.messages.any((m) => m.id == localId && m.sendState == SendState.sending);
      if (stillSending) {
        debugPrint('[ChatRoomController] WATCHDOG FORCING FAILED localId=$localId');
        _updateMessage(localId, (m) => m.copyWith(sendState: SendState.failed));
      }
    });

    try {
      final token = await _requireToken();
      debugPrint('[ChatRoomController] HTTP REQUEST START localId=$localId');
      final sent = await ref
          .read(messageApiProvider)
          .sendMessage(token, chatId, content, attachmentIds: attachmentIds.isEmpty ? null : attachmentIds);
      watchdog.cancel();
      debugPrint('[ChatRoomController] HTTP REQUEST SUCCESS localId=$localId serverId=${sent.id}');
      // The watchdog may have already forced this message to "failed" if
      // the response arrived just past the deadline - a late success must
      // still win and correctly replace the placeholder either way.
      _appendOrReplace(sent, matchLocalId: localId);
      debugPrint('[ChatRoomController] SEND END (success) localId=$localId');
    } catch (e) {
      watchdog.cancel();
      debugPrint('[ChatRoomController] HTTP REQUEST ERROR localId=$localId error=$e watchdogAlreadyFired=$watchdogFired');
      debugPrint('[ChatRoomController] CATCH ERROR localId=$localId -> SET MESSAGE FAILED');
      _updateMessage(localId, (m) => m.copyWith(sendState: SendState.failed));
      debugPrint('[ChatRoomController] SEND END (failed) localId=$localId');
    }
  }

  Future<void> edit(String messageId, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final token = await _requireToken();
    final updated = await ref.read(messageApiProvider).editMessage(token, chatId, messageId, trimmed);
    _replaceById(updated);
  }

  Future<void> delete(String messageId) async {
    final token = await _requireToken();
    await ref.read(messageApiProvider).deleteMessage(token, chatId, messageId);
    _updateMessage(messageId, (m) => m.copyWith(deleted: true));
  }

  /// Called on every keystroke in the composer; debounces so a
  /// TYPING_STARTED event is sent at most once per burst of typing, and a
  /// TYPING_STOPPED event follows automatically after a short idle period.
  void onComposerChanged(String text) {
    _typingStopTimer?.cancel();
    if (text.isEmpty) {
      stopTyping();
      return;
    }
    if (!_sentTypingStarted) {
      _sentTypingStarted = true;
      _webSocket.sendTyping(chatId, true);
    }
    _typingStopTimer = Timer(const Duration(seconds: 3), stopTyping);
  }

  void stopTyping() {
    _typingStopTimer?.cancel();
    if (_sentTypingStarted) {
      _sentTypingStarted = false;
      _webSocket.sendTyping(chatId, false);
    }
  }

  void _connect(String token) {
    _webSocket.connect(
      token: token,
      onConnected: () => _webSocket.subscribeToChat(chatId, _handleEvent),
    );
  }

  void _handleEvent(ChatEvent event) {
    switch (event.type) {
      case 'NEW_MESSAGE':
        _appendOrReplace(Message.fromJson(event.payload), matchLocalId: null);
        unawaited(_markRead());
      case 'MESSAGE_UPDATED':
      case 'MESSAGE_STATUS_UPDATED':
        _replaceById(Message.fromJson(event.payload));
      case 'POLL_UPDATED':
        final pollId = event.payload['pollId'] as String?;
        final messageId = event.payload['messageId'] as String?;
        if (pollId != null && messageId != null) {
          unawaited(_refreshPoll(pollId, messageId));
        }
      case 'MEMBER_JOINED':
        ref.invalidate(groupDetailsProvider(chatId));
      case 'MESSAGE_DELETED':
        final id = event.payload['messageId'] as String?;
        if (id != null) {
          _updateMessage(id, (m) => m.copyWith(deleted: true));
        }
      case 'MESSAGES_READ':
        final ids = (event.payload['messageIds'] as List?)?.cast<String>() ?? const [];
        for (final id in ids) {
          _updateMessage(id, (m) => m.copyWith(status: MessageStatus.read));
        }
      case 'TYPING_STARTED':
        _typingClearTimer?.cancel();
        final username = event.payload['username'] as String?;
        final current = state.value;
        if (current != null) {
          state = AsyncData(current.copyWith(typingUsername: username));
        }
        _typingClearTimer = Timer(const Duration(seconds: 5), _clearTyping);
      case 'TYPING_STOPPED':
        _clearTyping();
    }
  }

  void _clearTyping() {
    _typingClearTimer?.cancel();
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(clearTyping: true));
    }
  }

  Future<void> _markRead() async {
    // Zeroed optimistically, in lockstep with the REST call below, so the
    // chat list's unread badge doesn't wait for a full refetch to reflect
    // that the user is actively reading this chat right now.
    ref.read(chatsControllerProvider.notifier).markChatRead(chatId);
    try {
      final token = await _requireToken();
      await ref.read(messageApiProvider).markRead(token, chatId);
    } catch (_) {
      // Best-effort - a reconnect/reload will resync state from the server.
    }
  }

  /// Acknowledges delivery (SENT -> DELIVERED) for messages from other
  /// participants that are still SENT - a message already READ (or already
  /// DELIVERED) is left alone, and the backend itself only ever advances a
  /// SENT message, so this is safe to call redundantly.
  Future<void> _acknowledgeDelivery(List<Message> messages, String myId, String token) async {
    final api = ref.read(messageApiProvider);
    for (final message in messages) {
      if (message.sender.id == myId || message.status != MessageStatus.sent) {
        continue;
      }
      try {
        await api.markDelivered(token, chatId, message.id);
      } catch (_) {
        // Best-effort - a later reconnect/resync will catch up regardless.
      }
    }
  }

  /// Inserts a confirmed message into the list, replacing the optimistic
  /// placeholder at [matchLocalId] if one is given (a REST send response),
  /// or appending it as new otherwise (a WebSocket broadcast).
  ///
  /// The two call sites race: a message this client just sent arrives via
  /// its own WebSocket subscription (the server broadcasts to every
  /// participant, sender included) independently of - and, over a real
  /// network, sometimes *before* - the REST response to the very request
  /// that created it. Without the `alreadyPresent` checks below, whichever
  /// path loses the race would blindly insert the same message a second
  /// time: if the broadcast wins, it appends the real message while the
  /// optimistic placeholder is still present, and the later REST response
  /// then "replaces" that placeholder with the same message again instead
  /// of recognizing it already arrived. Checking by the message's real id
  /// (never the local placeholder id) makes the outcome the same regardless
  /// of which path arrives first.
  void _appendOrReplace(Message message, {required String? matchLocalId}) {
    final current = state.value;
    if (current == null) return;
    final alreadyPresent = current.messages.any((m) => m.id == message.id);

    if (matchLocalId != null) {
      if (alreadyPresent) {
        // The real message already arrived via the WebSocket broadcast -
        // just drop the now-redundant optimistic placeholder rather than
        // inserting a second copy of the same message.
        state = AsyncData(current.copyWith(
          messages: [for (final m in current.messages) if (m.id != matchLocalId) m],
        ));
        return;
      }
      state = AsyncData(current.copyWith(
        messages: [
          for (final m in current.messages)
            if (m.id == matchLocalId) message else m,
        ],
      ));
      return;
    }

    if (alreadyPresent) return;
    state = AsyncData(current.copyWith(messages: [...current.messages, message]));
  }

  /// Replaces a message with a fresher copy of itself. A status/edit event
  /// carries no viewer-specific poll state, so the poll already held here is
  /// kept rather than blanked out.
  void _replaceById(Message message) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      messages: [
        for (final m in current.messages)
          if (m.id == message.id) (message.poll == null ? message.copyWith(poll: m.poll) : message) else m,
      ],
    ));
  }

  void _updateMessage(String id, Message Function(Message) update) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      messages: [
        for (final m in current.messages)
          if (m.id == id) update(m) else m,
      ],
    ));
  }

  Future<String> _requireToken() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('ChatRoomController used while not authenticated');
    }
    return authState.token;
  }

  void _disconnect() {
    _typingClearTimer?.cancel();
    _typingStopTimer?.cancel();
    stopTyping();
    _webSocket.disconnect();
    _recordingTimer?.cancel();
    _audioRecorder?.cancel();
    _audioRecorder = null;
  }
}

final chatRoomControllerProvider =
    AsyncNotifierProvider.autoDispose.family<ChatRoomController, ChatRoomState, String>(
  (chatId) => ChatRoomController(chatId),
  retry: noAutoRetry,
);
