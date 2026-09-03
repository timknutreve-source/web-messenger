import 'package:dio/dio.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_api.dart';
import 'package:mobile_messenger/features/auth/data/auth_local_storage.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/auth/domain/user.dart';
import 'package:mobile_messenger/features/health/data/health_api.dart';

final sampleUser = User(
  id: 'user-1',
  username: 'alice',
  email: 'alice@example.com',
  emailVerified: false,
  createdAt: DateTime.utc(2026, 1, 1),
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
