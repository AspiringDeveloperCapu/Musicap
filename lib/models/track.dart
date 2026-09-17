class Track {
  final String id;
  final String title;
  final String artist;
  final String? imageUrl;
  final String audioUrl;
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

class Playlist {
  final String id;
  final String name;
  final String? imageUrl;
  final List<Track> tracks;

  const Playlist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.tracks,
  });
}
