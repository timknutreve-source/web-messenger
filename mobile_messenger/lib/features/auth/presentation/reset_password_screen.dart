import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import 'auth_validators.dart';
import 'widgets/password_requirements_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_surface.dart';
import 'widgets/app_password_field.dart';
import 'widgets/auth_scaffold.dart';

/// Reached from [ForgotPasswordScreen] after it successfully requests a
/// reset, carrying [email] along (as `extra`) so this screen knows which
/// account the 6-digit code the user is about to enter belongs to. There's
/// no in-app fallback for a missing email - without one there's nothing this
/// screen can meaningfully do, so it shows a clear error pointing back to
/// the forgot-password flow instead.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String? email;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
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
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = widget.email;
    if (_isSubmitting || email == null) return;

    setState(() => _generalError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(authApiProvider).resetPassword(
            email: email,
            code: _codeController.text.trim(),
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

  String? _validateCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Verification code is required';
    if (!RegExp(r'^\d{6}$').hasMatch(trimmed)) return 'Enter the 6-digit code';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Choose a new password',
      subtitle: widget.email != null && !_succeeded
          ? 'Enter the verification code we emailed you, then choose a new password.'
          : null,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final c = context.colors;
    if (widget.email == null) {
      return _MessageView(
        icon: Icons.error_outline_rounded,
        tone: c.error,
        toneSoft: c.errorSoft,
        message: 'This password reset session is missing or invalid.',
        actionLabel: 'Request a new code',
        onAction: () => context.go('/forgot-password'),
      );
    }

    if (_succeeded) {
      return _MessageView(
        key: const Key('reset_password_success_view'),
        icon: Icons.check_circle_outline_rounded,
        tone: c.success,
        toneSoft: c.successSoft,
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
            AppBanner(message: _generalError!),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('reset_password_code_field'),
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Verification code',
              prefixIcon: Icon(Icons.pin_outlined),
              counterText: '',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            maxLength: 6,
            textInputAction: TextInputAction.next,
            validator: _validateCode,
          ),
          const SizedBox(height: 16),
          AppPasswordField(
            fieldKey: const Key('reset_password_new_password_field'),
            controller: _passwordController,
            labelText: 'New password',
            textInputAction: TextInputAction.next,
            validator: AuthValidators.password,
          ),
          const SizedBox(height: 12),
          PasswordRequirementsList(password: _passwordController.text),
          const SizedBox(height: 16),
          AppPasswordField(
            fieldKey: const Key('reset_password_confirm_password_field'),
            controller: _confirmController,
            labelText: 'Confirm new password',
            textInputAction: TextInputAction.done,
            validator: AuthValidators.confirmPassword(() => _passwordController.text),
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('reset_password_submit_button'),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting ? const ButtonSpinner() : const Text('Reset password'),
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
    required this.tone,
    required this.toneSoft,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color tone;
  final Color toneSoft;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: toneSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tone.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, size: 30, color: tone),
          ),
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
