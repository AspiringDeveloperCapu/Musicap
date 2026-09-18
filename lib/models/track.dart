/// Data model for a single track (song).
/// Contains all metadata needed to display and play a track.
class Track {
  /// Unique identifier for the track.
  final String id;

  /// Display title of the track.
  final String title;

  /// Artist name.
  final String artist;

  /// Optional URL for the track's album art image.
  final String? imageUrl;

  /// URL pointing to the audio file (MP3, etc.).
  final String audioUrl;

  /// Optional known duration of the track.
  final Duration? duration;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.imageUrl,
    required this.audioUrl,
    this.duration,
  });
}

/// Data model for a playlist — a named collection of tracks.
class Playlist {
  /// Unique identifier for the playlist.
  final String id;

  /// Display name of the playlist.
  final String name;

  /// Optional URL for the playlist's cover image.
  final String? imageUrl;

  /// Ordered list of tracks in this playlist.
  final List<Track> tracks;

  const Playlist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.tracks,
  });
}
