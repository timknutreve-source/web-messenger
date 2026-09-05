import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/chat/chat_providers.dart';

import '../../support/fakes.dart';

void main() {
  late FakeChatApi chatApi;
  late ProviderContainer container;

  setUp(() {
    chatApi = FakeChatApi();
    container = ProviderContainer(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  group('ChatsController', () {
    test('loads active chats on build', () async {
      chatApi.activeChatsResult = [sampleChatSummary];

      final chats = await container.read(chatsControllerProvider.future);

      expect(chats, hasLength(1));
      expect(chats.first.otherUser.username, 'bob');
    });

    test('archive calls the API and removes the chat from state', () async {
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);

      await container.read(chatsControllerProvider.notifier).archive(sampleChatSummary.id);

      expect(chatApi.archivedChatIds, [sampleChatSummary.id]);
      expect(container.read(chatsControllerProvider).value, isEmpty);
    });

    test('a failed archive throws and leaves the chat in state', () async {
      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(chatsControllerProvider.future);

      chatApi.archiveError = Exception('boom');

      await expectLater(
        container.read(chatsControllerProvider.notifier).archive(sampleChatSummary.id),
        throwsException,
      );
      expect(container.read(chatsControllerProvider).value, hasLength(1));
    });
  });

  group('ArchivedChatsController', () {
    test('loads archived chats on build', () async {
      chatApi.archivedChatsResult = [sampleChatSummary];

      final chats = await container.read(archivedChatsControllerProvider.future);

      expect(chats, hasLength(1));
    });

    test('unarchive calls the API and removes the chat from state', () async {
      chatApi.archivedChatsResult = [sampleChatSummary];
      await container.read(archivedChatsControllerProvider.future);

      await container.read(archivedChatsControllerProvider.notifier).unarchive(sampleChatSummary.id);

      expect(chatApi.unarchivedChatIds, [sampleChatSummary.id]);
      expect(container.read(archivedChatsControllerProvider).value, isEmpty);
    });

    test('unarchive invalidates the active chats list', () async {
      chatApi.archivedChatsResult = [sampleChatSummary];
      chatApi.activeChatsResult = [];
      await container.read(archivedChatsControllerProvider.future);
      await container.read(chatsControllerProvider.future);

      chatApi.activeChatsResult = [sampleChatSummary];
      await container.read(archivedChatsControllerProvider.notifier).unarchive(sampleChatSummary.id);

      final chats = await container.read(chatsControllerProvider.future);
      expect(chats, hasLength(1));
    });
  });
}
