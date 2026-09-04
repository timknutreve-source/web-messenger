import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import 'auth_validators.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _submitted ? _buildSuccessView(context) : _buildFormView(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text(
          key: Key('forgot_password_success_message'),
          'If that email is registered, password reset instructions have been sent.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
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
          const Text(
            "Enter your account's email address and we'll send you a link to reset your password.",
          ),
          const SizedBox(height: 24),
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
            key: const Key('forgot_password_email_field'),
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: AuthValidators.email,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('forgot_password_submit_button'),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send reset link'),
          ),
        ],
      ),
    );
  }
}
