import 'dart:typed_data';

/// Non-web platforms never need an in-memory object URL - media is either
/// streamed with an Authorization header or read from a real file.
String? createObjectUrl(Uint8List bytes, String mimeType) => null;

void revokeObjectUrl(String url) {}
