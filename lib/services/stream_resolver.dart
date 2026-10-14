import 'package:flutter/foundation.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/services/music_api.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'stream_proxy_stub.dart'
    if (dart.library.io) 'stream_proxy.dart';

/// Resolves playable audio URLs for tracks.
///
/// Track metadata comes from the backend (web/desktop) or on-device
/// YouTube clients (Android), but the actual googlevideo stream URL is
/// always resolved on-device with youtube_explode_dart whenever a video
/// ID exists. Local files play directly; web falls back to the backend's
/// `/api/stream` proxy; on serverless Android a resolution failure
/// throws so the error surfaces to the user instead of a dead URL.
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
  ///
  /// Local files pass through untouched; platforms with a backend fall
  /// back to [Track.audioUrl] on failure; on serverless Android resolution
  /// failures throw (the player surfaces them as playback errors).
  Future<String> resolve(Track track) async {
    // Offline downloads: play the saved file as-is.
    if (track.audioUrl.startsWith('file:')) return track.audioUrl;

    final videoId = track.videoId;
    if (kIsWeb || videoId == null || videoId.isEmpty) {
      return track.audioUrl;
    }

    final now = DateTime.now();
    String? url;
    final cached = _cache[videoId];
    if (cached != null) {
      if (now.isBefore(cached.expiresAt)) {
        // Failure marker during backoff — skip straight to the fallback.
        if (cached.isFailure) {
          if (usesBackend) return track.audioUrl;
          throw StateError('Stream for $videoId unavailable (backing off)');
        }
        url = cached.url;
      } else {
        _cache.remove(videoId);
      }
    }

    if (url == null) {
      try {
        url = await _resolve(videoId).timeout(_resolveTimeout);
        _store(videoId, _CachedUrl(url, now.add(_cacheTtl)));
      } catch (e) {
        _store(videoId, _CachedUrl('', now.add(_failureBackoff)));
        if (usesBackend) return track.audioUrl;
        rethrow;
      }
    }

    // googlevideo rejects the open-ended byte ranges ExoPlayer sends
    // (both for loading and for seeking), so the stream is served through
    // a loopback relay that converts them to bounded ranges.
    return StreamProxy.instance.relay(url, key: videoId);
  }

  /// Resolves every track in [tracks] with bounded parallelism. YouTube
  /// rate-limits mass parallel manifest fetches (large queues otherwise
  /// time out wholesale), so only a few are in flight at once. Failed
  /// entries fall back to their backend URL (or throw on serverless
  /// platforms).
  Future<List<String>> resolveAll(List<Track> tracks) async {
    const workers = 3;
    final urls = List<String?>.filled(tracks.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < tracks.length) {
        final i = next++;
        urls[i] = await resolve(tracks[i]);
      }
    }

    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    return urls.cast<String>();
  }

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
  /// falls back to the track's URL, or throws on serverless platforms).
  const _CachedUrl(this.url, this.expiresAt);

  bool get isFailure => url.isEmpty;
}
