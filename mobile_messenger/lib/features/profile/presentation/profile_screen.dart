import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_surface.dart';
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

    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profileState.when(
        loading: () => const ProfileSkeleton(),
        error: (error, stackTrace) => AppErrorState(
          message: error is AppException ? error.message : 'Something went wrong. Please try again.',
          onRetry: () => ref.invalidate(profileControllerProvider),
        ),
        data: (user) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppLayout.formMaxWidth),
              child: AppSurface(
                radius: AppRadius.xl,
                shadow: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Identity band: the signature deep-green to warm-gold wash,
                    // with the avatar straddling its lower edge.
                    Stack(
                      children: [
                        Container(height: 112, decoration: BoxDecoration(gradient: c.signatureGradient)),
                        Padding(
                          padding: const EdgeInsets.only(top: 56),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                                child: ProfileAvatar(
                                  avatarFileName: user.avatarFileName,
                                  token: token,
                                  radius: 56,
                                  name: user.username,
                                  ring: true,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(user.username, style: text.headlineMedium),
                              const SizedBox(height: 2),
                              Text(user.email, style: text.bodyMedium?.copyWith(color: c.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppSurface(
                            elevated: true,
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('About Me', style: text.titleSmall),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  (user.aboutMe == null || user.aboutMe!.isEmpty) ? 'No bio yet.' : user.aboutMe!,
                                  style: text.bodyMedium?.copyWith(
                                    color: (user.aboutMe == null || user.aboutMe!.isEmpty)
                                        ? c.textMuted
                                        : c.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          FilledButton.icon(
                            key: const Key('edit_profile_button'),
                            onPressed: () => context.push('/profile/edit'),
                            icon: const Icon(Icons.edit_rounded),
                            label: const Text('Edit Profile'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
