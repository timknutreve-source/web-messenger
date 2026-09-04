import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/contact/contact_providers.dart';
import 'package:mobile_messenger/features/contact/domain/contact.dart';
import 'package:mobile_messenger/features/contact/domain/pending_invitation.dart';

import '../../support/fakes.dart';

void main() {
  late FakeContactApi contactApi;
  late ProviderContainer container;

  setUp(() {
    contactApi = FakeContactApi();
    container = ProviderContainer(
      overrides: [
        contactApiProvider.overrideWithValue(contactApi),
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  group('ContactsController', () {
    test('loads the current contacts on build', () async {
      contactApi.contactsResult = [Contact(user: sampleContactUser, since: DateTime.utc(2026, 1, 1))];

      final contacts = await container.read(contactsControllerProvider.future);

      expect(contacts, hasLength(1));
      expect(contacts.first.user.username, 'bob');
    });
  });

  group('PendingInvitationsController', () {
    final invitation = PendingInvitation(
      id: 'inv-1',
      sender: sampleContactUser,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    test('loads pending invitations on build', () async {
      contactApi.pendingResult = [invitation];

      final invitations = await container.read(pendingInvitationsControllerProvider.future);

      expect(invitations, hasLength(1));
      expect(invitations.first.sender.username, 'bob');
    });

    test('accept calls the API and removes the invitation from state', () async {
      contactApi.pendingResult = [invitation];
      await container.read(pendingInvitationsControllerProvider.future);

      await container.read(pendingInvitationsControllerProvider.notifier).accept('inv-1');

      expect(contactApi.acceptedInvitationIds, ['inv-1']);
      expect(container.read(pendingInvitationsControllerProvider).value, isEmpty);
    });

    test('accept invalidates the contacts list so the new contact appears', () async {
      contactApi.pendingResult = [invitation];
      contactApi.contactsResult = [];
      await container.read(pendingInvitationsControllerProvider.future);
      await container.read(contactsControllerProvider.future);

      contactApi.contactsResult = [Contact(user: sampleContactUser, since: DateTime.utc(2026, 1, 1))];
      await container.read(pendingInvitationsControllerProvider.notifier).accept('inv-1');

      final contacts = await container.read(contactsControllerProvider.future);
      expect(contacts, hasLength(1));
    });

    test('decline calls the API and removes the invitation from state', () async {
      contactApi.pendingResult = [invitation];
      await container.read(pendingInvitationsControllerProvider.future);

      await container.read(pendingInvitationsControllerProvider.notifier).decline('inv-1');

      expect(contactApi.declinedInvitationIds, ['inv-1']);
      expect(container.read(pendingInvitationsControllerProvider).value, isEmpty);
    });

    test('a failed accept throws and leaves the invitation in state', () async {
      contactApi.pendingResult = [invitation];
      await container.read(pendingInvitationsControllerProvider.future);

      contactApi.acceptInvitationError = Exception('boom');

      await expectLater(
        container.read(pendingInvitationsControllerProvider.notifier).accept('inv-1'),
        throwsException,
      );
      expect(container.read(pendingInvitationsControllerProvider).value, hasLength(1));
    });
  });

  group('ContactSearchController', () {
    test('starts with no results', () async {
      final results = await container.read(contactSearchControllerProvider.future);
      expect(results, isEmpty);
    });

    test('search populates results for a valid query', () async {
      contactApi.searchResult = [sampleContactUser];

      await container.read(contactSearchControllerProvider.notifier).search('bob');

      expect(container.read(contactSearchControllerProvider).value, hasLength(1));
    });

    test('search does not call the API for a too-short query', () async {
      contactApi.searchResult = [sampleContactUser];

      await container.read(contactSearchControllerProvider.notifier).search('b');

      expect(container.read(contactSearchControllerProvider).value, isEmpty);
    });

    test('search surfaces an error', () async {
      contactApi.searchError = Exception('boom');

      await container.read(contactSearchControllerProvider.notifier).search('bob');

      expect(container.read(contactSearchControllerProvider).hasError, isTrue);
    });
  });
}
