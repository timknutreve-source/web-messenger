import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_exception.dart';
import '../health_providers.dart';
import 'widgets/backend_status_view.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthState = ref.watch(backendHealthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Messenger')),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Backend status',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                healthState.when(
                  loading: () => const BackendStatusLoadingView(),
                  data: (_) => const BackendStatusConnectedView(),
                  error: (error, stackTrace) => BackendStatusErrorView(
                    message: error is AppException
                        ? error.message
                        : 'Something went wrong. Please try again.',
                    onRetry: () => ref.invalidate(backendHealthProvider),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
