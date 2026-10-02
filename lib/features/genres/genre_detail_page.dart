import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/features/player/mini_player.dart';
import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/genre.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/music_provider.dart';
import 'package:music_player/widgets/mood_palette.dart';
import 'package:music_player/widgets/track_menu.dart';

/// Shows the songs and playlists inside one genre/mood category.
///
/// YT Music-inspired layout: a gradient hero header derived from the genre
/// title with Play all / Shuffle, then Songs, a 2-column playlist grid, and
/// related-genre chips to keep browsing.
class GenreDetailPage extends ConsumerWidget {
  final GenreItem item;

  const GenreDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(genreContentProvider(item.params));

    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
      body: contentAsync.when(
        loading: () => ListView(
          children: [
            _buildHeader(context, ref, songs: const []),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        error: (err, _) => ListView(
          children: [
            _buildHeader(context, ref, songs: const []),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 16),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load this genre',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(genreContentProvider(item.params)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ],
        ),
        data: (content) => ListView(
          children: [
            _buildHeader(context, ref, songs: content.songs),
            if (content.songs.isEmpty && content.playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'Nothing found for this genre',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              ),
            if (content.songs.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(
                  'Songs',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              for (var i = 0; i < content.songs.length; i++)
                TrackTile(
                  track: content.songs[i],
                  showDuration: true,
                  onTap: () {
                    ref.read(audioPlayerProvider.notifier).playTrack(
                          content.songs[i],
                          fromQueue: content.songs,
                          startIndex: i,
                        );
                  },
                ),
            ],
            if (content.playlists.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  'Playlists',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: content.playlists.length,
                itemBuilder: (context, index) =>
                    _buildPlaylistCard(context, ref, content.playlists[index]),
              ),
            ],
            _buildRelatedChips(context, ref),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Gradient hero header with back button, title, and Play all / Shuffle.
  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref, {
    required List<Track> songs,
  }) {
    final canPlay = songs.isNotEmpty;
    final primary = MoodPalette.primary(item.title);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: MoodPalette.gradient(item.title)),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BackButton(
                color: Colors.white,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black38)],
                  ),
                ),
              ),
              if (canPlay) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            ref.read(audioPlayerProvider.notifier).playTrack(
                                  songs.first,
                                  fromQueue: songs,
                                  startIndex: 0,
                                );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: primary,
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play all'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => ref
                              .read(audioPlayerProvider.notifier)
                              .shufflePlay(songs),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                          ),
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Chips for every other genre/mood, so users can hop between them.
  Widget _buildRelatedChips(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(genresProvider);
    return genresAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (sections) {
        final others = [
          for (final section in sections)
            ...section.items.where((g) => g.params != item.params),
        ].take(40).toList();
        if (others.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'More in Genres & Moods',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final genre in others)
                    HoverScale(
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => GenreDetailPage(item: genre),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: MoodPalette.primary(genre.title),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          genre.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// A tappable playlist card that opens the playlist's track list.
  Widget _buildPlaylistCard(
    BuildContext context,
    WidgetRef ref,
    GenrePlaylist playlist,
  ) {
    return HoverScale(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GenrePlaylistPage(playlist: playlist),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: playlist.thumbnail != null
                    ? Image.network(
                        playlist.thumbnail!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, url, error) => const Center(
                          child: Icon(Icons.queue_music, size: 48),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.queue_music, size: 48),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                playlist.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Track list for one genre playlist, with Play All and Shuffle.
class GenrePlaylistPage extends ConsumerWidget {
  final GenrePlaylist playlist;

  const GenrePlaylistPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(playlistTracksProvider(playlist.playlistId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          playlist.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottomNavigationBar: const MiniPlayer(),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Could not load tracks',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.invalidate(playlistTracksProvider(playlist.playlistId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (tracks) {
          if (tracks.isEmpty) {
            return const Center(
              child: Text(
                'No tracks found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          final controller = ref.read(audioPlayerProvider.notifier);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => controller.playTrack(
                          tracks.first,
                          fromQueue: tracks,
                          startIndex: 0,
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: Text('Play All (${tracks.length})'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => controller.shufflePlay(tracks),
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Shuffle'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) => TrackTile(
                    track: tracks[index],
                    showDuration: true,
                    onTap: () => controller.playTrack(
                      tracks[index],
                      fromQueue: tracks,
                      startIndex: index,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
