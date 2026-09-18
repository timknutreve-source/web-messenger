import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' show PlayerState;
import 'package:dio/dio.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_api.dart';
import 'package:mobile_messenger/features/auth/data/auth_local_storage.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/auth/domain/user.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';
import 'package:mobile_messenger/features/chat/data/attachment_api.dart';
import 'package:mobile_messenger/features/chat/data/attachment_picker.dart';
import 'package:mobile_messenger/features/chat/data/audio_recorder_service.dart';
import 'package:mobile_messenger/features/chat/data/chat_api.dart';
import 'package:mobile_messenger/features/chat/data/chat_audio_player.dart';
import 'package:mobile_messenger/features/chat/data/chat_websocket_client.dart';
import 'package:mobile_messenger/features/chat/data/message_api.dart';
import 'package:mobile_messenger/features/chat/domain/attachment.dart';
import 'package:mobile_messenger/features/chat/domain/chat_event.dart';
import 'package:mobile_messenger/features/chat/domain/chat_summary.dart';
import 'package:mobile_messenger/features/chat/domain/message.dart';
import 'package:mobile_messenger/features/chat/domain/message_page.dart';
import 'package:mobile_messenger/features/contact/contact_providers.dart';
import 'package:mobile_messenger/features/contact/data/contact_api.dart';
import 'package:mobile_messenger/features/contact/domain/contact.dart';
import 'package:mobile_messenger/features/contact/domain/contact_user_summary.dart';
import 'package:mobile_messenger/features/contact/domain/pending_invitation.dart';
import 'package:mobile_messenger/features/health/data/health_api.dart';
import 'package:mobile_messenger/features/profile/data/profile_api.dart';
import 'package:mobile_messenger/features/profile/profile_providers.dart';

/// Verified by default - most tests use this as an ordinary already-usable
/// signed-in account, not one specifically testing the verification gate.
/// Tests that need an unverified account should use
/// `sampleUser.copyWith(emailVerified: false)` explicitly.
final sampleUser = User(
  id: 'user-1',
  username: 'alice',
  email: 'alice@example.com',
  emailVerified: true,
  aboutMe: null,
  avatarFileName: null,
  createdAt: DateTime.utc(2026, 1, 1),
);

const sampleContactUser = ContactUserSummary(
  id: 'user-2',
  username: 'bob',
  email: 'bob@example.com',
  avatarFileName: null,
);

/// [sampleUser] represented as the sender of a [Message] - used when a test
/// needs to render a message as sent by "me".
const sampleUserContactSummary = ContactUserSummary(
  id: 'user-1',
  username: 'alice',
  email: 'alice@example.com',
  avatarFileName: null,
);

final sampleChatSummary = ChatSummary(
  id: 'chat-1',
  otherUser: sampleContactUser,
  lastActivityAt: DateTime.utc(2026, 1, 1),
  archived: false,
);

Message sampleMessage({
  String id = 'message-1',
  ContactUserSummary? sender,
  String? content = 'Hello',
  MessageStatus status = MessageStatus.sent,
  DateTime? createdAt,
  DateTime? editedAt,
  bool deleted = false,
  SendState sendState = SendState.confirmed,
  List<Attachment> attachments = const [],
}) =>
    Message(
      id: id,
      conversationId: 'chat-1',
      sender: sender ?? sampleContactUser,
      content: content,
      status: status,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1, 12),
      editedAt: editedAt,
      deleted: deleted,
      sendState: sendState,
      attachments: attachments,
    );

Attachment sampleAttachment({
  String id = 'attachment-1',
  AttachmentKind type = AttachmentKind.image,
  String mimeType = 'image/jpeg',
  int fileSize = 12345,
  int? width = 800,
  int? height = 600,
  int? durationSeconds,
  String? url,
  String? thumbnailUrl,
}) =>
    Attachment(
      id: id,
      type: type,
      mimeType: mimeType,
      fileSize: fileSize,
      width: width,
      height: height,
      durationSeconds: durationSeconds,
      url: url ?? '/api/attachments/$id',
      thumbnailUrl: thumbnailUrl ?? (type == AttachmentKind.image ? '/api/attachments/$id/thumbnail' : null),
    );

/// In-memory stand-in for [AuthLocalStorage] - no platform channel involved,
/// so it's safe to use in widget tests.
class FakeAuthLocalStorage extends AuthLocalStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> clearToken() async => _token = null;
}

