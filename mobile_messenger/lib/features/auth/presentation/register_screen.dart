import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_presenter.dart';
import '../auth_providers.dart';
import 'auth_validators.dart';
import 'widgets/password_requirements_list.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_surface.dart';
import 'widgets/app_password_field.dart';
import 'widgets/auth_scaffold.dart';

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

    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Join in a minute. We will email you a code to verify it is you.',
      child: Form(
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
              key: const Key('register_username_field'),
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.alternate_email_rounded),
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
                prefixIcon: const Icon(Icons.mail_outline_rounded),
                errorText: _fieldErrors['email'],
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 16),
            AppPasswordField(
              fieldKey: const Key('register_password_field'),
              controller: _passwordController,
              labelText: 'Password',
              errorText: _fieldErrors['password'],
              textInputAction: TextInputAction.next,
              validator: AuthValidators.password,
            ),
            const SizedBox(height: 12),
            PasswordRequirementsList(password: _passwordController.text),
            const SizedBox(height: 16),
            AppPasswordField(
              fieldKey: const Key('register_confirmPassword_field'),
              controller: _confirmPasswordController,
              labelText: 'Confirm password',
              textInputAction: TextInputAction.done,
              validator: AuthValidators.confirmPassword(() => _passwordController.text),
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('register_submit_button'),
              onPressed: isLoading ? null : _submit,
              child: isLoading ? const ButtonSpinner() : const Text('Register'),
            ),
            const SizedBox(height: 12),
            TextButton(
              key: const Key('register_go_to_login_button'),
              onPressed: isLoading ? null : () => context.canPop() ? context.pop() : context.go('/login'),
              child: const Text('Already have an account? Log in'),
            ),
          ],
        ),
      ),
    );
  }
}
