import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const _kPlaylistsKey = 'playlists.v1';

/// Mutable state provider for playlist management.
/// Allows CRUD operations: create, rename, delete, add tracks, remove tracks.
/// Playlists are persisted to shared_preferences so they survive restarts.
class PlaylistManager extends StateNotifier<List<Playlist>> {
  PlaylistManager() : super(const []) {
    _load();
  }

  /// Loads persisted playlists, seeding defaults on first launch.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPlaylistsKey);
    if (raw == null) {
      state = _defaultPlaylists();
      await _save();
      return;
    }
    try {
      final decoded = jsonDecode(raw) as List;
      state = [
        for (final p in decoded)
          Playlist.fromJson(Map<String, dynamic>.from(p)),
      ];
    } catch (_) {
      state = _defaultPlaylists();
      await _save();
    }
  }

  /// Persists the current playlist list.
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPlaylistsKey,
      jsonEncode(state.map((p) => p.toJson()).toList()),
    );
  }

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
    _save();
    return id;
  }

  /// Deletes a playlist by [playlistId].
  void deletePlaylist(String playlistId) {
    state = state.where((p) => p.id != playlistId).toList();
    _save();
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
    _save();
  }

  /// Adds a track to a playlist. Prevents duplicates by track ID.
  /// Returns true if the track was added, false if it was already present.
  bool addTrackToPlaylist(String playlistId, Track track) {
    final targetPlaylist = state.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => Playlist(id: '', name: '', tracks: []),
    );
    if (targetPlaylist.id.isEmpty) return false;
    if (targetPlaylist.tracks.any((t) => t.id == track.id)) return false;

    state = [
      for (final p in state)
        if (p.id == playlistId)
          Playlist(
            id: p.id,
            name: p.name,
            tracks: [...p.tracks, track],
          )
        else
          p,
    ];
    _save();
    return true;
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
    _save();
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
