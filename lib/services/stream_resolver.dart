import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/services/music_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'stream_proxy_stub.dart'
    if (dart.library.io) 'stream_proxy.dart';

/// User-facing playback resolution failure. [toString] is the message
/// shown to the user, without exception-class noise.
class ResolveException implements Exception {
  final String message;
  ResolveException(this.message);
  @override
  String toString() => message;
}

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

  /// Avoid stalling playback on a hung YouTube request. Mobile networks
  /// need more headroom than an emulator on LAN.
  static const _resolveTimeout = Duration(seconds: 20);

  /// Don't hammer YouTube when resolution just failed.
  static const _failureBackoff = Duration(seconds: 60);

  /// After a resolveAll batch that hit timeouts, leave the shared client
  /// alone for this long before touching YouTube again — repeated fresh
  /// clients during an active rate-limit just get refused faster.
  static const _rateLimitCooldown = Duration(seconds: 90);

  /// Cap for the escalating cooldown so a bad streak doesn't silence
  /// resolution for the rest of the session.
  static const _maxCooldown = Duration(minutes: 15);

  /// Successful resolutions are mirrored to disk so replaying a track
  /// after an app restart doesn't re-request YouTube (googlevideo URLs
  /// stay valid for hours; entries share the in-memory TTL for safety).
  /// Failure markers stay in memory only.
  static const _kDiskCacheKey = 'resolver.urlCache.v1';
  static const _kDiskCacheMaxEntries = 200;

  final Map<String, _CachedUrl> _cache = {};
  final Map<String, (String, int)> _diskEntries = {};
  Future<void>? _diskLoad;
  YoutubeExplode? _yt;
  DateTime? _coolingUntil;

  /// Escalates 90s → 3min → 7min → 15min across repeated rate-limits
  /// within a short window, backing off harder instead of repeatedly
  /// poking an IP that YouTube is already refusing.
  int _rateLimitStrikes = 0;
  DateTime? _lastRateLimit;

  void _tripRateLimit() {
    final now = DateTime.now();
    if (_lastRateLimit == null ||
        now.difference(_lastRateLimit!) > const Duration(minutes: 20)) {
      _rateLimitStrikes = 0;
    }
    _lastRateLimit = now;
    _rateLimitStrikes++;
    var cooldown = _rateLimitCooldown * (1 << (_rateLimitStrikes - 1).clamp(0, 4));
    if (cooldown > _maxCooldown) cooldown = _maxCooldown;
    _coolingUntil = now.add(cooldown);
    _yt?.close();
    _yt = null;
  }

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
    final cooling = _coolingUntil;
    if (cooling != null && now.isBefore(cooling)) {
      if (usesBackend) return track.audioUrl;
      throw ResolveException('YouTube is busy — try again in a moment');
    }

    // Load the persisted cache once (no-op afterwards). A cached URL from
    // a previous session skips the YouTube request entirely.
    await (_diskLoad ??= _loadDiskCache());

    String? url;
    final cached = _cache[videoId];
    if (cached != null) {
      if (now.isBefore(cached.expiresAt)) {
        // Failure marker during backoff — skip straight to the fallback.
        if (cached.isFailure) {
          if (usesBackend) return track.audioUrl;
          throw ResolveException(
              'Couldn\'t load stream — wait a moment and try again');
        }
        url = cached.url;
      } else {
        _cache.remove(videoId);
      }
    }

    if (url == null) {
      try {
        url = await _resolveWithRetry(videoId);
        _store(videoId, _CachedUrl(url, now.add(_cacheTtl)));
      } catch (e) {
        _store(videoId, _CachedUrl('', now.add(_failureBackoff)));
        if (usesBackend) return track.audioUrl;
        if (e is ResolveException) rethrow;
        if (e is RequestLimitExceededException) {
          _tripRateLimit();
          throw ResolveException(
              'YouTube is busy — wait a minute and try again');
        }
        if (e is TimeoutException) {
          throw ResolveException(
              'Couldn\'t reach YouTube — check your connection and try again');
        }
        rethrow;
      }
    }

    // googlevideo rejects the open-ended byte ranges ExoPlayer sends
    // (both for loading and for seeking), so the stream is served through
    // a loopback relay that converts them to bounded ranges.
    return StreamProxy.instance.relay(url, key: videoId);
  }

  /// Resolves every track in [tracks] sequentially. YouTube rate-limits
  /// mass parallel manifest fetches (large queues otherwise time out
  /// wholesale), so one fetch at a time with a pause between them. If
  /// consecutive timeouts signal an active rate-limit, the rest of the
  /// batch is abandoned and a cooldown is set so the next attempt waits
  /// out the limit instead of feeding it more requests. Failed entries
  /// come back as empty strings for the caller to skip.
  Future<List<String>> resolveAll(List<Track> tracks) async {
    final urls = List<String>.filled(tracks.length, '');
    var consecutiveTimeouts = 0;

    for (var i = 0; i < tracks.length; i++) {
      try {
        urls[i] = await resolve(tracks[i]);
        consecutiveTimeouts = 0;
      } on TimeoutException {
        consecutiveTimeouts++;
        if (consecutiveTimeouts >= 2) {
          // Active rate-limit: stop feeding the fire and cool down.
          _tripRateLimit();
          break;
        }
      } on RequestLimitExceededException {
        // YouTube explicitly refused — cool down immediately.
        _tripRateLimit();
        break;
      } catch (_) {
        // Unresolvable track — leave '' and keep going.
      }
      if (i < tracks.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    return urls;
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

  /// Resolves with one retry on timeout. A hung request poisons the
  /// shared client's connection pool, so the retry gets a fresh one.
  Future<String> _resolveWithRetry(String videoId) async {
    try {
      return await _resolve(videoId).timeout(_resolveTimeout);
    } on TimeoutException {
      _yt?.close();
      _yt = null;
      return await _resolve(videoId).timeout(_resolveTimeout);
    }
  }

  void _store(String videoId, _CachedUrl entry) {
    _cache[videoId] = entry;
    final now = DateTime.now();
    _cache.removeWhere((_, e) => now.isAfter(e.expiresAt));
    if (entry.isFailure) return; // Failure markers are session-only.
    _diskEntries[videoId] = (entry.url, entry.expiresAt.millisecondsSinceEpoch);
    unawaited(_persistDiskCache());
  }

  /// Restores cached URLs saved by a previous session. Expired and
  /// corrupt entries are dropped; a bad payload just leaves the cache
  /// empty.
  Future<void> _loadDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDiskCacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (final entry in data.entries) {
        final pair = entry.value as List;
        final url = pair[0] as String;
        final expiry = (pair[1] as num).toInt();
        if (url.isEmpty || expiry <= nowMs) continue;
        _diskEntries[entry.key] = (url, expiry);
        _cache[entry.key] = _CachedUrl(
            url, DateTime.fromMillisecondsSinceEpoch(expiry));
      }
    } catch (_) {
      // Corrupt cache — start empty; new resolves repopulate it.
    }
  }

  /// Writes the disk cache back, pruning expired entries and capping the
  /// size. Best-effort — persistence problems never block resolution.
  Future<void> _persistDiskCache() async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _diskEntries.removeWhere((_, v) => v.$2 <= nowMs);
      while (_diskEntries.length > _kDiskCacheMaxEntries) {
        _diskEntries.remove(_diskEntries.keys.first);
      }
      final prefs = await SharedPreferences.getInstance();
      final data = {
        for (final e in _diskEntries.entries)
          e.key: [e.value.$1, e.value.$2],
      };
      await prefs.setString(_kDiskCacheKey, jsonEncode(data));
    } catch (_) {
      // Nothing sensible to do — the in-memory cache still works.
    }
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
