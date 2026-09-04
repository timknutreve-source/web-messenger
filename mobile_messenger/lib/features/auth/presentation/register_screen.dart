import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import 'auth_validators.dart';
import 'widgets/password_requirements_list.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _generalError;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _generalError = null;
      _fieldErrors = const {};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref.read(authControllerProvider.notifier).register(
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    if (state.hasError) {
      final presentation = presentError(state.error!);
      setState(() {
        _generalError = presentation.message;
        _fieldErrors = presentation.fieldErrors;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
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
                    key: const Key('register_username_field'),
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      border: const OutlineInputBorder(),
                      errorText: _fieldErrors['username'],
                    ),
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.username,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('register_email_field'),
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: const OutlineInputBorder(),
                      errorText: _fieldErrors['email'],
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.email,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('register_password_field'),
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      errorText: _fieldErrors['password'],
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.password,
                  ),
                  const SizedBox(height: 8),
                  PasswordRequirementsList(password: _passwordController.text),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('register_confirmPassword_field'),
                    controller: _confirmPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: AuthValidators.confirmPassword(() => _passwordController.text),
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('register_submit_button'),
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Register'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    key: const Key('register_go_to_login_button'),
                    onPressed: isLoading ? null : () => context.go('/login'),
                    child: const Text('Already have an account? Log in'),
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
