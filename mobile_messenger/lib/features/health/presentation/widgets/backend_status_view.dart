import 'package:flutter/material.dart';

class BackendStatusLoadingView extends StatelessWidget {
  const BackendStatusLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        SizedBox(height: 16),
        Text('Checking connection...'),
      ],
    );
  }
}

class BackendStatusConnectedView extends StatelessWidget {
  const BackendStatusConnectedView({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, color: colorScheme.primary, size: 40),
        const SizedBox(height: 12),
        const Text('Connected', style: TextStyle(fontSize: 18)),
      ],
    );
  }
}

class BackendStatusErrorView extends StatelessWidget {
  const BackendStatusErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cancel, color: colorScheme.error, size: 40),
        const SizedBox(height: 12),
        const Text('Connection failed', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
