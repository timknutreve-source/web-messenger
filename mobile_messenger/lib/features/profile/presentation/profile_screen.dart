import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/app_exception.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../profile_providers.dart';
import 'widgets/profile_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileControllerProvider);
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profileState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ProfileErrorView(
          message: error is AppException ? error.message : 'Something went wrong. Please try again.',
          onRetry: () => ref.invalidate(profileControllerProvider),
        ),
        data: (user) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProfileAvatar(avatarFileName: user.avatarFileName, token: token, radius: 56),
                  const SizedBox(height: 16),
                  Text(user.username, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(user.email, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('About Me', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      (user.aboutMe == null || user.aboutMe!.isEmpty)
                          ? 'No bio yet.'
                          : user.aboutMe!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    key: const Key('edit_profile_button'),
                    onPressed: () => context.push('/profile/edit'),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Profile'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileErrorView extends StatelessWidget {
  const _ProfileErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
