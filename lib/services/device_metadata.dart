import 'package:music_player/models/track.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// On-device YouTube metadata for serverless Android.
///
/// Mirrors the backend subset the app relies on: search results, search
/// suggestions, and a search-based "related" feed for autoplay. Web and
/// desktop keep using `MusicApi` instead.
class DeviceMetadata {
  DeviceMetadata._();

  static final DeviceMetadata instance = DeviceMetadata._();

  final YoutubeExplode _yt = YoutubeExplode();

  /// Searches YouTube on-device and maps results into app [Track]s.
  /// [Track.audioUrl] stays empty — playback resolves through
  /// `StreamResolver` using the video ID.
  Future<List<Track>> search(String query, {int limit = 30}) async {
    final results = await _yt.search.search(query);
    return results.take(limit).map(_trackFromVideo).toList();
  }

  /// Autocomplete suggestions straight from YouTube.
  Future<List<String>> suggestions(String query) =>
      _yt.search.getQuerySuggestions(query);

  /// Search-based substitute for the backend recommendations radio:
  /// results similar to [seed], excluding [excludeIds] (the current queue).
  Future<List<Track>> related(
    Track seed, {
    int limit = 10,
    Set<String> excludeIds = const {},
  }) async {
    final query = '${seed.title} ${seed.artist}'.trim();
    if (query.isEmpty) return const <Track>[];
    final results = await _yt.search.search(query);
    return results
        .where((v) => !excludeIds.contains(v.id.value))
        .take(limit)
        .map(_trackFromVideo)
        .toList();
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
