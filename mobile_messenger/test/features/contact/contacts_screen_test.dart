import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/contact/contact_providers.dart';
import 'package:mobile_messenger/features/contact/domain/contact.dart';
import 'package:mobile_messenger/features/contact/domain/pending_invitation.dart';
import 'package:mobile_messenger/features/contact/presentation/contacts_screen.dart';

import '../../support/fakes.dart';

void main() {
  final authenticatedOverride = authControllerProvider.overrideWith(
    () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
  );

  final samplePendingInvitation = PendingInvitation(
    id: 'inv-1',
    sender: sampleContactUser,
    createdAt: DateTime.utc(2026, 1, 1),
  );

  final sampleContact = Contact(user: sampleContactUser, since: DateTime.utc(2026, 1, 1));

  group('Contacts tab', () {
    testWidgets('renders the contacts screen with three tabs', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedOverride, ...[contactsControllerProvider.overrideWith(() => FakeContactsController([]))]],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contacts_screen')), findsOneWidget);
      expect(find.byKey(const Key('contacts_tab')), findsOneWidget);
      expect(find.byKey(const Key('pending_tab')), findsOneWidget);
      expect(find.byKey(const Key('search_tab')), findsOneWidget);
    });

    testWidgets('shows an empty state when there are no contacts', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedOverride, ...[contactsControllerProvider.overrideWith(() => FakeContactsController([]))]],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contacts_empty_view')), findsOneWidget);
    });

    testWidgets('renders a contact once loaded', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedOverride, ...[
            contactsControllerProvider.overrideWith(() => FakeContactsController([sampleContact])),
          ]],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('bob'), findsOneWidget);
      expect(find.text('bob@example.com'), findsOneWidget);
    });

    testWidgets('shows an error state with retry when loading contacts fails', (tester) async {
      final contactApi = FakeContactApi()..contactsError = const NetworkUnavailableException();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authenticatedOverride,
            contactApiProvider.overrideWithValue(contactApi),
            pendingInvitationsControllerProvider.overrideWith(() => FakePendingInvitationsController([])),
          ],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to connect. Please try again.'),
        findsOneWidget,
      );

      contactApi.contactsError = null;
      contactApi.contactsResult = [sampleContact];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('bob'), findsOneWidget);
    });
  });

  group('Pending invitations tab', () {
    testWidgets('shows an empty state when there are no pending invitations', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedOverride, ...[
            pendingInvitationsControllerProvider.overrideWith(() => FakePendingInvitationsController([])),
          ]],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_tab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pending_empty_view')), findsOneWidget);
    });

    testWidgets('renders a pending invitation with sender info and action buttons', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedOverride, ...[
            pendingInvitationsControllerProvider
                .overrideWith(() => FakePendingInvitationsController([samplePendingInvitation])),
          ]],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_tab')));
      await tester.pumpAndSettle();

      expect(find.text('bob'), findsOneWidget);
      expect(find.text('bob@example.com'), findsOneWidget);
      expect(find.byKey(const Key('accept_invitation_button_inv-1')), findsOneWidget);
      expect(find.byKey(const Key('decline_invitation_button_inv-1')), findsOneWidget);
    });

    testWidgets('accepting an invitation removes it from the list with success feedback',
        (tester) async {
      final contactApi = FakeContactApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authenticatedOverride,
            contactApiProvider.overrideWithValue(contactApi),
            pendingInvitationsControllerProvider
                .overrideWith(() => FakePendingInvitationsController([samplePendingInvitation])),
            contactsControllerProvider.overrideWith(() => FakeContactsController([])),
          ],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_tab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('accept_invitation_button_inv-1')));
      await tester.pumpAndSettle();

      expect(contactApi.acceptedInvitationIds, ['inv-1']);
      expect(find.byKey(const Key('pending_invitation_tile_inv-1')), findsNothing);
      expect(find.byKey(const Key('pending_empty_view')), findsOneWidget);
    });

    testWidgets('declining an invitation removes it from the list', (tester) async {
      final contactApi = FakeContactApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authenticatedOverride,
            contactApiProvider.overrideWithValue(contactApi),
            pendingInvitationsControllerProvider
                .overrideWith(() => FakePendingInvitationsController([samplePendingInvitation])),
          ],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_tab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('decline_invitation_button_inv-1')));
      await tester.pumpAndSettle();

      expect(contactApi.declinedInvitationIds, ['inv-1']);
      expect(find.byKey(const Key('pending_invitation_tile_inv-1')), findsNothing);
      expect(find.byKey(const Key('pending_empty_view')), findsOneWidget);
    });

    testWidgets('shows an error and keeps the invitation when accept fails', (tester) async {
      final contactApi = FakeContactApi()
        ..acceptInvitationError = const DuplicateResourceException('This invitation has already been responded to');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authenticatedOverride,
            contactApiProvider.overrideWithValue(contactApi),
            pendingInvitationsControllerProvider
                .overrideWith(() => FakePendingInvitationsController([samplePendingInvitation])),
          ],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending_tab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('accept_invitation_button_inv-1')));
      await tester.pumpAndSettle();

      expect(find.text('This invitation has already been responded to'), findsOneWidget);
      expect(find.byKey(const Key('pending_invitation_tile_inv-1')), findsOneWidget);
    });
  });

  group('Search tab', () {
    testWidgets('shows search results with a send-invitation action', (tester) async {
      final contactApi = FakeContactApi()..searchResult = [sampleContactUser];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedOverride, contactApiProvider.overrideWithValue(contactApi)],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search_tab')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('contact_search_field')), 'bob');
      await tester.tap(find.byKey(const Key('contact_search_submit_button')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('search_result_tile_user-2')),
          matching: find.text('bob'),
        ),
        findsOneWidget,
      );
      expect(find.text('bob@example.com'), findsOneWidget);
      expect(find.byKey(const Key('send_invitation_button_user-2')), findsOneWidget);
    });

    testWidgets('sending an invitation shows success feedback on the row', (tester) async {
      final contactApi = FakeContactApi()..searchResult = [sampleContactUser];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedOverride, contactApiProvider.overrideWithValue(contactApi)],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search_tab')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('contact_search_field')), 'bob');
      await tester.tap(find.byKey(const Key('contact_search_submit_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('send_invitation_button_user-2')));
      await tester.pumpAndSettle();

      expect(contactApi.sentInvitationRecipientIds, ['user-2']);
      expect(find.byKey(const Key('invitation_sent_label_user-2')), findsOneWidget);
      expect(find.byKey(const Key('send_invitation_button_user-2')), findsNothing);
    });

    testWidgets('shows an error when sending an invitation fails', (tester) async {
      final contactApi = FakeContactApi()
        ..searchResult = [sampleContactUser]
        ..sendInvitationError = const DuplicateResourceException('You are already contacts');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedOverride, contactApiProvider.overrideWithValue(contactApi)],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search_tab')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('contact_search_field')), 'bob');
      await tester.tap(find.byKey(const Key('contact_search_submit_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('send_invitation_button_user-2')));
      await tester.pumpAndSettle();

      expect(find.text('You are already contacts'), findsOneWidget);
      expect(find.byKey(const Key('send_invitation_button_user-2')), findsOneWidget);
    });

    testWidgets('shows an empty state before any search is performed', (tester) async {
      final contactApi = FakeContactApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedOverride, contactApiProvider.overrideWithValue(contactApi)],
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search_tab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search_empty_view')), findsOneWidget);
    });
  });
}