/// Stand-in for [AuthApi] whose responses/errors are set directly by tests,
/// so no real HTTP call is ever made.
class FakeAuthApi extends AuthApi {
  FakeAuthApi() : super(Dio());

  AuthResult? loginResult;
  Object? loginError;

  AuthResult? registerResult;
  Object? registerError;

  User? currentUser;
  Object? currentUserError;

  String? verifyEmailResult;
  Object? verifyEmailError;

  String? resendVerificationResult;
  Object? resendVerificationError;

  String? forgotPasswordResult;
  Object? forgotPasswordError;

  String? resetPasswordResult;
  Object? resetPasswordError;

  /// When set, the matching method awaits this instead of resolving
  /// immediately - lets a test observe an in-flight "loading" state
  /// deterministically before completing it, instead of racing a
  /// same-microtask resolution.
  Completer<String>? verifyEmailDelay;
  Completer<String>? resendVerificationDelay;
  Completer<String>? forgotPasswordDelay;
  Completer<String>? resetPasswordDelay;

  @override
  Future<AuthResult> login({required String usernameOrEmail, required String password}) async {
    if (loginError != null) throw loginError!;
    return loginResult!;
  }

  @override
  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
  }) async {
    if (registerError != null) throw registerError!;
    return registerResult!;
  }

  @override
  Future<User> fetchCurrentUser(String token) async {
    if (currentUserError != null) throw currentUserError!;
    return currentUser!;
  }

  @override
  Future<String> verifyEmail({required String authToken, required String code}) async {
    if (verifyEmailDelay != null) return verifyEmailDelay!.future;
    if (verifyEmailError != null) throw verifyEmailError!;
    return verifyEmailResult ?? 'Your email has been verified.';
  }

  @override
  Future<String> resendVerification(String authToken) async {
    if (resendVerificationDelay != null) return resendVerificationDelay!.future;
    if (resendVerificationError != null) throw resendVerificationError!;
    return resendVerificationResult ?? 'Verification email sent.';
  }

  @override
  Future<String> forgotPassword(String email) async {
    if (forgotPasswordDelay != null) return forgotPasswordDelay!.future;
    if (forgotPasswordError != null) throw forgotPasswordError!;
    return forgotPasswordResult ??
        'If that email is registered, password reset instructions have been sent.';
  }

  @override
  Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    if (resetPasswordDelay != null) return resetPasswordDelay!.future;
    if (resetPasswordError != null) throw resetPasswordError!;
    return resetPasswordResult ?? 'Your password has been reset. You can now log in.';
  }
}

/// [AuthController] whose `build()` resolves immediately to a fixed state,
/// so widget tests don't depend on async storage/network resolution timing.
/// `login`/`register`/`logout` still run for real against whatever
/// `authApiProvider`/`authLocalStorageProvider` are overridden with.
class FakeAuthController extends AuthController {
  FakeAuthController(this._initialState);

  final AuthState _initialState;

  @override
  Future<AuthState> build() async => _initialState;
}

/// Stand-in for [HealthApi] that succeeds or fails without a real HTTP call.
class FakeHealthApi extends HealthApi {
  FakeHealthApi({this.error}) : super(Dio());

  final Object? error;

  @override
  Future<void> checkHealth() async {
    if (error != null) throw error!;
  }
}

/// Stand-in for [ProfileApi] whose responses/errors are set directly by
/// tests, so no real HTTP call or file upload is ever made.
class FakeProfileApi extends ProfileApi {
  FakeProfileApi() : super(Dio());

  User? profile;
  Object? profileError;

  User? updateResult;
  Object? updateError;

  User? uploadResult;
  Object? uploadError;

  /// When set, [updateProfile] awaits this instead of resolving immediately -
  /// lets a test observe the in-flight "saving" state deterministically
  /// before completing it, instead of racing a same-microtask resolution.
  Completer<User>? updateDelay;

  @override
  Future<User> getProfile(String token) async {
    if (profileError != null) throw profileError!;
    return profile!;
  }

  @override
  Future<User> updateProfile(
    String token, {
    required String username,
    required String email,
    required String aboutMe,
  }) async {
    if (updateDelay != null) return updateDelay!.future;
    if (updateError != null) throw updateError!;
    return updateResult!;
  }

  @override
  Future<User> uploadAvatar(String token, File imageFile) async {
    if (uploadError != null) throw uploadError!;
    return uploadResult!;
  }
}

