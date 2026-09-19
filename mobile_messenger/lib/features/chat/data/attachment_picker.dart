import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

/// Thin wrapper around [ImagePicker] so attachment-picking can be faked in
/// tests - the real [ImagePicker] talks to a platform method channel, which
/// isn't available in plain unit/widget tests without extra plumbing.
///
/// Returns [XFile]s (not `dart:io` `File`s) so the same code works on the web,
/// where a picked file has no path on disk, only in-memory bytes.
class AttachmentPicker {
  Future<XFile?> pickImage(ImageSource source) async =>
      _heldInMemoryOnWeb(await ImagePicker().pickImage(source: source, imageQuality: 90));

  Future<XFile?> pickVideo(ImageSource source) async =>
      _heldInMemoryOnWeb(await ImagePicker().pickVideo(source: source));

  /// On the web a picked file is only a `blob:` URL, read back on demand.
  /// Reading it once right away and holding the bytes makes the preview and
  /// the later upload independent of that URL staying valid.
  Future<XFile?> _heldInMemoryOnWeb(XFile? file) async {
    if (file == null || !kIsWeb) return file;
    final bytes = await file.readAsBytes();
    return XFile.fromData(bytes, name: file.name, mimeType: file.mimeType, length: bytes.length);
  }
}
