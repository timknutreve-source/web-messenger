import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';

/// Plays a voice message attachment.
///
/// `audioplayers`' network [UrlSource] has no way to attach a custom
/// `Authorization` header, but every attachment download requires one (see
/// the backend's participant-only authorization check) - so this fetches
/// the audio bytes itself, authenticated exactly like any other API call
/// (the same `Dio` instance, same bearer header), and hands the already-
/// decrypted, already-downloaded bytes to the player via [BytesSource]
/// instead of letting the player fetch the URL directly. The trade-off is
/// that playback only starts once the whole (short) voice message has
/// downloaded, rather than streaming progressively - acceptable for voice
/// messages, which are seconds to a few minutes long, not full videos.
class ChatAudioPlayer {
  ChatAudioPlayer(this._dio, [AudioPlayer? player]) : _providedPlayer = player;

  final Dio _dio;

  // Real AudioPlayer() construction eagerly touches a platform channel, so
  // it's only ever created lazily on first actual use - a fake subclass
  // overriding every method below never triggers it (same reasoning as
  // AudioRecorderService).
  final AudioPlayer? _providedPlayer;
  AudioPlayer? _lazyPlayer;
  AudioPlayer get _player => _providedPlayer ?? (_lazyPlayer ??= AudioPlayer());

  Stream<Duration> get onPositionChanged => _player.onPositionChanged;
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  Future<void> playFromUrl(String url, String token) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    await _player.play(BytesSource(Uint8List.fromList(response.data ?? const [])));
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() => _player.resume();

  Future<void> dispose() async {
    // Never invokes the _player getter - disposing must not lazily
    // construct a real player just to immediately tear it down.
    await (_providedPlayer ?? _lazyPlayer)?.dispose();
  }
}
