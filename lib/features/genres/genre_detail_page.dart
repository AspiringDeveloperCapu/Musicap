import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/features/player/mini_player.dart';
import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/genre.dart';
import 'package:music_player/providers/download_manager.dart';
import 'package:music_player/providers/music_provider.dart';

/// Shows the playlists inside one genre/mood category.
class GenreDetailPage extends ConsumerWidget {
  final GenreItem item;

  const GenreDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(genrePlaylistsProvider(item.params));

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
      ),
      bottomNavigationBar: const MiniPlayer(),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Could not load playlists',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.invalidate(genrePlaylistsProvider(item.params)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (playlists) {
          if (playlists.isEmpty) {
            return const Center(
              child: Text(
                'No playlists found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
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
                                  errorBuilder: (context, url, error) =>
                                      const Center(
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
            },
          );
        },
      ),
    );
  }
}

/// Track list for one genre playlist, with Play All.
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
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ref.read(audioPlayerProvider.notifier).playTrack(
                            tracks.first,
                            fromQueue: tracks,
                            startIndex: 0,
                          );
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Play All (${tracks.length})'),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: track.imageUrl != null
                              ? Image.network(
                                  track.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, url, error) =>
                                      const Icon(Icons.music_note),
                                )
                              : const Icon(Icons.music_note),
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color:
                              Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                        onSelected: (value) {
                          if (value == 'queue') {
                            ref
                                .read(audioPlayerProvider.notifier)
                                .addToQueue(track);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Added "${track.title}" to queue'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          } else if (value == 'download') {
                            ref
                                .read(downloadManagerProvider.notifier)
                                .startDownload(track);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Downloading "${track.title}"'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'queue',
                            child: Text('Add to queue'),
                          ),
                          PopupMenuItem(
                            value: 'download',
                            child: Text('Download'),
                          ),
                        ],
                      ),
                      onTap: () {
                        ref.read(audioPlayerProvider.notifier).playTrack(
                              track,
                              fromQueue: tracks,
                              startIndex: index,
                            );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
