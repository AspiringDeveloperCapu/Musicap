import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/genre.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/playlist_manager.dart';
import 'package:music_player/providers/settings_provider.dart';
import 'package:music_player/services/device_metadata.dart';
import 'package:music_player/services/music_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fetches trending charts for the user's selected region/language.
final chartsProvider = FutureProvider<List<Track>>((ref) async {
  if (!usesBackend) return const <Track>[];
  final settings = ref.watch(settingsProvider);
  return musicApi.getCharts(
    limit: 20,
    cc: settings.region,
    lang: settings.language,
  );
});

/// Recently played tracks — stored locally in memory.
final recentlyPlayedProvider = StateNotifierProvider<RecentlyPlayedNotifier, List<Track>>((ref) {
  return RecentlyPlayedNotifier();
});

class RecentlyPlayedNotifier extends StateNotifier<List<Track>> {
  RecentlyPlayedNotifier() : super([]);

  void addTrack(Track track) {
    state = [track, ...state.where((t) => t.id != track.id).take(19)];
  }
}

/// "Made for you" recommendations seeded by the most recently played track
/// (or charts on first launch).
final recommendationsProvider = FutureProvider<List<Track>>((ref) async {
  if (!usesBackend) return const <Track>[];
  final recent = ref.watch(recentlyPlayedProvider);
  final language = ref.watch(settingsProvider.select((s) => s.language));

  String? seed;
  if (recent.isNotEmpty) {
    seed = recent.first.videoId ?? recent.first.id;
  }
  if (seed == null) {
    final charts = await ref.watch(chartsProvider.future);
    if (charts.isNotEmpty) {
      seed = charts.first.videoId ?? charts.first.id;
    }
  }
  if (seed == null) return [];

  final recs = await musicApi.getRecommendations(
    videoId: seed,
    limit: 20,
    lang: language,
  );
  final seedId = seed;
  return recs.where((t) => t.id != seedId).toList();
});

/// YT Music Genres & Moods sections for the Genres page and Home chips.
final genresProvider = FutureProvider<List<GenreSection>>((ref) async {
  if (!usesBackend) return const <GenreSection>[];
  final language = ref.watch(settingsProvider.select((s) => s.language));
  return musicApi.getGenres(lang: language);
});

/// Recommendations seeded by a specific track (used in playlist detail).
final trackRecommendationsProvider =
    FutureProvider.family<List<Track>, String>((ref, seedVideoId) async {
  if (!usesBackend) return const <Track>[];
  final language = ref.watch(settingsProvider.select((s) => s.language));
  final recs = await musicApi.getRecommendations(
    videoId: seedVideoId,
    limit: 20,
    lang: language,
  );
  return recs.where((t) => t.id != seedVideoId).toList();
});

/// Songs and playlists inside one genre/mood category.
final genreContentProvider =
    FutureProvider.family<GenreContent, String>((ref, params) async {
  if (!usesBackend) return const GenreContent();
  final language = ref.watch(settingsProvider.select((s) => s.language));
  return musicApi.getGenreContent(params, limit: 12, lang: language);
});

/// Tracks of a playlist (genre playlists, recommendations into playlists).
final playlistTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, playlistId) async {
  if (!usesBackend) return const <Track>[];
  final language = ref.watch(settingsProvider.select((s) => s.language));
  return musicApi.getPlaylistTracks(playlistId, limit: 50, lang: language);
});

/// User playlists — backed by playlistManagerProvider.
final playlistsProvider = Provider<List<Playlist>>((ref) {
  return ref.watch(playlistManagerProvider);
});

/// Mutable state provider for the current search query text.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Debounced search provider — calls the backend API with a delay.
final searchResultsProvider = FutureProvider<List<Track>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  // Wait 500ms for the user to stop typing.
  await Future.delayed(const Duration(milliseconds: 500));

  // Re-check if query changed during delay.
  final currentQuery = ref.read(searchQueryProvider);
  if (currentQuery != query) return [];

  if (!usesBackend) return DeviceMetadata.instance.search(query, limit: 30);

  final language = ref.watch(settingsProvider.select((s) => s.language));
  return musicApi.search(query, limit: 30, lang: language);
});

/// Debounced autocomplete suggestions for the search field.
final searchSuggestionsProvider = FutureProvider<List<String>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.length < 2) return [];
  final language = ref.watch(settingsProvider.select((s) => s.language));

  // Wait 300ms for the user to stop typing.
  await Future.delayed(const Duration(milliseconds: 300));

  final currentQuery = ref.read(searchQueryProvider).trim();
  if (currentQuery != query) return [];

  try {
    final suggestions = usesBackend
        ? await musicApi.getSuggestions(query, lang: language)
        : await DeviceMetadata.instance.suggestions(query);
    return suggestions.where((s) => s.isNotEmpty).take(8).toList();
  } catch (_) {
    return [];
  }
});

/// Search history — persisted so it survives restarts.
final recentSearchesProvider =
    StateNotifierProvider<RecentSearchesNotifier, List<String>>((ref) {
  return RecentSearchesNotifier();
});

class RecentSearchesNotifier extends StateNotifier<List<String>> {
  RecentSearchesNotifier() : super(const []) {
    _load();
  }

  static const _kKey = 'recentSearches.v1';
  static const _kMax = 10;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return;
    try {
      state = (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      // Corrupt history — start fresh.
    }
  }

  Future<void> addSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    state = [
      trimmed,
      ...state.where((q) => q.toLowerCase() != trimmed.toLowerCase()),
    ].take(_kMax).toList();
    await _save();
  }

  Future<void> removeSearch(String query) async {
    state = state.where((q) => q != query).toList();
    await _save();
  }

  Future<void> clear() async {
    state = [];
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(state));
  }
}
