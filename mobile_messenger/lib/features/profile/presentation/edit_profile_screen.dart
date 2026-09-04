import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/error_presenter.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_validators.dart';
import '../profile_providers.dart';
import 'profile_validators.dart';
import 'widgets/profile_avatar.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _aboutMeController;

  File? _pickedImage;
  String? _imageError;
  String? _generalError;
  Map<String, String> _fieldErrors = const {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(profileControllerProvider).requireValue;
    _usernameController = TextEditingController(text: user.username);
    _emailController = TextEditingController(text: user.email);
    _aboutMeController = TextEditingController(text: user.aboutMe ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _aboutMeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _imageError = null);

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    } catch (_) {
      setState(() => _imageError = 'Could not open the photo picker.');
      return;
    }
    if (picked == null) return; // user cancelled selection

    final file = File(picked.path);
    final extension = picked.path.split('.').last;
    final sizeBytes = await file.length();
    final validationError = ProfileValidators.pickedImage(
      fileExtension: extension,
      sizeBytes: sizeBytes,
    );
    if (validationError != null) {
      setState(() => _imageError = validationError);
      return;
    }

    setState(() {
      _pickedImage = file;
      _imageError = null;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;

    setState(() {
      _generalError = null;
      _fieldErrors = const {};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    final controller = ref.read(profileControllerProvider.notifier);

    await controller.updateProfile(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      aboutMe: _aboutMeController.text.trim(),
    );

    if (!mounted) return;
    var state = ref.read(profileControllerProvider);
    if (state.hasError) {
      final presentation = presentError(state.error!);
      setState(() {
        _isSaving = false;
        _generalError = presentation.message;
        _fieldErrors = presentation.fieldErrors;
      });
      return;
    }

    final image = _pickedImage;
    if (image != null) {
      await controller.uploadAvatar(image);
      if (!mounted) return;
      state = ref.read(profileControllerProvider);
      if (state.hasError) {
        setState(() {
          _isSaving = false;
          _generalError = presentError(state.error!).message;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
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
                  Center(
                    child: Column(
                      children: [
                        _pickedImage != null
                            ? CircleAvatar(
                                radius: 56,
                                backgroundImage: FileImage(_pickedImage!),
                              )
                            : ProfileAvatar(
                                avatarFileName: ref.watch(profileControllerProvider).value?.avatarFileName,
                                token: token,
                                radius: 56,
                              ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          key: const Key('edit_profile_change_photo_button'),
                          onPressed: _isSaving ? null : _pickImage,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Change Photo'),
                        ),
                        if (_imageError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _imageError!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('edit_profile_username_field'),
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
                    key: const Key('edit_profile_email_field'),
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
                    key: const Key('edit_profile_aboutMe_field'),
                    controller: _aboutMeController,
                    decoration: InputDecoration(
                      labelText: 'About Me',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      errorText: _fieldErrors['aboutMe'],
                    ),
                    minLines: 3,
                    maxLines: 6,
                    maxLength: ProfileValidators.aboutMeMaxLength,
                    validator: ProfileValidators.aboutMe,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('edit_profile_save_button'),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
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
