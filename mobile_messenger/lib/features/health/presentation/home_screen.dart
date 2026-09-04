import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/network/error_presenter.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';
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
            key: const Key('view_profile_button'),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
            icon: Padding(
              padding: const EdgeInsets.all(4),
              child: ProfileAvatar(
                avatarFileName: user?.avatarFileName,
                token: authState is AuthAuthenticated ? authState.token : null,
                radius: 14,
              ),
            ),
          ),
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
                  const _UnverifiedEmailBanner(),
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

/// Shown on the home screen for an unverified account. Lets the user request
/// a fresh verification email without leaving the screen.
class _UnverifiedEmailBanner extends ConsumerStatefulWidget {
  const _UnverifiedEmailBanner();

  @override
  ConsumerState<_UnverifiedEmailBanner> createState() => _UnverifiedEmailBannerState();
}

class _UnverifiedEmailBannerState extends ConsumerState<_UnverifiedEmailBanner> {
  bool _isSending = false;
  String? _feedback;
  bool _feedbackIsError = false;

  Future<void> _resend() async {
    final authState = ref.read(authControllerProvider).value;
    if (_isSending || authState is! AuthAuthenticated) return;

    setState(() {
      _isSending = true;
      _feedback = null;
    });
    try {
      final message = await ref.read(authApiProvider).resendVerification(authState.token);
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _feedback = message;
        _feedbackIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _feedback = presentError(e).message;
        _feedbackIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          'Your email is not verified yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        TextButton(
          key: const Key('resend_verification_button'),
          onPressed: _isSending ? null : _resend,
          child: _isSending
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Resend verification email'),
        ),
        if (_feedback != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _feedback!,
              key: const Key('resend_verification_feedback'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _feedbackIsError ? colorScheme.error : colorScheme.primary),
            ),
          ),
      ],
    );
  }
}
