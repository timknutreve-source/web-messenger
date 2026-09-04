import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/auth/domain/user.dart';
import 'package:mobile_messenger/features/profile/presentation/edit_profile_screen.dart';
import 'package:mobile_messenger/features/profile/profile_providers.dart';

import '../../support/fakes.dart';

/// A minimal router (Home -> Edit) so `context.pop()` inside
/// EditProfileScreen has somewhere real to return to, matching how it's
/// actually reached in the app.
GoRouter _testRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.push('/edit'),
              child: const Text('Go to edit'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/edit', builder: (context, state) => const EditProfileScreen()),
    ],
  );
}

void main() {
  late FakeProfileApi profileApi;
  late ProviderContainer container;

  setUp(() {
    profileApi = FakeProfileApi();
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
        ),
        profileApiProvider.overrideWithValue(profileApi),
        profileControllerProvider.overrideWith(() => FakeProfileController(sampleUser)),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pumpToEditScreen(WidgetTester tester) async {
    // In the real app, EditProfileScreen is only reachable via the "Edit
    // Profile" button on ProfileScreen, which only renders once
    // profileControllerProvider has resolved - so its data is always ready
    // by the time EditProfileScreen's initState() reads it synchronously.
    // Replicate that precondition here.
    await container.read(profileControllerProvider.future);

    final router = _testRouter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Go to edit'));
    await tester.pumpAndSettle();
  }

  testWidgets('pre-fills fields with the current profile', (tester) async {
    await pumpToEditScreen(tester);

    expect(find.widgetWithText(TextFormField, sampleUser.username), findsOneWidget);
    expect(find.widgetWithText(TextFormField, sampleUser.email), findsOneWidget);
  });

  testWidgets('rejects an invalid email', (tester) async {
    await pumpToEditScreen(tester);

    await tester.enterText(find.byKey(const Key('edit_profile_email_field')), 'not-an-email');
    await tester.tap(find.byKey(const Key('edit_profile_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('rejects an About Me over the max length', (tester) async {
    await pumpToEditScreen(tester);

    // The field's own `maxLength` stops normal typing/pasting at 500 chars,
    // so exceeding it (e.g. from data that predates a stricter limit) can
    // only reach the validator via a direct controller update.
    final field = tester.widget<TextFormField>(find.byKey(const Key('edit_profile_aboutMe_field')));
    field.controller!.text = 'a' * 501;
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('edit_profile_save_button')));
    await tester.tap(find.byKey(const Key('edit_profile_save_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('at most 500 characters'), findsOneWidget);
  });

  testWidgets('successful save shows confirmation and returns to the previous screen', (tester) async {
    profileApi.updateResult = sampleUser.copyWith(aboutMe: 'updated bio');
    await pumpToEditScreen(tester);

    await tester.enterText(find.byKey(const Key('edit_profile_aboutMe_field')), 'updated bio');
    await tester.tap(find.byKey(const Key('edit_profile_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Profile updated'), findsOneWidget);
    expect(find.text('Go to edit'), findsOneWidget); // back on the previous screen
  });

  testWidgets('shows a duplicate username error from the backend', (tester) async {
    profileApi.updateError = const DuplicateResourceException('Username is already taken');
    await pumpToEditScreen(tester);

    await tester.tap(find.byKey(const Key('edit_profile_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Username is already taken'), findsOneWidget);
  });

  testWidgets('shows a duplicate email error from the backend', (tester) async {
    profileApi.updateError = const DuplicateResourceException('Email is already registered');
    await pumpToEditScreen(tester);

    await tester.tap(find.byKey(const Key('edit_profile_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Email is already registered'), findsOneWidget);
  });

  testWidgets('prevents duplicate submissions while saving', (tester) async {
    final delay = Completer<User>();
    profileApi.updateDelay = delay;
    await pumpToEditScreen(tester);

    await tester.tap(find.byKey(const Key('edit_profile_save_button')));
    await tester.pump();

    // Mid-save (the fake's Future is still pending): the button shows a
    // spinner instead of "Save", proving a second tap can't re-trigger the
    // submit handler.
    expect(
      find.descendant(
        of: find.byKey(const Key('edit_profile_save_button')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    delay.complete(sampleUser);
    await tester.pumpAndSettle();
  });
}
