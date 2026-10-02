import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/music_provider.dart';
import 'package:music_player/providers/playlist_manager.dart';
import 'package:music_player/providers/download_manager.dart';
import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/features/player/mini_player.dart';
import 'package:music_player/widgets/horizontal_row.dart';

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
                    color: Theme.of(context).colorScheme.onSurface
                        .withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tracks in this playlist',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface
                          .withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Play All and Download All buttons.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (playlist.tracks.isNotEmpty) {
                              ref
                                  .read(audioPlayerProvider.notifier)
                                  .playTrack(
                                    playlist.tracks.first,
                                    fromQueue: playlist.tracks,
                                    startIndex: 0,
                                  );
                            }
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: Text('Play All (${playlist.tracks.length})'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                        onPressed: () {
                          final notDownloaded = playlist.tracks.where((t) {
                            final dl = ref.read(downloadManagerProvider)[t.id];
                            return dl?.status != DownloadStatus.downloaded;
                          }).toList();
                          if (notDownloaded.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('All tracks already downloaded'),
                              ),
                            );
                          } else {
                            ref
                                .read(downloadManagerProvider.notifier)
                                .startDownloadAll(notDownloaded);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Downloading ${notDownloaded.length} track${notDownloaded.length > 1 ? 's' : ''}',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Download All'),
                      ),
                    ],
                  ),
                ),
                // Track list
                if (_seedTrack(playlist) != null)
                  _buildRecommendations(context, ref, playlist),
                Expanded(
                  child: ListView.builder(
                    itemCount: playlist.tracks.length,
                    itemBuilder: (context, index) {
                      final track = playlist.tracks[index];
                      return _buildTrackTile(
                        context,
                        ref,
                        playlist,
                        track,
                        index,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  /// First track with a video ID — used to seed recommendations.
  String? _seedTrack(Playlist playlist) {
    for (final track in playlist.tracks) {
      if (track.videoId != null) return track.videoId;
    }
    return null;
  }

  /// Horizontally scrollable "Recommended" section based on [playlist]'s
  /// first track. Tapping a card plays it; the + button adds it here.
  Widget _buildRecommendations(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
    final seed = _seedTrack(playlist)!;
    final recsAsync = ref.watch(trackRecommendationsProvider(seed));

    return recsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: LinearProgressIndicator(),
      ),
      // Recommendations are optional — hide on failure.
      error: (_, __) => const SizedBox.shrink(),
      data: (recs) {
        final existingIds = playlist.tracks.map((t) => t.id).toSet();
        final filtered = recs
            .where((t) => !existingIds.contains(t.id))
            .toList();
        if (filtered.isEmpty) return const SizedBox.shrink();
        return HorizontalRow(
          title: 'Recommended',
          height: 190,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final track = filtered[index];
            return HoverScale(
              onTap: () {
                ref
                    .read(audioPlayerProvider.notifier)
                    .playTrack(track, fromQueue: filtered, startIndex: index);
                ref.read(recentlyPlayedProvider.notifier).addTrack(track);
              },
              child: Container(
                width: 140,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: track.imageUrl != null
                              ? Image.network(
                                  track.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, url, error) =>
                                      const Center(
                                        child: Icon(Icons.music_note, size: 40),
                                      ),
                                )
                              : const Center(
                                  child: Icon(Icons.music_note, size: 40),
                                ),
                        ),
                        // Add to this playlist.
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Material(
                            color: Colors.black.withOpacity(0.55),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                final added = ref
                                    .read(playlistManagerProvider.notifier)
                                    .addTrackToPlaylist(playlist.id, track);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      added
                                          ? 'Added "${track.title}" to "${playlist.name}"'
                                          : '"${track.title}" is already in this playlist',
                                    ),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.add,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface
                            .withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
            ref
                .read(playlistManagerProvider.notifier)
                .removeTrackFromPlaylist(playlist.id, index);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed "${track.title}" from playlist'),
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
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'download', child: Text('Download')),
          const PopupMenuItem(
            value: 'remove',
            child: Text('Remove from playlist'),
          ),
        ],
      ),
      onTap: () {
        // Play this track starting from this position in the playlist.
        ref
            .read(audioPlayerProvider.notifier)
            .playTrack(track, fromQueue: playlist.tracks, startIndex: index);
      },
    );
  }

  /// Shows a dialog to rename the playlist.
  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ref
                  .read(playlistManagerProvider.notifier)
                  .renamePlaylist(playlist.id, value.trim());
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
                ref
                    .read(playlistManagerProvider.notifier)
                    .renamePlaylist(playlist.id, controller.text.trim());
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
  void _confirmDeletePlaylist(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
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
              ref
                  .read(playlistManagerProvider.notifier)
                  .deletePlaylist(playlist.id);
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
