import 'dart:async';

import 'package:music_player/models/track.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// On-device YouTube metadata for serverless Android.
///
/// Mirrors the backend subset the app relies on: search results, search
/// suggestions, and a search-based "related" feed for autoplay. Web and
/// desktop keep using `MusicApi` instead.
///
/// Every network call is capped at 15s: a raw YouTube search with no
/// timeout can hang forever on a slow connection, which previously left
/// autoplay waiting indefinitely.
class DeviceMetadata {
  DeviceMetadata._();

  static final DeviceMetadata instance = DeviceMetadata._();

  static const _timeout = Duration(seconds: 15);

  final YoutubeExplode _yt = YoutubeExplode();

  Future<T> _withTimeout<T>(Future<T> future) =>
      future.timeout(_timeout,
          onTimeout: () => throw TimeoutException('YouTube request timed out'));

  /// Searches YouTube on-device and maps results into app [Track]s.
  /// [Track.audioUrl] stays empty — playback resolves through
  /// `StreamResolver` using the video ID. Returns an empty list on timeout.
  Future<List<Track>> search(String query, {int limit = 30}) async {
    try {
      final results = await _withTimeout(_yt.search.search(query));
      return results.take(limit).map(_trackFromVideo).toList();
    } on TimeoutException {
      return const <Track>[];
    }
  }

  /// Autocomplete suggestions straight from YouTube. Empty on timeout.
  Future<List<String>> suggestions(String query) async {
    try {
      return await _withTimeout(_yt.search.getQuerySuggestions(query));
    } on TimeoutException {
      return const <String>[];
    }
  }

  /// Search-based substitute for the backend recommendations radio:
  /// results similar to [seed], excluding [excludeIds] (the current queue).
  /// Empty list on timeout — callers treat that as "no related music".
  Future<List<Track>> related(
    Track seed, {
    int limit = 10,
    Set<String> excludeIds = const {},
  }) async {
    final query = '${seed.title} ${seed.artist}'.trim();
    if (query.isEmpty) return const <Track>[];
    try {
      final results = await _withTimeout(_yt.search.search(query));
      return results
          .where((v) => !excludeIds.contains(v.id.value))
          .take(limit)
          .map(_trackFromVideo)
          .toList();
    } on TimeoutException {
      return const <Track>[];
    }
  }

  Track _trackFromVideo(Video video) => Track(
    id: video.id.value,
    title: video.title,
    artist: video.author,
    imageUrl: video.thumbnails.maxResUrl,
    audioUrl: '',
    duration: video.duration,
    videoId: video.id.value,
  );
}