/// [ProfileController] whose `build()` resolves immediately to a fixed user,
/// so widget tests don't depend on async network resolution timing.
/// `updateProfile`/`uploadAvatar` still run for real against whatever
/// `profileApiProvider` is overridden with.
class FakeProfileController extends ProfileController {
  FakeProfileController(this._initialUser);

  final User _initialUser;

  @override
  Future<User> build() async => _initialUser;
}

/// Stand-in for [ContactApi] whose responses/errors are set directly by
/// tests, so no real HTTP call is ever made.
class FakeContactApi extends ContactApi {
  FakeContactApi() : super(Dio());

  List<ContactUserSummary>? searchResult;
  Object? searchError;

  List<Contact>? contactsResult;
  Object? contactsError;

  List<PendingInvitation>? pendingResult;
  Object? pendingError;

  Object? sendInvitationError;
  Object? acceptInvitationError;
  Object? declineInvitationError;

  final List<String> sentInvitationRecipientIds = [];
  final List<String> acceptedInvitationIds = [];
  final List<String> declinedInvitationIds = [];

  @override
  Future<List<ContactUserSummary>> search(String token, String query) async {
    if (searchError != null) throw searchError!;
    return searchResult ?? [];
  }

  @override
  Future<List<Contact>> listContacts(String token) async {
    if (contactsError != null) throw contactsError!;
    return contactsResult ?? [];
  }

  @override
  Future<List<PendingInvitation>> listPendingInvitations(String token) async {
    if (pendingError != null) throw pendingError!;
    return pendingResult ?? [];
  }

  @override
  Future<void> sendInvitation(String token, String recipientId) async {
    if (sendInvitationError != null) throw sendInvitationError!;
    sentInvitationRecipientIds.add(recipientId);
  }

  @override
  Future<void> acceptInvitation(String token, String invitationId) async {
    if (acceptInvitationError != null) throw acceptInvitationError!;
    acceptedInvitationIds.add(invitationId);
  }

  @override
  Future<void> declineInvitation(String token, String invitationId) async {
    if (declineInvitationError != null) throw declineInvitationError!;
    declinedInvitationIds.add(invitationId);
  }
}

/// [ContactsController] whose `build()` resolves immediately to a fixed
/// list, so widget tests don't depend on async network resolution timing.
class FakeContactsController extends ContactsController {
  FakeContactsController(this._initialContacts);

  final List<Contact> _initialContacts;

  @override
  Future<List<Contact>> build() async => _initialContacts;
}

/// [PendingInvitationsController] whose `build()` resolves immediately to a
/// fixed list, so widget tests don't depend on async network resolution
/// timing. `accept`/`decline` still run for real against whatever
/// `contactApiProvider` is overridden with.
class FakePendingInvitationsController extends PendingInvitationsController {
  FakePendingInvitationsController(this._initialInvitations);

  final List<PendingInvitation> _initialInvitations;

  @override
  Future<List<PendingInvitation>> build() async => _initialInvitations;
}

/// Stand-in for [ChatApi] whose responses/errors are set directly by tests,
/// so no real HTTP call is ever made.
class FakeChatApi extends ChatApi {
  FakeChatApi() : super(Dio());

  List<ChatSummary>? activeChatsResult;
  Object? activeChatsError;

  List<ChatSummary>? archivedChatsResult;
  Object? archivedChatsError;

  Object? archiveError;
  Object? unarchiveError;

  final List<String> archivedChatIds = [];
  final List<String> unarchivedChatIds = [];

  /// When set, the matching method awaits this instead of resolving
  /// immediately - lets a test observe an in-flight "loading" state
  /// deterministically before completing it, instead of racing a
  /// same-microtask resolution.
  Completer<List<ChatSummary>>? activeChatsDelay;
  Completer<List<ChatSummary>>? archivedChatsDelay;

  int listActiveChatsCallCount = 0;

  @override
  Future<List<ChatSummary>> listActiveChats(String token) async {
    listActiveChatsCallCount++;
    if (activeChatsDelay != null) return activeChatsDelay!.future;
    if (activeChatsError != null) throw activeChatsError!;
    return activeChatsResult ?? [];
  }

  @override
  Future<List<ChatSummary>> listArchivedChats(String token) async {
    if (archivedChatsDelay != null) return archivedChatsDelay!.future;
    if (archivedChatsError != null) throw archivedChatsError!;
    return archivedChatsResult ?? [];
  }

  @override
  Future<ChatSummary> archiveChat(String token, String chatId) async {
    if (archiveError != null) throw archiveError!;
    archivedChatIds.add(chatId);
    return sampleChatSummary;
  }

