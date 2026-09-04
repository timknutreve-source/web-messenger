import 'package:flutter/material.dart';

import '../../../../core/config/app_config.dart';

/// Renders the user's avatar, or a bundled icon placeholder if they haven't
/// uploaded one (or if it fails to load) - so the UI never shows a broken
/// image and every new user has a usable default avatar with nothing to
/// store per-user until they actually upload a photo.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.avatarFileName,
    required this.token,
    this.radius = 40,
  });

  final String? avatarFileName;
  final String? token;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fileName = avatarFileName;
    final authToken = token;
    if (fileName == null || authToken == null) {
      return _placeholder(context);
    }

    final diameter = radius * 2;
    return ClipOval(
      child: Image.network(
        AppConfig.avatarUrl(fileName),
        headers: {'Authorization': 'Bearer $authToken'},
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: diameter,
            height: diameter,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      child: Icon(Icons.person, size: radius, color: colorScheme.onPrimaryContainer),
    );
  }
}
