import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/profile/profile_providers.dart';

import '../../support/fakes.dart';

void main() {
  late FakeProfileApi profileApi;
  late ProviderContainer container;

  setUp(() {
    profileApi = FakeProfileApi();
    container = ProviderContainer(
      overrides: [
        profileApiProvider.overrideWithValue(profileApi),
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  test('loads the current profile on build', () async {
    profileApi.profile = sampleUser.copyWith(aboutMe: 'hello');

    final user = await container.read(profileControllerProvider.future);

    expect(user.aboutMe, 'hello');
  });

  test('updateProfile stores the returned profile and syncs AuthController', () async {
    profileApi.profile = sampleUser;
    await container.read(profileControllerProvider.future);

    final updated = sampleUser.copyWith(username: 'alice2', aboutMe: 'new bio');
    profileApi.updateResult = updated;

    await container.read(profileControllerProvider.notifier).updateProfile(
          username: 'alice2',
          email: sampleUser.email,
          aboutMe: 'new bio',
        );

    expect(container.read(profileControllerProvider).value?.username, 'alice2');

    final authState = container.read(authControllerProvider).value;
    expect(authState, isA<AuthAuthenticated>());
    expect((authState as AuthAuthenticated).user.username, 'alice2');
  });

  test('updateProfile surfaces a duplicate username error', () async {
    profileApi.profile = sampleUser;
    await container.read(profileControllerProvider.future);

    profileApi.updateError = const DuplicateResourceException('Username is already taken');

    await container.read(profileControllerProvider.notifier).updateProfile(
          username: 'taken',
          email: sampleUser.email,
          aboutMe: '',
        );

    final state = container.read(profileControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<DuplicateResourceException>());
  });

  test('updateProfile surfaces a duplicate email error', () async {
    profileApi.profile = sampleUser;
    await container.read(profileControllerProvider.future);

    profileApi.updateError = const DuplicateResourceException('Email is already registered');

    await container.read(profileControllerProvider.notifier).updateProfile(
          username: sampleUser.username,
          email: 'taken@example.com',
          aboutMe: '',
        );

    expect(container.read(profileControllerProvider).error, isA<DuplicateResourceException>());
  });

  test('uploadAvatar stores the returned profile and syncs AuthController', () async {
    profileApi.profile = sampleUser;
    await container.read(profileControllerProvider.future);

    final updated = sampleUser.copyWith(avatarFileName: 'new-avatar.jpg');
    profileApi.uploadResult = updated;

    await container.read(profileControllerProvider.notifier).uploadAvatar(XFile('irrelevant.jpg'));

    expect(container.read(profileControllerProvider).value?.avatarFileName, 'new-avatar.jpg');
    final authState = container.read(authControllerProvider).value as AuthAuthenticated;
    expect(authState.user.avatarFileName, 'new-avatar.jpg');
  });

  test('uploadAvatar surfaces a failure without clearing the previous profile data', () async {
    profileApi.profile = sampleUser;
    await container.read(profileControllerProvider.future);

    profileApi.uploadError = const FileTooLargeException();

    await container.read(profileControllerProvider.notifier).uploadAvatar(XFile('irrelevant.jpg'));

    final state = container.read(profileControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<FileTooLargeException>());
  });
}
