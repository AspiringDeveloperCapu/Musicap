import 'dart:async';

import 'package:music_player/models/track.dart';
import 'package:music_player/services/youtube_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// On-device YouTube metadata for serverless Android.
///
/// Mirrors the backend subset the app relies on: search results, search
/// suggestions, and a search-based "related" feed for autoplay. Web and
/// desktop keep using `MusicApi` instead.
///
/// Searches and suggestions are memoized for the session: revisiting
/// the same query happens constantly (back-and-forth edits in the same
/// search field, repeated autoplay seeds) and redoing those YouTube
/// requests buys nothing — it just feeds the rate limiter.
///
/// Every network call is capped at 15s: a raw YouTube search with no
/// timeout can hang forever on a slow connection, which previously left
/// autoplay waiting indefinitely.
class DeviceMetadata {
  DeviceMetadata._();

  static final DeviceMetadata instance = DeviceMetadata._();

  static const _timeout = Duration(seconds: 15);

  /// Session memo size cap; oldest entries evicted first.
  static const _kMemoMax = 60;

  final Map<String, List<Track>> _searchMemo = {};
  final Map<String, List<String>> _suggestionMemo = {};

  Future<T> _withTimeout<T>(Future<T> future) =>
      future.timeout(_timeout,
          onTimeout: () => throw TimeoutException('YouTube request timed out'));

  /// Searches YouTube on-device and maps results into app [Track]s.
  /// [Track.audioUrl] stays empty — playback resolves through
  /// `StreamResolver` using the video ID. Returns an empty list on timeout.
  Future<List<Track>> search(String query, {int limit = 30}) async {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return const <Track>[];
    final memo = _searchMemo[key];
    if (memo != null) return memo.take(limit).toList();
    try {
      final results = await _withTimeout(
          YoutubeClientPool.instance.use().search.search(query));
      final mapped = results.map(_trackFromVideo).toList();
      _memoSearch(key, mapped);
      return mapped.take(limit).toList();
    } on TimeoutException {
      return const <Track>[];
    }
  }

  /// Autocomplete suggestions straight from YouTube. Empty on timeout.
  Future<List<String>> suggestions(String query) async {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return const <String>[];
    final memo = _suggestionMemo[key];
    if (memo != null) return memo;
    try {
      final suggestions = await _withTimeout(YoutubeClientPool.instance
          .use()
          .search
          .getQuerySuggestions(query));
      final cleaned = suggestions.where((s) => s.isNotEmpty).take(8).toList();
      _memoSuggestions(key, cleaned);
      return cleaned;
    } on TimeoutException {
      return const <String>[];
    }
  }

  /// Search-based substitute for the backend recommendations radio:
  /// results similar to [seed], excluding [excludeIds] (the current queue).
  /// Empty list on timeout — callers treat that as "no related music".
  ///
  /// The same seed is searched repeatedly across autoplay cycles and
  /// queue rebuilds, so the raw search page is memoized by seed video ID
  /// and the [excludeIds] filter re-applied on top of each call.
  Future<List<Track>> related(
    Track seed, {
    int limit = 10,
    Set<String> excludeIds = const {},
  }) async {
    final seedId = seed.videoId ?? seed.id;
    final memo = seedId == null || seedId.isEmpty
        ? null
        : _searchMemo['related:$seedId'];
    if (memo != null) return _filterRelated(memo, excludeIds, limit);
    final query = '${seed.title} ${seed.artist}'.trim();
    if (query.isEmpty) return const <Track>[];
    try {
      final results = await _withTimeout(
          YoutubeClientPool.instance.use().search.search(query));
      final mapped = results.map(_trackFromVideo).toList();
      if (seedId != null && seedId.isNotEmpty) {
        _memoSearch('related:$seedId', mapped);
      }
      return _filterRelated(mapped, excludeIds, limit);
    } on TimeoutException {
      return const <Track>[];
    }
  }

  List<Track> _filterRelated(
    List<Track> results,
    Set<String> excludeIds,
    int limit,
  ) =>
      results
          .where((v) => !excludeIds.contains(v.videoId) && !excludeIds.contains(v.id))
          .take(limit)
          .toList();

  void _memoSearch(String key, List<Track> results) {
    if (_searchMemo.length >= _kMemoMax) {
      _searchMemo.remove(_searchMemo.keys.first);
    }
    _searchMemo[key] = results;
  }

  void _memoSuggestions(String key, List<String> results) {
    if (_suggestionMemo.length >= _kMemoMax) {
      _suggestionMemo.remove(_suggestionMemo.keys.first);
    }
    _suggestionMemo[key] = results;
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
