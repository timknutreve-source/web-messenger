import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import 'auth_validators.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_surface.dart';
import 'widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;
  String? _generalError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _generalError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      // The backend deliberately returns the same generic message whether or
      // not the address is registered - we show it as-is rather than
      // inventing our own, so there's exactly one message to keep in sync.
      await ref.read(authApiProvider).forgotPassword(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitted = true;
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
    return AuthScaffold(
      title: 'Forgot password?',
      subtitle: _submitted ? null : "It happens. Enter your email and we'll send you a 6-digit code to reset it.",
      child: _submitted ? _buildSuccessView(context) : _buildFormView(context),
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: c.successSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.success.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.mark_email_read_outlined, size: 30, color: c.success),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          key: Key('forgot_password_success_message'),
          'If that email is registered, password reset instructions have been sent.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('forgot_password_enter_code_button'),
          onPressed: () => context.push('/reset-password', extra: _emailController.text.trim()),
          child: const Text('Enter code'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('forgot_password_back_to_login_button'),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Back to login'),
        ),
      ],
    );
  }

  Widget _buildFormView(BuildContext context) {
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
            key: const Key('forgot_password_email_field'),
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: AuthValidators.email,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 22),
          FilledButton(
            key: const Key('forgot_password_submit_button'),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting ? const ButtonSpinner() : const Text('Send reset link'),
          ),
        ],
      ),
    );
  }
}
