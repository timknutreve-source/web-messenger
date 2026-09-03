import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import 'data/health_api.dart';

final healthApiProvider = Provider<HealthApi>((ref) {
  return HealthApi(ref.watch(dioProvider));
});

/// Result of the most recent backend health check.
///
/// Re-fetch by calling `ref.invalidate(backendHealthProvider)`.
final backendHealthProvider = FutureProvider.autoDispose<void>((ref) async {
  final healthApi = ref.watch(healthApiProvider);
  await healthApi.checkHealth();
});
