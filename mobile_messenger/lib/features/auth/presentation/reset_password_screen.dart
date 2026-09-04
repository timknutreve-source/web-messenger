import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import 'auth_validators.dart';
import 'widgets/password_requirements_list.dart';

/// Reached via the password reset email's deep link (`/reset-password?token=...`),
/// which supplies [token]. There's no in-app manual-entry fallback for a
/// missing token - without one there's nothing this screen can meaningfully do,
/// so it shows a clear error pointing back to the forgot-password flow instead.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;
  bool _succeeded = false;
  String? _generalError;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = widget.token;
    if (_isSubmitting || token == null) return;

    setState(() => _generalError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(authApiProvider).resetPassword(
            token: token,
            newPassword: _passwordController.text,
          );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _succeeded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _generalError = presentError(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.token == null) {
      return _MessageView(
        icon: Icons.error_outline,
        iconColor: Theme.of(context).colorScheme.error,
        message: 'This password reset link is missing or invalid.',
        actionLabel: 'Request a new link',
        onAction: () => context.go('/forgot-password'),
      );
    }

    if (_succeeded) {
      return _MessageView(
        key: const Key('reset_password_success_view'),
        icon: Icons.check_circle_outline,
        iconColor: Theme.of(context).colorScheme.primary,
        message: 'Your password has been reset. You can now log in.',
        actionLabel: 'Back to login',
        onAction: () => context.go('/login'),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_generalError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _generalError!,
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('reset_password_new_password_field'),
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'New password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            textInputAction: TextInputAction.next,
            validator: AuthValidators.password,
          ),
          const SizedBox(height: 8),
          PasswordRequirementsList(password: _passwordController.text),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('reset_password_confirm_password_field'),
            controller: _confirmController,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            textInputAction: TextInputAction.done,
            validator: AuthValidators.confirmPassword(() => _passwordController.text),
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('reset_password_submit_button'),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Reset password'),
          ),
        ],
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: iconColor),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
