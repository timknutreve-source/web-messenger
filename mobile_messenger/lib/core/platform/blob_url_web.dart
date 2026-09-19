import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Wraps [bytes] in a browser `blob:` URL.
///
/// Needed because a browser `<video>` element cannot send an Authorization
/// header, yet every attachment download requires one: the bytes are fetched
/// with the app's authenticated HTTP client instead and handed to the player
/// through this local URL. The trade-off is that a video is fully downloaded
/// before it starts playing, rather than streamed with range requests.
String? createObjectUrl(Uint8List bytes, String mimeType) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  return web.URL.createObjectURL(blob);
}

void revokeObjectUrl(String url) => web.URL.revokeObjectURL(url);
