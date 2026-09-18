import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/playlist_manager.dart';

/// Hardcoded list of recently played tracks.
/// In a real app, this would come from persistent storage or an API.
final recentlyPlayedProvider = Provider<List<Track>>((ref) {
  return const [
    Track(
      id: '1',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    ),
    Track(
      id: '2',
      title: 'Starboy',
      artist: 'The Weeknd',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    ),
    Track(
      id: '3',
      title: 'Shape of You',
      artist: 'Ed Sheeran',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    ),
  ];
});

/// Hardcoded list of recommended tracks for the dashboard.
final recommendationsProvider = Provider<List<Track>>((ref) {
  return const [
    Track(
      id: '4',
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    ),
    Track(
      id: '5',
      title: 'Hotel California',
      artist: 'Eagles',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
    ),
    Track(
      id: '6',
      title: 'Stairway to Heaven',
      artist: 'Led Zeppelin',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
    ),
    Track(
      id: '7',
      title: 'Sweet Child O\' Mine',
      artist: 'Guns N\' Roses',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
    ),
  ];
});

/// Hardcoded list of user playlists, each containing multiple tracks.
/// NOTE: This is now backed by the playlistManagerProvider for CRUD operations.
final playlistsProvider = Provider<List<Playlist>>((ref) {
  return ref.watch(playlistManagerProvider);
});

/// Mutable state provider for the current search query text.
/// Updated by the search TextField in the HomePage AppBar.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Derived provider that filters all tracks across recently played,
/// recommendations, and playlists based on the current search query.
/// Matches against both track title and artist name (case-insensitive).
final searchResultsProvider = Provider<List<Track>>((ref) {
  final query = ref.watch(searchQueryProvider).toLowerCase();
  if (query.isEmpty) return [];

  // Combine all tracks from every section into a single searchable list.
  final allTracks = [
    ...ref.watch(recentlyPlayedProvider),
    ...ref.watch(recommendationsProvider),
    ...ref.watch(playlistsProvider).expand((p) => p.tracks),
  ];

  return allTracks.where((track) {
    return track.title.toLowerCase().contains(query) ||
        track.artist.toLowerCase().contains(query);
  }).toList();
});
