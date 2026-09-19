import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Thin wrapper around [AudioRecorder] so voice-message recording can be
/// faked in tests - the real recorder talks to a platform method channel
/// (and the OS microphone permission dialog), neither of which is available
/// in plain unit/widget tests without extra plumbing (same reasoning as
/// [AttachmentPicker] wrapping `image_picker`).
///
/// Records mono, 16kHz WAV specifically - see `AttachmentValidator`'s
/// Javadoc on the backend for why WAV (not the smaller AAC-in-M4A default)
/// was chosen: its magic bytes are unambiguous against the video-detection
/// logic that already exists there, at the cost of a larger file for the
/// same duration - acceptable for short voice messages.
class AudioRecorderService {
  AudioRecorderService([AudioRecorder? recorder]) : _providedRecorder = recorder;

  // The real AudioRecorder() constructor eagerly touches a platform method
  // channel, so it's only ever created lazily, on first actual use - a fake
  // subclass overriding every method below never triggers it, exactly like
  // AttachmentPicker never constructs a real ImagePicker in tests.
  final AudioRecorder? _providedRecorder;
  AudioRecorder? _lazyRecorder;
  AudioRecorder get _recorder => _providedRecorder ?? (_lazyRecorder ??= AudioRecorder());

  String? _currentPath;

  /// Requests the microphone permission if not already granted (prompting
  /// the OS dialog the first time), returning whether recording may proceed.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording to a fresh temporary file. Throws if a recording is
  /// already in progress or the permission was denied - callers are
  /// expected to check [hasPermission] first for a clean user-facing error
  /// rather than relying on this throwing.
  Future<void> start() async {
    // On the web there is no file system to record into: the recorder keeps
    // the audio in memory and hands back a blob URL when stopped, so the
    // `path` argument is ignored there (and path_provider is unsupported).
    final path = kIsWeb ? '' : await _newTemporaryPath();
    _currentPath = kIsWeb ? null : path;
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
  }

  Future<String> _newTemporaryPath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/voice-message-${DateTime.now().microsecondsSinceEpoch}.wav';
  }

  /// Stops recording and returns the finished file, or `null` if nothing
  /// was recorded (e.g. [start] was never called, or it failed silently).
  Future<XFile?> stop() async {
    final resultPath = await _recorder.stop();
    _currentPath = null;
    if (resultPath == null) return null;
    return XFile(resultPath, name: 'voice-message.wav', mimeType: 'audio/wav');
  }

  /// Stops recording and discards the file - used when the user cancels
  /// instead of sending.
  Future<void> cancel() async {
    await _recorder.cancel();
    final path = _currentPath;
    _currentPath = null;
    if (!kIsWeb && path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void dispose() {
    // Uses the already-created instance directly (never the _recorder
    // getter) so disposing never lazily constructs one just to dispose it.
    (_providedRecorder ?? _lazyRecorder)?.dispose();
  }
}
