import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import '../domain/auth_state.dart';
import 'auth_validators.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_surface.dart';
import 'widgets/app_password_field.dart';
import 'widgets/auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameOrEmailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _generalError;

  @override
  void dispose() {
    _usernameOrEmailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _generalError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref.read(authControllerProvider.notifier).login(
          usernameOrEmail: _usernameOrEmailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    if (state.hasError) {
      setState(() => _generalError = presentError(state.error!).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authControllerProvider);
    final isLoading = authAsync.isLoading;
    final sessionExpired = authAsync.value is AuthUnauthenticated &&
        (authAsync.value as AuthUnauthenticated).sessionExpired;

    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Log in to pick up where you left off.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sessionExpired && _generalError == null) ...[
              const KeyedSubtree(
                key: Key('session_expired_banner'),
                child: AppBanner(
                  tone: AppBannerTone.warning,
                  icon: Icons.schedule_rounded,
                  message: 'Your session has expired. Please log in again.',
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_generalError != null) ...[
              AppBanner(message: _generalError!),
              const SizedBox(height: 16),
            ],
            TextFormField(
              key: const Key('login_usernameOrEmail_field'),
              controller: _usernameOrEmailController,
              decoration: const InputDecoration(
                labelText: 'Username or email',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              validator: (value) => AuthValidators.required(value, fieldName: 'Username or email'),
            ),
            const SizedBox(height: 16),
            AppPasswordField(
              fieldKey: const Key('login_password_field'),
              controller: _passwordController,
              labelText: 'Password',
              textInputAction: TextInputAction.done,
              validator: (value) => AuthValidators.required(value, fieldName: 'Password'),
              onFieldSubmitted: (_) => _submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('login_forgot_password_button'),
                onPressed: isLoading ? null : () => context.push('/forgot-password'),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 6),
            FilledButton(
              key: const Key('login_submit_button'),
              onPressed: isLoading ? null : _submit,
              child: isLoading ? const ButtonSpinner() : const Text('Log in'),
            ),
            const SizedBox(height: 14),
            TextButton(
              key: const Key('login_go_to_register_button'),
              onPressed: isLoading ? null : () => context.push('/register'),
              child: const Text("Don't have an account? Register"),
            ),
          ],
        ),
      ),
    );
  }
}
