import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import 'auth_validators.dart';

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
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Log in')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Mobile Messenger', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 32),
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
                    key: const Key('login_usernameOrEmail_field'),
                    controller: _usernameOrEmailController,
                    decoration: const InputDecoration(
                      labelText: 'Username or email',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        AuthValidators.required(value, fieldName: 'Username or email'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('login_password_field'),
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
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
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('login_submit_button'),
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Log in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    key: const Key('login_go_to_register_button'),
                    onPressed: isLoading ? null : () => context.go('/register'),
                    child: const Text("Don't have an account? Register"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
