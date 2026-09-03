import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_api.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';

import '../../support/fakes.dart';

void main() {
  late FakeAuthApi authApi;
  late FakeAuthLocalStorage storage;
  late ProviderContainer container;

  setUp(() {
    authApi = FakeAuthApi();
    storage = FakeAuthLocalStorage();
    container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(authApi),
        authLocalStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
  });

  test('starts unauthenticated when there is no stored token', () async {
    final state = await container.read(authControllerProvider.future);
    expect(state, isA<AuthUnauthenticated>());
  });

  test('restores the session when a valid token was stored', () async {
    await storage.saveToken('stored-token');
    authApi.currentUser = sampleUser;

    final state = await container.read(authControllerProvider.future);

    expect(state, isA<AuthAuthenticated>());
    expect((state as AuthAuthenticated).user.username, 'alice');
    expect(state.token, 'stored-token');
  });

  test('clears the stored token and starts unauthenticated when it is rejected', () async {
    await storage.saveToken('expired-token');
    authApi.currentUserError = const InvalidCredentialsException();

    final state = await container.read(authControllerProvider.future);

    expect(state, isA<AuthUnauthenticated>());
    expect(await storage.readToken(), isNull);
  });

  test('login stores the token and becomes authenticated on success', () async {
    await container.read(authControllerProvider.future);
    authApi.loginResult = AuthResult(token: 'new-token', user: sampleUser);

    await container
        .read(authControllerProvider.notifier)
        .login(usernameOrEmail: 'alice', password: 'Str0ng!Pass');

    final state = container.read(authControllerProvider).value;
    expect(state, isA<AuthAuthenticated>());
    expect(await storage.readToken(), 'new-token');
  });

  test('login surfaces an error and does not store a token on failure', () async {
    await container.read(authControllerProvider.future);
    authApi.loginError = const InvalidCredentialsException();

    await container
        .read(authControllerProvider.notifier)
        .login(usernameOrEmail: 'alice', password: 'WrongPass1!');

    final asyncState = container.read(authControllerProvider);
    expect(asyncState.hasError, isTrue);
    expect(asyncState.error, isA<InvalidCredentialsException>());
    expect(await storage.readToken(), isNull);
  });

  test('register stores the token and becomes authenticated on success', () async {
    await container.read(authControllerProvider.future);
    authApi.registerResult = AuthResult(token: 'register-token', user: sampleUser);

    await container.read(authControllerProvider.notifier).register(
          username: 'alice',
          email: 'alice@example.com',
          password: 'Str0ng!Pass',
        );

    final state = container.read(authControllerProvider).value;
    expect(state, isA<AuthAuthenticated>());
    expect(await storage.readToken(), 'register-token');
  });

  test('logout clears the token and returns to unauthenticated', () async {
    await storage.saveToken('some-token');
    authApi.currentUser = sampleUser;
    await container.read(authControllerProvider.future);
    expect(container.read(authControllerProvider).value, isA<AuthAuthenticated>());

    await container.read(authControllerProvider.notifier).logout();

    expect(container.read(authControllerProvider).value, isA<AuthUnauthenticated>());
    expect(await storage.readToken(), isNull);
  });
}
