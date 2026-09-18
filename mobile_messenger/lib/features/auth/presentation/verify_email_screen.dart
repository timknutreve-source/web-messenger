import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import '../domain/auth_state.dart';

/// Reached automatically for a signed-in account whose email isn't verified
/// yet (see the redirect logic in `routing/app_router.dart`), which also
/// navigates away again the moment `user.emailVerified` becomes true - this
/// screen never needs to navigate itself on success, only update the cached
/// user via [AuthController.updateUser].
///
/// Code-based rather than link-based: the user types the 6-digit code
/// emailed to them directly into the app, so there's nothing that depends on
/// an email client recognizing a clickable link/custom URL scheme.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  bool _succeeded = false;
  String? _errorMessage;

  bool _isResending = false;
  String? _resendFeedback;
  bool _resendFeedbackIsError = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final authState = ref.read(authControllerProvider).value;
    if (authState is! AuthAuthenticated) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(authApiProvider).verifyEmail(
            authToken: authState.token,
            code: _codeController.text.trim(),
          );
      if (!mounted) return;
      // The endpoint only returns a confirmation message, not a fresh user -
      // flip the already-known field locally rather than re-fetching /me.
      // This also flips the router's redirect condition, which will
      // navigate away from this screen on its own.
      ref.read(authControllerProvider.notifier).updateUser(
            authState.user.copyWith(emailVerified: true),
          );
      setState(() {
        _isSubmitting = false;
        _succeeded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = presentError(e).message;
      });
    }
  }

  Future<void> _resend() async {
    final authState = ref.read(authControllerProvider).value;
    if (_isResending || authState is! AuthAuthenticated) return;

    setState(() {
      _isResending = true;
      _resendFeedback = null;
    });
    try {
      final message = await ref.read(authApiProvider).resendVerification(authState.token);
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _resendFeedback = message;
        _resendFeedbackIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _resendFeedback = presentError(e).message;
        _resendFeedbackIsError = true;
      });
    }
  }

  String? _validateCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Verification code is required';
    if (!RegExp(r'^\d{6}$').hasMatch(trimmed)) return 'Enter the 6-digit code';
    return null;
  }

  /// This screen is only ever reached via the router's forced redirect (see
  /// the class doc) rather than a normal push, so there is typically nothing
  /// on the navigation stack to pop back to - a plain back arrow would do
  /// nothing, or on Android could pop the entire app. The only "previous
  /// screen" that actually makes sense here is login: ending the session
  /// (the same [AuthController.logout] the home screen's own logout button
  /// uses) flips auth state to unauthenticated, which the router's redirect
  /// then sends to '/login' on its own - never back to this screen, since
  /// there is no longer a signed-in-but-unverified user to redirect.
  Future<void> _exitVerification() async {
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not just read-on-submit) so the provider is already resolved
    // by the time the user can interact with the form - this screen is only
    // ever reached once authenticated (see the router), so this never
    // actually renders anything conditionally on it, but eagerly ties this
    // widget's lifecycle to the auth state it depends on.
    ref.watch(authControllerProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitVerification();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('verify_email_back_button'),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _exitVerification,
          ),
          title: const Text('Verify your email'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _succeeded ? _buildSuccessView(context) : _buildFormView(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    return Column(
      key: const Key('verify_email_success_view'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text('Your email has been verified.', textAlign: TextAlign.center),
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
          Text('Verify your email', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('We sent a verification code to your email address.'),
          const SizedBox(height: 24),
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                key: const Key('verify_email_error_message'),
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('verify_email_code_field'),
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Verification code',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textInputAction: TextInputAction.done,
            maxLength: 6,
            validator: _validateCode,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('verify_email_submit_button'),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Verify email'),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              key: const Key('verify_email_resend_button'),
              onPressed: _isResending ? null : _resend,
              child: _isResending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Resend code'),
            ),
          ),
          if (_resendFeedback != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _resendFeedback!,
                key: const Key('verify_email_resend_feedback'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _resendFeedbackIsError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
