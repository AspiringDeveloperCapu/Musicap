import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// The single shared [YoutubeExplode] session for every on-device
/// YouTube call (search, suggestions, related music, stream
/// resolution). One consistent session per device — same visitor, pool
/// and challenge state — looks far more like a regular YouTube user
/// than several short-lived ones, which keeps the anonymous rate
/// limits at arm's length.
///
/// Sessions are dropped (and a clean one created on next use) whenever
/// a request hangs or a rate limit trips, so a poisoned connection pool
/// never lingers across callers.
class YoutubeClientPool {
  YoutubeClientPool._();

  static final YoutubeClientPool instance = YoutubeClientPool._();

  YoutubeExplode? _yt;

  /// The shared session, created on first use and after every [reset].
  YoutubeExplode use() => _yt ??= YoutubeExplode();

  /// Drops the current session. The next [use] builds a fresh one.
  void reset() {
    final old = _yt;
    _yt = null;
    try {
      old?.close();
    } catch (_) {
      // Close failures don't matter — the session is discarded anyway.
    }
  }
}
