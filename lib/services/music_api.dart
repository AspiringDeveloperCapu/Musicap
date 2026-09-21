import 'package:dio/dio.dart';
import 'package:music_player/models/track.dart';

const String baseUrl = 'http://localhost:5000';

class MusicApi {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Search songs by query.
  Future<List<Track>> search(String query, {int limit = 20}) async {
    final response = await _dio.get('/api/search', queryParameters: {
      'q': query,
      'limit': limit,
    });
    final results = response.data['results'] as List;
    return results.map((r) => _trackFromJson(r)).toList();
  }

  /// Get trending charts.
  Future<List<Track>> getCharts({int limit = 20}) async {
    final response = await _dio.get('/api/charts', queryParameters: {
      'limit': limit,
    });
    final results = response.data['results'] as List;
    return results.map((r) => _trackFromJson(r)).toList();
  }

  /// Get search autocomplete suggestions.
  Future<List<String>> getSuggestions(String query) async {
    final response = await _dio.get('/api/suggestions', queryParameters: {
      'q': query,
    });
    final results = response.data['results'] as List;
    return results.cast<String>();
  }

  /// Get the streaming URL for a track (proxied through our backend).
  String getStreamUrl(String videoId) {
    return '$baseUrl/api/stream/$videoId';
  }

  /// Get song metadata.
  Future<Track?> getSong(String videoId) async {
    try {
      final response = await _dio.get('/api/song/$videoId');
      return _trackFromJson(response.data['response']);
    } catch (_) {
      return null;
    }
  }

  /// Get lyrics for a song.
  Future<String?> getLyrics(String videoId) async {
    try {
      final response = await _dio.get('/api/lyrics/$videoId');
      return response.data['lyrics'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Convert API JSON to Track model.
  /// Uses the backend stream URL as the audio source.
  Track _trackFromJson(Map<String, dynamic> json) {
    final videoId = json['videoId'] ?? '';
    return Track(
      id: videoId,
      title: json['title'] ?? '',
      artist: json['artist'] ?? 'Unknown',
      imageUrl: json['thumbnail'],
      audioUrl: getStreamUrl(videoId),
      videoId: videoId,
    );
  }
}

final musicApi = MusicApi();
