import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/platform/blob_url.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_state.dart';

/// Plays a chat video attachment, streamed from the backend (which supports
/// HTTP range requests, so playback can start and seek without downloading
/// the whole file first).
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  Object? _error;
  String? _objectUrl;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final authState = await ref.read(authControllerProvider.future);
      if (authState is! AuthAuthenticated) return;

      final controller = await _createController(authState.token);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// Native platforms stream the video with an Authorization header (and so
  /// support seeking via range requests). A browser `<video>` element cannot
  /// send that header, so on the web the bytes are fetched through the
  /// authenticated HTTP client and played from a local blob URL instead.
  Future<VideoPlayerController> _createController(String token) async {
    final url = AppConfig.resolve(widget.videoUrl);
    if (!kIsWeb) {
      return VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: {'Authorization': 'Bearer $token'});
    }
    final response = await ref.read(dioProvider).get<List<int>>(
          widget.videoUrl,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Authorization': 'Bearer $token'},
            receiveTimeout: AppConfig.uploadSendTimeout,
          ),
        );
    final blobUrl = createObjectUrl(Uint8List.fromList(response.data ?? const []), 'video/mp4');
    if (blobUrl == null) throw StateError('Could not create a playable URL for this video');
    _objectUrl = blobUrl;
    return VideoPlayerController.networkUrl(Uri.parse(blobUrl));
  }

  @override
  void dispose() {
    _controller?.dispose();
    final url = _objectUrl;
    if (url != null) revokeObjectUrl(url);
    super.dispose();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      key: const Key('video_player_screen'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _error != null
            ? const Icon(
                Icons.error_outline,
                key: Key('video_player_error'),
                color: Colors.white54,
                size: 64,
              )
            : controller == null
                ? const CircularProgressIndicator(color: Colors.white, key: Key('video_player_loading'))
                : AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: GestureDetector(
                      key: const Key('video_player_surface'),
                      onTap: _togglePlayback,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(controller),
                          if (!controller.value.isPlaying)
                            const Icon(Icons.play_arrow, color: Colors.white70, size: 72),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
