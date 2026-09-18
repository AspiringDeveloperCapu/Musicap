import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/providers/playlist_manager.dart';
import 'package:music_player/features/playlist/playlist_detail_page.dart';
import 'package:music_player/models/track.dart';

/// Library page that displays available playlists and the current playback queue.
/// Tapping a playlist navigates to its detail view.
/// Includes a "Create Playlist" button to add new playlists.
class PlaylistPage extends ConsumerWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioPlayerProvider);
    final playlists = ref.watch(playlistManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          // Create new playlist button
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreatePlaylistDialog(context, ref),
          ),
        ],
      ),
      body: ListView(
        children: [
          // "Your Playlists" section header.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Your Playlists',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          // Render each playlist as a tappable tile.
          ...playlists.map((playlist) => _PlaylistTile(
                playlist: playlist,
                onTap: () {
                  // Navigate to playlist detail page.
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailPage(playlistId: playlist.id),
                    ),
                  );
                },
              )),
          const Divider(indent: 16, endIndent: 16),

          // "Queue / Now Playing" section header with track count.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Queue / Now Playing',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                if (state.queue.isNotEmpty)
                  Text(
                    '${state.queue.length} tracks',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
              ],
            ),
          ),
          // Show empty state or the current queue list.
          if (state.queue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Nothing playing yet',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ),
            )
          else
            ...List.generate(state.queue.length, (index) {
              final track = state.queue[index];
              final isPlaying = index == state.currentIndex;

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ListTile(
                  // Leading icon: equalizer if playing, music note otherwise.
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: isPlaying && state.isPlaying
                          ? const Icon(Icons.equalizer, color: Colors.white, size: 20)
                          : Icon(
                              Icons.music_note,
                              size: 20,
                              color: isPlaying
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.primary,
                            ),
                    ),
                  ),
                  title: Text(
                    track.title,
                    style: TextStyle(
                      fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                      color: isPlaying ? Theme.of(context).colorScheme.primary : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isPlaying
                      ? Icon(
                          Icons.play_arrow,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    // Jump to this track in the current queue.
                    ref.read(audioPlayerProvider.notifier).playTrack(
                          track,
                          fromQueue: state.queue,
                          startIndex: index,
                        );
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Shows a dialog to create a new playlist.
  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ref.read(playlistManagerProvider.notifier).createPlaylist(value.trim());
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(playlistManagerProvider.notifier).createPlaylist(controller.text.trim());
                Navigator.of(context).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// A single playlist row tile with an icon, name, track count, and play button.
class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const _PlaylistTile({
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Icon(
              Icons.queue_music,
              size: 22,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ),
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${playlist.tracks.length} tracks',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.play_circle_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: onTap,
        ),
        onTap: onTap,
      ),
    );
  }
}
