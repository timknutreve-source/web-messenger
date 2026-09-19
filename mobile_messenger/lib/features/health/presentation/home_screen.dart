import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
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
    final unreadMessageCount = ref.watch(unreadMessageCountProvider);
    final pendingInvitationCount = ref.watch(pendingInvitationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Messenger'),
        actions: [
          _BadgedIconButton(
            key: const Key('view_chats_button'),
            tooltip: 'Chats',
            onPressed: () => context.push('/chats'),
            icon: const Icon(Icons.chat_bubble_outline),
            count: unreadMessageCount,
          ),
          _BadgedIconButton(
            key: const Key('view_contacts_button'),
            tooltip: 'Contacts',
            onPressed: () => context.push('/contacts'),
            icon: const Icon(Icons.people_outline),
            count: pendingInvitationCount,
          ),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// An [IconButton] with a small numeric badge in its corner when [count] is
/// greater than zero (and none at all when it's zero) - e.g. `1`, `2`, `3`,
/// matching the platform's usual notification-count convention.
class _BadgedIconButton extends StatelessWidget {
  const _BadgedIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.count,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: icon,
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