  @override
  Future<ChatSummary> unarchiveChat(String token, String chatId) async {
    if (unarchiveError != null) throw unarchiveError!;
    unarchivedChatIds.add(chatId);
    return sampleChatSummary;
  }
}

/// [ChatsController] whose `build()` resolves immediately to a fixed list,
/// so widget tests don't depend on async network resolution timing.
/// `archive` still runs for real against whatever `chatApiProvider` is
/// overridden with.
class FakeChatsController extends ChatsController {
  FakeChatsController(this._initialChats);

  final List<ChatSummary> _initialChats;

  @override
  Future<List<ChatSummary>> build() async => _initialChats;
}

/// [ArchivedChatsController] whose `build()` resolves immediately to a fixed
/// list, so widget tests don't depend on async network resolution timing.
/// `unarchive` still runs for real against whatever `chatApiProvider` is
/// overridden with.
class FakeArchivedChatsController extends ArchivedChatsController {
  FakeArchivedChatsController(this._initialChats);

  final List<ChatSummary> _initialChats;

  @override
  Future<List<ChatSummary>> build() async => _initialChats;
}

/// Stand-in for [MessageApi] whose responses/errors are set directly by
/// tests, so no real HTTP call is ever made.
class FakeMessageApi extends MessageApi {
  FakeMessageApi() : super(Dio());

  MessagePage loadMessagesResult = const MessagePage(messages: [], hasMore: false);
  Object? loadMessagesError;

  Message? sendMessageResult;
  Object? sendMessageError;

  /// When set, [sendMessage] waits on this instead of resolving immediately -
  /// lets a test simulate a slow REST response racing against a WebSocket
  /// broadcast for the same message that arrives first.
  Completer<void>? sendMessageGate;

  Message? editMessageResult;
  Object? editMessageError;

  Object? deleteMessageError;
  Object? markReadError;
  Object? markDeliveredError;

  final List<String?> sentContents = [];
  final List<List<String>?> sentAttachmentIds = [];
  final List<String> editedMessageIds = [];
  final List<String> deletedMessageIds = [];
  int markReadCallCount = 0;
  int loadMessagesCallCount = 0;

  @override
  Future<MessagePage> loadMessages(String token, String chatId, {String? before, int? limit}) async {
    loadMessagesCallCount++;
    if (loadMessagesError != null) throw loadMessagesError!;
    return loadMessagesResult;
  }

  @override
  Future<Message> sendMessage(
    String token,
    String chatId,
    String? content, {
    List<String>? attachmentIds,
  }) async {
    sentContents.add(content);
    sentAttachmentIds.add(attachmentIds);
    if (sendMessageGate != null) await sendMessageGate!.future;
    if (sendMessageError != null) throw sendMessageError!;
    return sendMessageResult ?? sampleMessage(id: 'sent-${sentContents.length}', content: content);
  }

  @override
  Future<Message> editMessage(String token, String chatId, String messageId, String content) async {
    editedMessageIds.add(messageId);
    if (editMessageError != null) throw editMessageError!;
    return editMessageResult ?? sampleMessage(id: messageId, content: content, editedAt: DateTime.now());
  }

  @override
  Future<void> deleteMessage(String token, String chatId, String messageId) async {
    deletedMessageIds.add(messageId);
    if (deleteMessageError != null) throw deleteMessageError!;
  }

  @override
  Future<void> markRead(String token, String chatId) async {
    markReadCallCount++;
    if (markReadError != null) throw markReadError!;
  }

  final List<String> markedDeliveredMessageIds = [];

  @override
  Future<void> markDelivered(String token, String chatId, String messageId) async {
    markedDeliveredMessageIds.add(messageId);
    if (markDeliveredError != null) throw markDeliveredError!;
  }
}

/// Stand-in for [ChatWebSocketClient]: never opens a real socket.
/// `connect()` resolves synchronously, and [emit] lets a test simulate an
/// incoming broadcast on the chat topic the controller subscribed to.
///
/// Supports multiple simultaneous subscriptions (matching a real STOMP
/// broker's fan-out): [emit] calls every listener registered via [subscribe],
/// since in real usage more than one controller can independently subscribe
/// to the same destination (e.g. `ChatRoomController` and `ChatsController`
/// both subscribing to the same open chat's topic) and each must
/// independently receive the same broadcast.
class FakeChatWebSocketClient extends ChatWebSocketClient {
  final List<void Function(ChatEvent event)> _listeners = [];
  final List<bool> typingCalls = [];
  bool disconnected = false;

