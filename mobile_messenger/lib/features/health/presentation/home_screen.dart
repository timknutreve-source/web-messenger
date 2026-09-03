import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_exception.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../health_providers.dart';
import 'widgets/backend_status_view.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthState = ref.watch(backendHealthProvider);
    final authState = ref.watch(authControllerProvider).value;
    final user = authState is AuthAuthenticated ? authState.user : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Messenger'),
        actions: [
          IconButton(
            key: const Key('logout_button'),
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (user != null) ...[
                Text('Welcome, ${user.username}', style: Theme.of(context).textTheme.headlineSmall),
                if (!user.emailVerified) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Your email is not verified yet. Email verification is coming in a future update.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 24),
              ],
              Card(
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
            ],
          ),
        ),
      ),
    );
  }
}
