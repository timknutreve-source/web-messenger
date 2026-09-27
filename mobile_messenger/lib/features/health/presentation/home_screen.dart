import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../chat/presentation/widgets/chat_list_tile.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../chat/chat_providers.dart';
import '../../contact/contact_providers.dart';
import '../../group/group_providers.dart';
import '../../profile/presentation/widgets/profile_avatar.dart';

/// Total unread messages across every active (non-archived) chat - the
/// Chats icon's badge. Derived entirely from [chatsControllerProvider]'s
/// existing per-chat `unreadCount` (itself kept live by that controller's
/// own WebSocket subscription - see its Javadoc) rather than tracking
/// anything separately, so there is exactly one source of truth for "how
/// many messages are unread".
final unreadMessageCountProvider = Provider<int>((ref) {
  final chats = ref.watch(chatsControllerProvider).value;
  if (chats == null) return 0;
  return chats.fold(0, (total, chat) => total + chat.unreadCount);
});

/// Number of pending (not yet accepted/declined) incoming contact
/// invitations - the Contacts icon's badge. Derived from the same
/// [pendingInvitationsControllerProvider] list the Requests tab itself
/// renders - not a separate invitation-tracking system.
final pendingInvitationCountProvider = Provider<int>((ref) {
  final contactInvitations = ref.watch(pendingInvitationsControllerProvider).value?.length ?? 0;
  final groupInvitations = ref.watch(pendingGroupInvitationsControllerProvider).value?.length ?? 0;
  return contactInvitations + groupInvitations;
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).value;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final token = authState is AuthAuthenticated ? authState.token : null;
    final unreadMessageCount = ref.watch(unreadMessageCountProvider);
    final pendingInvitationCount = ref.watch(pendingInvitationCountProvider);
    final chats = ref.watch(chatsControllerProvider).value;
    final dark = ref.watch(themeModeProvider) != ThemeMode.light;
    final text = Theme.of(context).textTheme;
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: AppSpacing.lg,
        title: Row(
          children: [
            const BrandMark(size: 32),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text('Web Messenger', style: text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('theme_toggle_button'),
            tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
            icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          IconButton(
            key: const Key('view_profile_button'),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
            icon: ProfileAvatar(avatarFileName: user?.avatarFileName, token: token, radius: 15, name: user?.username),
          ),
          IconButton(
            key: const Key('logout_button'),
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: AmbientBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  kToolbarHeight + AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                children: [
                  if (user != null) ...[
                    Text('Welcome, ${user.username}', style: text.headlineMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Pick up where you left off.', style: text.bodyMedium?.copyWith(color: c.textSecondary)),
                    if (!user.emailVerified) ...[const SizedBox(height: AppSpacing.lg), const _UnverifiedEmailBanner()],
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _HubCard(
                            badgeKey: const Key('view_chats_button'),
                            icon: Icons.chat_bubble_rounded,
                            tone: c.primary,
                            title: 'Chats',
                            caption: unreadMessageCount == 0 ? 'All caught up' : '$unreadMessageCount unread',
                            count: unreadMessageCount,
                            onTap: () => context.push('/chats'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _HubCard(
                            badgeKey: const Key('view_contacts_button'),
                            icon: Icons.people_rounded,
                            tone: c.accentGreen,
                            title: 'Contacts',
                            caption: pendingInvitationCount == 0
                                ? 'People & invitations'
                                : '$pendingInvitationCount pending',
                            count: pendingInvitationCount,
                            onTap: () => context.push('/contacts'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (chats != null) ...[
                    AppSectionHeader(
                      'Recent chats',
                      padding: const EdgeInsets.fromLTRB(4, 28, 4, 8),
                      trailing: chats.isEmpty
                          ? null
                          : TextButton(onPressed: () => context.push('/chats'), child: const Text('See all')),
                    ),
                    if (chats.isEmpty)
                      const AppSurface(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                          child: AppEmptyState(
                            icon: Icons.forum_rounded,
                            title: 'No chats yet',
                            message: 'Add a contact to start your first conversation.',
                            compact: true,
                          ),
                        ),
                      )
                    else
                      AppSurface(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Column(
                          children: [
                            for (final chat in chats.take(4))
                              ChatListTile(
                                tileKey: Key('home_recent_chat_${chat.id}'),
                                chat: chat,
                                token: token,
                                onTap: () => context.push('/chats/${chat.id}', extra: chat.otherUser),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A large navigation card. The [badgeKey] sits on the icon tile alone (which
/// holds only the count, when there is one) so the badge is easy to address.
class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.badgeKey,
    required this.icon,
    required this.tone,
    required this.title,
    required this.caption,
    required this.count,
    required this.onTap,
  });

  final Key badgeKey;
  final IconData icon;
  final Color tone;
  final String title;
  final String caption;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title, $caption',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.xlAll,
          side: BorderSide(color: c.divider),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          hoverColor: c.surfaceHover,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  key: badgeKey,
                  width: 60,
                  height: 52,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: c.isDark ? 0.16 : 0.14),
                          borderRadius: AppRadius.lgAll,
                        ),
                        child: Icon(icon, color: tone, size: 26),
                      ),
                      if (count > 0) Positioned(top: -6, right: 0, child: CountBadge(count: count)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(title, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(caption, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
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
    final c = context.colors;
    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderColor: c.warning.withValues(alpha: 0.4),
      color: c.warning.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_email_unread_rounded, size: 20, color: c.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Your email is not verified yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('resend_verification_button'),
              onPressed: _isSending ? null : _resend,
              child: _isSending ? const ButtonSpinner(size: 16) : const Text('Resend verification email'),
            ),
          ),
          if (_feedback != null)
            Row(
              children: [
                Icon(
                  _feedbackIsError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                  size: 16,
                  color: _feedbackIsError ? c.error : c.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _feedback!,
                    key: const Key('resend_verification_feedback'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: _feedbackIsError ? c.error : c.success),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
