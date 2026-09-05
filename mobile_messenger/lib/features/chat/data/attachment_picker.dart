import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// Thin wrapper around [ImagePicker] so attachment-picking can be faked in
/// tests - the real [ImagePicker] talks to a platform method channel, which
/// isn't available in plain unit/widget tests without extra plumbing.
class AttachmentPicker {
  Future<File?> pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    return picked == null ? null : File(picked.path);
  }

  Future<File?> pickVideo(ImageSource source) async {
    final picked = await ImagePicker().pickVideo(source: source);
    return picked == null ? null : File(picked.path);
  }
}