  @override
  bool get isConnected => true;

  @override
  void connect({
    required String token,
    void Function()? onConnected,
    void Function(Object error)? onError,
  }) {
    onConnected?.call();
  }

  /// Set by [subscribe] to whatever destination was last subscribed to, so
  /// a test can assert which topic a controller subscribed to if it needs to.
  String? lastSubscribedDestination;

  @override
  StompUnsubscribe subscribe(String destination, void Function(ChatEvent event) onEvent) {
    lastSubscribedDestination = destination;
    _listeners.add(onEvent);
    return ({Map<String, String>? unsubscribeHeaders}) {};
  }

  @override
  void sendTyping(String chatId, bool started) {
    typingCalls.add(started);
  }

  @override
  void disconnect() {
    disconnected = true;
  }

  void emit(ChatEvent event) {
    for (final listener in List.of(_listeners)) {
      listener(event);
    }
  }
}

/// Stand-in for [AttachmentApi] whose responses/errors are set directly by
/// tests, so no real HTTP call or file upload is ever made.
class FakeAttachmentApi extends AttachmentApi {
  FakeAttachmentApi() : super(Dio());

  Attachment? uploadResult;
  Object? uploadError;

  /// When set, [upload] awaits this instead of resolving immediately - lets
  /// a test observe the "uploading" state deterministically before
  /// completing it.
  Completer<Attachment>? uploadDelay;

  final List<String> uploadedFilePaths = [];
  final List<int?> uploadedDurations = [];

  @override
  Future<Attachment> upload(String token, String chatId, File file, {int? durationSeconds}) async {
    uploadedFilePaths.add(file.path);
    uploadedDurations.add(durationSeconds);
    if (uploadDelay != null) return uploadDelay!.future;
    if (uploadError != null) throw uploadError!;
    return uploadResult ?? sampleAttachment();
  }
}

/// Stand-in for [AttachmentPicker]: returns a canned local [File] instead of
/// invoking the real `image_picker` platform channel, which isn't available
/// in plain unit/widget tests. The file just needs to exist on disk - tests
/// point it at a temp file with a few dummy bytes.
class FakeAttachmentPicker extends AttachmentPicker {
  File? imageResult;
  File? videoResult;

  final List<ImageSource> imagePickSources = [];
  final List<ImageSource> videoPickSources = [];

  @override
  Future<File?> pickImage(ImageSource source) async {
    imagePickSources.add(source);
    return imageResult;
  }

  @override
  Future<File?> pickVideo(ImageSource source) async {
    videoPickSources.add(source);
    return videoResult;
  }
}

/// Stand-in for [AudioRecorderService]: never touches the microphone or a
/// real platform channel. [hasPermissionResult] controls whether recording
/// is allowed to start; [stopResult] is the file [stop] returns (defaulting
/// to a small real temp file so callers that check for existence succeed).
class FakeAudioRecorderService extends AudioRecorderService {
  bool hasPermissionResult = true;
  File? stopResult;
  bool started = false;
  bool cancelled = false;
  int stopCallCount = 0;

  @override
  Future<bool> hasPermission() async => hasPermissionResult;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<File?> stop() async {
    stopCallCount++;
    started = false;
    return stopResult ??
        (File('${Directory.systemTemp.path}/fake_voice_message.wav')..writeAsBytesSync([1, 2, 3]));
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    started = false;
  }

  @override
  void dispose() {}
}

/// Stand-in for [ChatAudioPlayer]: never fetches real bytes or touches a
/// real platform audio player. [emitComplete] lets a test simulate playback
/// finishing on its own (not via a manual pause).
class FakeChatAudioPlayer extends ChatAudioPlayer {
  FakeChatAudioPlayer() : super(Dio());

  final _stateController = StreamController<PlayerState>.broadcast();
  final _completeController = StreamController<void>.broadcast();

  bool isPlaying = false;
  final List<String> playedUrls = [];
  Object? playError;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _stateController.stream;

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  @override
  Stream<Duration> get onPositionChanged => const Stream.empty();

  @override
  Future<void> playFromUrl(String url, String token) async {
    playedUrls.add(url);
    if (playError != null) throw playError!;
    isPlaying = true;
    _stateController.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _stateController.add(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    isPlaying = true;
    _stateController.add(PlayerState.playing);
  }

  void emitComplete() {
    isPlaying = false;
    _completeController.add(null);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _completeController.close();
  }
}
