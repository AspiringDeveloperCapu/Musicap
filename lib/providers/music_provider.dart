import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/playlist_manager.dart';
import 'package:music_player/services/music_api.dart';

/// Fetches trending charts from the backend API.
final chartsProvider = FutureProvider<List<Track>>((ref) async {
  return musicApi.getCharts(limit: 20);
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

/// Hardcoded list of recommended tracks — replaced with charts for now.
final recommendationsProvider = Provider<List<Track>>((ref) {
  return const [];
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

  return musicApi.search(query, limit: 30);
});
