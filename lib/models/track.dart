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

  /// YouTube video ID used for API stream URL resolution.
  final String? videoId;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.imageUrl,
    required this.audioUrl,
    this.duration,
    this.videoId,
  });

  /// Create a Track from API JSON response.
  factory Track.fromJson(Map<String, dynamic> json, {String? streamBaseUrl}) {
    final vid = json['videoId'] ?? '';
    final audioUrl = streamBaseUrl != null && vid.isNotEmpty
        ? '$streamBaseUrl/api/stream/$vid'
        : json['audioUrl'] ?? '';
    return Track(
      id: vid.isNotEmpty ? vid : json['id'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? 'Unknown',
      imageUrl: json['thumbnail'] ?? json['imageUrl'],
      audioUrl: audioUrl,
      videoId: vid.isNotEmpty ? vid : null,
    );
  }
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
