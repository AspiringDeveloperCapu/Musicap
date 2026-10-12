import 'package:flutter/foundation.dart';
import 'package:music_player/models/track.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolves playable audio URLs for tracks.
///
/// Hybrid architecture: track metadata comes from the backend, but the
/// actual googlevideo stream URL is resolved on-device with
/// youtube_explode_dart whenever possible. Falls back to the backend's
/// `/api/stream` proxy on web, for demo tracks (no videoId), and whenever
/// device-side resolution fails — so playback keeps working either way.
class StreamResolver {
  StreamResolver._();

  static final StreamResolver instance = StreamResolver._();

  /// googlevideo URLs stay valid for hours; re-resolve well before that.
  static const _cacheTtl = Duration(minutes: 50);

  /// Avoid stalling playback on a hung YouTube request.
  static const _resolveTimeout = Duration(seconds: 12);

  /// Don't hammer YouTube when resolution just failed.
  static const _failureBackoff = Duration(seconds: 60);

  final Map<String, _CachedUrl> _cache = {};
  YoutubeExplode? _yt;

  /// Returns the best playable audio URL for [track].
  /// Never throws — always falls back to the track's backend URL.
  Future<String> resolve(Track track) async {
    final videoId = track.videoId;
    if (kIsWeb || videoId == null || videoId.isEmpty) {
      return track.audioUrl;
    }

    final now = DateTime.now();
    final cached = _cache[videoId];
    if (cached != null) {
      if (now.isBefore(cached.expiresAt)) {
        // Failure marker during backoff — skip straight to the fallback.
        return cached.isFailure ? track.audioUrl : cached.url;
      }
      _cache.remove(videoId);
    }

    try {
      final url = await _resolve(videoId).timeout(_resolveTimeout);
      _store(videoId, _CachedUrl(url, now.add(_cacheTtl)));
      return url;
    } catch (_) {
      _store(videoId, _CachedUrl('', now.add(_failureBackoff)));
      return track.audioUrl;
    }
  }

  /// Resolves every track in [tracks] in parallel (used when a whole
  /// queue is loaded). Failed entries fall back to their backend URL.
  Future<List<String>> resolveAll(List<Track> tracks) =>
      Future.wait(tracks.map(resolve));

  Future<String> _resolve(String videoId) async {
    final yt = _yt ??= YoutubeExplode();
    final manifest = await yt.videos.streamsClient.getManifest(videoId);

    // Prefer standalone audio streams; muxed (audio+video) as a last resort.
    // Within each group prefer unthrottled streams so downloads aren't slow.
    final audioOnly = manifest.audioOnly;
    if (audioOnly.isNotEmpty) {
      final unthrottled = audioOnly.where((s) => !s.isThrottled);
      final pick = unthrottled.isNotEmpty ? unthrottled : audioOnly;
      return pick.withHighestBitrate().url.toString();
    }
    final muxed = manifest.muxed;
    if (muxed.isNotEmpty) {
      return muxed.withHighestBitrate().url.toString();
    }
    throw StateError('No playable streams for $videoId');
  }

  void _store(String videoId, _CachedUrl entry) {
    _cache[videoId] = entry;
    final now = DateTime.now();
    _cache.removeWhere((_, e) => now.isAfter(e.expiresAt));
  }
}

class _CachedUrl {
  final String url;
  final DateTime expiresAt;

  /// An empty [url] is a failure marker (during backoff [resolve]
  /// treats it as a miss and returns the backend fallback directly).
  const _CachedUrl(this.url, this.expiresAt);

  bool get isFailure => url.isEmpty;
}
