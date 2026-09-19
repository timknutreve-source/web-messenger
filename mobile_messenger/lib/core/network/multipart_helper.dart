import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;

/// Builds a multipart upload part from a picked/recorded [XFile], in the one
/// way that works on every platform.
///
/// On mobile the file is streamed straight from disk (so a 50MB video is
/// never held in memory). On the web there is no file system - an [XFile]
/// there is backed by an in-memory blob - so its bytes are read instead.
/// Either way the server never trusts the filename or content type it is
/// given: it identifies the real format from the file's own bytes.
Future<MultipartFile> multipartFromXFile(XFile file) async {
  if (kIsWeb) {
    return MultipartFile.fromBytes(await file.readAsBytes(), filename: _safeName(file));
  }
  return MultipartFile.fromFile(file.path, filename: _safeName(file));
}

String _safeName(XFile file) {
  final name = file.name;
  return name.isEmpty ? 'upload' : name;
}
