/// A single genre/mood entry from YT Music's Genres & Moods page.
class GenreItem {
  final String title;
  final String params;

  const GenreItem({required this.title, required this.params});

  factory GenreItem.fromJson(Map<String, dynamic> json) {
    return GenreItem(
      title: json['title'] ?? '',
      params: json['params'] ?? '',
    );
  }
}

/// A titled section of genre/mood items (e.g. "Genres", "Moods & moments").
class GenreSection {
  final String title;
  final List<GenreItem> items;

  const GenreSection({required this.title, required this.items});

  factory GenreSection.fromJson(Map<String, dynamic> json) {
    return GenreSection(
      title: json['title'] ?? '',
      items: [
        for (final item in (json['items'] as List? ?? []))
          GenreItem.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}

/// A playlist inside a genre/mood category.
class GenrePlaylist {
  final String title;
  final String playlistId;
  final String? thumbnail;

  const GenrePlaylist({
    required this.title,
    required this.playlistId,
    this.thumbnail,
  });

  factory GenrePlaylist.fromJson(Map<String, dynamic> json) {
    return GenrePlaylist(
      title: json['title'] ?? '',
      playlistId: json['playlistId'] ?? '',
      thumbnail: json['thumbnail'],
    );
  }
}
