import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:music_player/models/genre.dart';
import 'package:music_player/models/track.dart';

/// Default backend URL for the current platform.
///
/// On web, a page served over HTTPS (production, e.g. behind Render) serves
/// the app and the API from the same origin — use that origin directly.
/// Over plain HTTP (Flutter dev server, local static server) the page isn't
/// the backend, so target port 5000 of whatever host served the page — this
/// covers dev on localhost, the PC's LAN IP when opened from a phone, and
/// the backend-served production build alike.
/// Android points at the deployed Render backend; desktop uses localhost.
String get defaultServerUrl {
  if (kIsWeb) {
    final base = Uri.base;
    if (base.scheme == 'https' || base.port == 5000) {
      return base.origin;
    }
    return 'http://${base.host}:5000';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'https://musicap-backend.onrender.com';
  }
  return 'http://localhost:5000';
}

/// Whether this platform uses the backend server for metadata.
///
/// Android is fully serverless — search, suggestions and related tracks
/// come from on-device YouTube clients (see `DeviceMetadata`), local
/// files are scanned through MediaStore, and streams resolve locally.
/// Web and desktop keep using the backend.
bool get usesBackend =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.android;

class MusicApi {
  String _serverUrl = defaultServerUrl;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: defaultServerUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Current backend base URL.
  String get serverUrl => _serverUrl;

  /// Point the API at a different backend (persisted via Settings).
  void setServerUrl(String url) {
    var v = url.trim();
    if (v.isEmpty) return;
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'http://$v';
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    _serverUrl = v;
    _dio.options.baseUrl = v;
  }

  /// Pings the backend's health endpoint. Returns true when the server
  /// responds with its expected payload; false on any network/HTTP error.
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get(
        '/api/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      return response.statusCode == 200 &&
          response.data is Map &&
          response.data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Search songs by query.
  Future<List<Track>> search(String query, {int limit = 20, String? lang}) async {
    final response = await _dio.get('/api/search', queryParameters: {
      'q': query,
      'limit': limit,
      if (lang != null) 'lang': lang,
    });
    final results = response.data['results'] as List;
    return results.map((r) => _trackFromJson(r)).toList();
  }

  /// Get trending charts for a country.
  Future<List<Track>> getCharts({int limit = 20, String? cc, String? lang}) async {
    final response = await _dio.get('/api/charts', queryParameters: {
      'limit': limit,
      if (cc != null) 'cc': cc,
      if (lang != null) 'lang': lang,
    });
    final results = response.data['results'] as List;
    return results.map((r) => _trackFromJson(r)).toList();
  }

  /// Get YT Music's Genres & Moods sections.
  Future<List<GenreSection>> getGenres({String? lang}) async {
    final response = await _dio.get('/api/genres', queryParameters: {
      if (lang != null) 'lang': lang,
    });
    final sections = response.data['sections'] as List;
    return sections
        .map((s) => GenreSection.fromJson(Map<String, dynamic>.from(s)))
        .toList();
  }

  /// Get a genre/mood category's songs and playlists.
  Future<GenreContent> getGenreContent(
    String params, {
    int limit = 12,
    String? lang,
  }) async {
    final response = await _dio.get('/api/genre', queryParameters: {
      'params': params,
      'limit': limit,
      if (lang != null) 'lang': lang,
    });
    final songs = (response.data['songs'] as List? ?? [])
        .map((s) => _trackFromJson(Map<String, dynamic>.from(s)))
        .toList();
    final playlists = (response.data['playlists'] as List? ?? [])
        .map((p) => GenrePlaylist.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    return GenreContent(songs: songs, playlists: playlists);
  }

  /// Get the tracks of a playlist (used for genre playlists).
  Future<List<Track>> getPlaylistTracks(
    String playlistId, {
    int limit = 50,
    String? lang,
  }) async {
    final response = await _dio.get('/api/playlist/$playlistId', queryParameters: {
      'limit': limit,
      if (lang != null) 'lang': lang,
    });
    final results = response.data['results'] as List;
    return results.map((r) => _trackFromJson(r)).toList();
  }

  /// Get radio/watch-playlist recommendations seeded by a video ID.
  Future<List<Track>> getRecommendations({
    required String videoId,
    int limit = 20,
    String? lang,
  }) async {
    final response = await _dio.get('/api/recommendations', queryParameters: {
      'videoId': videoId,
      'limit': limit,
      if (lang != null) 'lang': lang,
    });
    final results = response.data['results'] as List;
    return results.map((r) => _trackFromJson(r)).toList();
  }

  /// Get search autocomplete suggestions.
  Future<List<String>> getSuggestions(String query, {String? lang}) async {
    final response = await _dio.get('/api/suggestions', queryParameters: {
      'q': query,
      if (lang != null) 'lang': lang,
    });
    final results = response.data['results'] as List;
    return results.cast<String>();
  }

  /// Get the streaming URL for a track (proxied through our backend).
  String getStreamUrl(String videoId) {
    return '$serverUrl/api/stream/$videoId';
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
      duration: _parseDuration(json['duration']),
      videoId: videoId,
    );
  }

  /// Parses "m:ss" / "h:mm:ss" duration strings from the API.
  Duration? _parseDuration(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      final parts = raw.split(':');
      if (parts.length >= 2 && parts.length <= 3) {
        final numbers = parts.map((p) => int.tryParse(p.trim())).toList();
        if (numbers.every((n) => n != null)) {
          var seconds = 0;
          for (final n in numbers) {
            seconds = seconds * 60 + n!;
          }
          return Duration(seconds: seconds);
        }
      }
    }
    return null;
  }
}

final musicApi = MusicApi();
