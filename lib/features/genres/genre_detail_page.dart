import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/features/player/mini_player.dart';
import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/genre.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/download_manager.dart';
import 'package:music_player/providers/music_provider.dart';

/// Shows the songs and playlists inside one genre/mood category.
class GenreDetailPage extends ConsumerWidget {
  final GenreItem item;

  const GenreDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(genreContentProvider(item.params));

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
      ),
      bottomNavigationBar: const MiniPlayer(),
      body: contentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
        data: (content) {
          if (content.songs.isEmpty && content.playlists.isEmpty) {
            return const Center(
              child: Text(
                'Nothing found for this genre',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          return ListView(
            children: [
              if (content.songs.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Songs',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                for (var i = 0; i < content.songs.length; i++)
                  _buildSongTile(context, ref, content.songs, i),
              ],
              if (content.playlists.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
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
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  /// A playable song row.
  Widget _buildSongTile(
    BuildContext context,
    WidgetRef ref,
    List<Track> songs,
    int index,
  ) {
    final track = songs[index];
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
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        ),
        onSelected: (value) {
          if (value == 'queue') {
            ref.read(audioPlayerProvider.notifier).addToQueue(track);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added "${track.title}" to queue'),
                duration: const Duration(seconds: 1),
              ),
            );
          } else if (value == 'download') {
            ref.read(downloadManagerProvider.notifier).startDownload(track);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloading "${track.title}"'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'queue', child: Text('Add to queue')),
          PopupMenuItem(value: 'download', child: Text('Download')),
        ],
      ),
      onTap: () {
        ref.read(audioPlayerProvider.notifier).playTrack(
              track,
              fromQueue: songs,
              startIndex: index,
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
