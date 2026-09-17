import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';

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

final playlistsProvider = Provider<List<Playlist>>((ref) {
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
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = Provider<List<Track>>((ref) {
  final query = ref.watch(searchQueryProvider).toLowerCase();
  if (query.isEmpty) return [];

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
