import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_api.dart';
import 'package:mobile_messenger/features/auth/data/auth_local_storage.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/auth/domain/user.dart';
import 'package:mobile_messenger/features/contact/contact_providers.dart';
import 'package:mobile_messenger/features/contact/data/contact_api.dart';
import 'package:mobile_messenger/features/contact/domain/contact.dart';
import 'package:mobile_messenger/features/contact/domain/contact_user_summary.dart';
import 'package:mobile_messenger/features/contact/domain/pending_invitation.dart';
import 'package:mobile_messenger/features/health/data/health_api.dart';
import 'package:mobile_messenger/features/profile/data/profile_api.dart';
import 'package:mobile_messenger/features/profile/profile_providers.dart';

final sampleUser = User(
  id: 'user-1',
  username: 'alice',
  email: 'alice@example.com',
  emailVerified: false,
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
  Future<String> verifyEmail(String token) async {
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
  Future<String> resetPassword({required String token, required String newPassword}) async {
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
