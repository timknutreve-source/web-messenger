import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';

/// Full-screen, pinch-to-zoom view of a chat image attachment.
class ImageViewerScreen extends ConsumerWidget {
  const ImageViewerScreen({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).value;
    final token = authState is AuthAuthenticated ? authState.token : null;

    return Scaffold(
      key: const Key('image_viewer_screen'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: token == null
            ? const CircularProgressIndicator(color: Colors.white)
            : InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  AppConfig.resolve(imageUrl),
                  headers: {'Authorization': 'Bearer $token'},
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white, key: Key('image_viewer_loading')),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      key: Key('image_viewer_error'),
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
