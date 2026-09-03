import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/core/network/app_exception.dart';
import 'package:mobile_messenger/features/health/data/health_api.dart';
import 'package:mobile_messenger/features/health/health_providers.dart';

class _FakeHealthApi extends HealthApi {
  _FakeHealthApi({this.error}) : super(Dio());

  final AppException? error;

  @override
  Future<void> checkHealth() async {
    if (error != null) throw error!;
  }
}

void main() {
  testWidgets('shows connected state when the backend is reachable',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthApiProvider.overrideWithValue(_FakeHealthApi()),
        ],
        child: const MobileMessengerApp(),
      ),
    );

    expect(find.text('Mobile Messenger'), findsOneWidget);
    expect(find.text('Backend status'), findsOneWidget);
    expect(find.text('Checking connection...'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('shows error state and can retry when the backend is unreachable',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthApiProvider.overrideWithValue(
            _FakeHealthApi(error: const NetworkUnavailableException()),
          ),
        ],
        child: const MobileMessengerApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
    expect(
      find.text('Could not reach the backend server. Make sure it is running.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
  });
}
