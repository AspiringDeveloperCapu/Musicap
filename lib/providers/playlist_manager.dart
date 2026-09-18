import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Mutable state provider for playlist management.
/// Allows CRUD operations: create, rename, delete, add tracks, remove tracks.
class PlaylistManager extends StateNotifier<List<Playlist>> {
  PlaylistManager() : super(_defaultPlaylists());

  /// Initial hardcoded playlists.
  static List<Playlist> _defaultPlaylists() {
    return [
      Playlist(
        id: 'p1',
        name: 'Favorites',
        tracks: [
          const Track(
            id: '8',
            title: 'Don\'t Stop Believin\'',
            artist: 'Journey',
            audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
          ),
          const Track(
            id: '9',
            title: 'Livin\' on a Prayer',
            artist: 'Bon Jovi',
            audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-9.mp3',
          ),
        ],
      ),
      Playlist(
        id: 'p2',
        name: 'Chill Vibes',
        tracks: [
          const Track(
            id: '10',
            title: 'Summertime',
            artist: 'DJ Jazzy Jeff',
            audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-10.mp3',
          ),
        ],
      ),
      Playlist(
        id: 'p3',
        name: 'Workout Mix',
        tracks: [
          const Track(
            id: '11',
            title: 'Stronger',
            artist: 'Kanye West',
            audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-11.mp3',
          ),
          const Track(
            id: '12',
            title: 'Till I Collapse',
            artist: 'Eminem',
            audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-12.mp3',
          ),
        ],
      ),
    ];
  }

  /// Creates a new empty playlist with the given [name].
  /// Returns the new playlist's ID.
  String createPlaylist(String name) {
    final id = _uuid.v4();
    final playlist = Playlist(id: id, name: name, tracks: []);
    state = [...state, playlist];
    return id;
  }

  /// Deletes a playlist by [playlistId].
  void deletePlaylist(String playlistId) {
    state = state.where((p) => p.id != playlistId).toList();
  }

  /// Renames a playlist.
  void renamePlaylist(String playlistId, String newName) {
    state = [
      for (final p in state)
        if (p.id == playlistId)
          Playlist(id: p.id, name: newName, tracks: p.tracks)
        else
          p,
    ];
  }

  /// Adds a track to a playlist. Prevents duplicates by track ID.
  void addTrackToPlaylist(String playlistId, Track track) {
    state = [
      for (final p in state)
        if (p.id == playlistId)
          Playlist(
            id: p.id,
            name: p.name,
            tracks: p.tracks.any((t) => t.id == track.id)
                ? p.tracks
                : [...p.tracks, track],
          )
        else
          p,
    ];
  }

  /// Removes a track from a playlist by track index.
  void removeTrackFromPlaylist(String playlistId, int trackIndex) {
    state = [
      for (final p in state)
        if (p.id == playlistId)
          Playlist(
            id: p.id,
            name: p.name,
            tracks: List<Track>.from(p.tracks)..removeAt(trackIndex),
          )
        else
          p,
    ];
  }
}

/// The main playlist manager provider.
final playlistManagerProvider = StateNotifierProvider<PlaylistManager, List<Playlist>>((ref) {
  return PlaylistManager();
});

/// Read-only provider that exposes just the playlist list (same as before).
/// Use this in places that only need to read playlists.
final playlistsListProvider = Provider<List<Playlist>>((ref) {
  return ref.watch(playlistManagerProvider);
});
