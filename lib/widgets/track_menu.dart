import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/download_manager.dart';
import 'package:music_player/providers/playlist_manager.dart';

/// Shows the dialog that lets the user pick one of their playlists for [track].
void showAddToPlaylistDialog(BuildContext context, WidgetRef ref, Track track) {
  final playlists = ref.read(playlistManagerProvider);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Add "${track.title}" to playlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: playlists.isEmpty
            ? const Text('No playlists yet. Create one first.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    leading: Icon(
                      Icons.queue_music,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.tracks.length} tracks'),
                    onTap: () {
                      final added = ref
                          .read(playlistManagerProvider.notifier)
                          .addTrackToPlaylist(playlist.id, track);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            added
                                ? 'Added "${track.title}" to "${playlist.name}"'
                                : '"${track.title}" is already in "${playlist.name}"',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

/// Confirms and deletes a downloaded track's file.
void confirmDeleteDownload(BuildContext context, WidgetRef ref, Track track) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete download?'),
      content: Text(
        'Delete "${track.title}" from downloads? This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            ref.read(downloadManagerProvider.notifier).deleteDownload(track);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Deleted "${track.title}"'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

/// Shared "more" popup menu for a track: Play next, Add to queue,
/// Add to playlist, and Download / Delete download depending on state.
class TrackMenuButton extends ConsumerWidget {
  final Track track;
  final double iconSize;
  final Color? iconColor;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;

  const TrackMenuButton(
    this.track, {
    super.key,
    this.iconSize = 20,
    this.iconColor,
    this.padding = EdgeInsets.zero,
    this.constraints,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dlStatus = ref.watch(downloadManagerProvider)[track.id]?.status;
    final menuColor = iconColor ??
        Theme.of(context).colorScheme.onSurface.withOpacity(0.6);

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: iconSize, color: menuColor),
      padding: padding,
      constraints: constraints,
      onSelected: (value) {
        final controller = ref.read(audioPlayerProvider.notifier);
        switch (value) {
          case 'playNext':
            controller.playNext(track);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"${track.title}" will play next'),
                duration: const Duration(seconds: 1),
              ),
            );
          case 'queue':
            controller.addToQueue(track);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added "${track.title}" to queue'),
                duration: const Duration(seconds: 1),
              ),
            );
          case 'playlist':
            showAddToPlaylistDialog(context, ref, track);
          case 'download':
            ref.read(downloadManagerProvider.notifier).startDownload(track);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloading "${track.title}"'),
                duration: const Duration(seconds: 1),
              ),
            );
          case 'deleteDownload':
            confirmDeleteDownload(context, ref, track);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'playNext', child: Text('Play next')),
        const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
        const PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
        if (dlStatus == DownloadStatus.downloaded)
          const PopupMenuItem(
            value: 'deleteDownload',
            child: Text('Delete download'),
          )
        else
          const PopupMenuItem(value: 'download', child: Text('Download')),
      ],
    );
  }
}

/// Standard song row used across search, genre pages, and playlists:
/// thumbnail, title, artist, optional duration/download indicators, and
/// the shared [TrackMenuButton].
class TrackTile extends ConsumerWidget {
  final Track track;
  final VoidCallback? onTap;
  final bool showDuration;
  final bool showDownloadBadge;
  final double menuIconSize;

  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.showDuration = false,
    this.showDownloadBadge = false,
    this.menuIconSize = 20,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dlState = ref.watch(downloadManagerProvider)[track.id];
    final durationLabel = track.duration != null
        ? '${track.duration!.inMinutes}:${(track.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
        : null;

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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDuration && durationLabel != null)
            Text(
              durationLabel,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          if (showDownloadBadge &&
              dlState?.status == DownloadStatus.downloaded)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.download_done, size: 16, color: Colors.green),
            ),
          TrackMenuButton(track, iconSize: menuIconSize),
        ],
      ),
      onTap: onTap,
    );
  }
}
