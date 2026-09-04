import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import '../domain/auth_state.dart';

enum _VerifyStatus { verifying, succeeded, failed, missingToken }

/// Reached via the verification email's deep link (`/verify-email?token=...`).
/// Auto-verifies on load - there's nothing for the user to fill in, so this
/// screen is a pure loading -> result flow, reachable whether or not the
/// user happens to already be logged in.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  _VerifyStatus _status = _VerifyStatus.verifying;
  String _errorMessage = '';
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final token = widget.token;
    if (token == null) {
      setState(() => _status = _VerifyStatus.missingToken);
      return;
    }
    _verify(token);
  }

  Future<void> _verify(String token) async {
    try {
      await ref.read(authApiProvider).verifyEmail(token);
      if (!mounted) return;
      setState(() => _status = _VerifyStatus.succeeded);
      await _refreshCachedUserIfLoggedIn();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _VerifyStatus.failed;
        _errorMessage = presentError(e).message;
      });
    }
  }

  /// If the user happens to already be logged in, refresh their cached
  /// profile so the "unverified" banner on the home screen clears
  /// immediately, without requiring them to log out and back in.
  Future<void> _refreshCachedUserIfLoggedIn() async {
    final authState = ref.read(authControllerProvider).value;
    if (authState is! AuthAuthenticated) return;
    try {
      final freshUser = await ref.read(authApiProvider).fetchCurrentUser(authState.token);
      ref.read(authControllerProvider.notifier).updateUser(freshUser);
    } catch (_) {
      // Non-critical - the banner will simply catch up next time /me is called.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify email')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_status) {
      case _VerifyStatus.verifying:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Verifying your email...'),
          ],
        );
      case _VerifyStatus.succeeded:
        return Column(
          key: const Key('verify_email_success_view'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('Your email has been verified.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Continue'),
            ),
          ],
        );
      case _VerifyStatus.failed:
        return Column(
          key: const Key('verify_email_error_view'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(_errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Text(
              'If your link expired, you can request a new one from the home screen after logging in.',
              textAlign: TextAlign.center,
            ),
          ],
        );
      case _VerifyStatus.missingToken:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40),
            SizedBox(height: 16),
            Text('This verification link is missing or invalid.', textAlign: TextAlign.center),
          ],
        );
    }
  }
}
