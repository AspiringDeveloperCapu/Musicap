import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/playlist_manager.dart';
import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/features/player/mini_player.dart';

/// Detail view for a single playlist. Shows the playlist's tracks with options
/// to play all, rename, or remove individual tracks.
class PlaylistDetailPage extends ConsumerWidget {
  final String playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistManagerProvider);
    final playlist = playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => Playlist(id: '', name: 'Unknown', tracks: []),
    );

    if (playlist.id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Playlist')),
        body: const Center(child: Text('Playlist not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          // Rename button
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _showRenameDialog(context, ref, playlist),
          ),
          // Delete playlist button
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _confirmDeletePlaylist(context, ref, playlist),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
      body: playlist.tracks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tracks in this playlist',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Play All button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (playlist.tracks.isNotEmpty) {
                          ref.read(audioPlayerProvider.notifier).playTrack(
                            playlist.tracks.first,
                            fromQueue: playlist.tracks,
                            startIndex: 0,
                          );
                        }
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Play All (${playlist.tracks.length} tracks)'),
                    ),
                  ),
                ),
                // Track list
                Expanded(
                  child: ListView.builder(
                    itemCount: playlist.tracks.length,
                    itemBuilder: (context, index) {
                      final track = playlist.tracks[index];
                      return _buildTrackTile(context, ref, playlist, track, index);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  /// Builds a track list tile with play on tap and remove from playlist option.
  Widget _buildTrackTile(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    Track track,
    int index,
  ) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
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
          if (value == 'remove') {
            ref.read(playlistManagerProvider.notifier).removeTrackFromPlaylist(
              playlist.id,
              index,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed "${track.title}" from playlist'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'remove',
            child: Text('Remove from playlist'),
          ),
        ],
      ),
      onTap: () {
        // Play this track starting from this position in the playlist.
        ref.read(audioPlayerProvider.notifier).playTrack(
          track,
          fromQueue: playlist.tracks,
          startIndex: index,
        );
      },
    );
  }

  /// Shows a dialog to rename the playlist.
  void _showRenameDialog(BuildContext context, WidgetRef ref, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ref.read(playlistManagerProvider.notifier).renamePlaylist(
                playlist.id,
                value.trim(),
              );
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
                ref.read(playlistManagerProvider.notifier).renamePlaylist(
                  playlist.id,
                  controller.text.trim(),
                );
                Navigator.of(context).pop();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog before deleting the playlist.
  void _confirmDeletePlaylist(BuildContext context, WidgetRef ref, Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(playlistManagerProvider.notifier).deletePlaylist(playlist.id);
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to library
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
