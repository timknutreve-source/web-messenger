import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/widgets/app_skeleton.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/auth/auth_providers.dart';
import 'package:mobile_messenger/features/auth/domain/auth_state.dart';
import 'package:mobile_messenger/features/profile/presentation/profile_screen.dart';
import 'package:mobile_messenger/features/profile/profile_providers.dart';

import '../../support/fakes.dart';

void main() {
  final authenticatedOverride = authControllerProvider.overrideWith(
    () => FakeAuthController(AuthAuthenticated(user: sampleUser, token: 'tok')),
  );

  testWidgets('shows a loading indicator while the profile is loading', (tester) async {
    final profileApi = FakeProfileApi()..profile = sampleUser;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, profileApiProvider.overrideWithValue(profileApi)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );

    expect(find.byType(Shimmer), findsOneWidget);
  });

  testWidgets('renders username, email, and About Me once loaded', (tester) async {
    final user = sampleUser.copyWith(username: 'alice', email: 'alice@example.com', aboutMe: 'I like Flutter');
    final profileApi = FakeProfileApi()..profile = user;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, profileApiProvider.overrideWithValue(profileApi)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('I like Flutter'), findsOneWidget);
  });

  testWidgets('shows a placeholder for an empty About Me', (tester) async {
    final profileApi = FakeProfileApi()..profile = sampleUser.copyWith(aboutMe: null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, profileApiProvider.overrideWithValue(profileApi)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No bio yet.'), findsOneWidget);
  });

  testWidgets('shows an error state with retry when loading fails', (tester) async {
    final profileApi = FakeProfileApi()..profileError = const NetworkUnavailableException();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authenticatedOverride, profileApiProvider.overrideWithValue(profileApi)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to connect. Please try again.'),
      findsOneWidget,
    );

    profileApi.profileError = null;
    profileApi.profile = sampleUser;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text(sampleUser.username), findsOneWidget);
  });
}
