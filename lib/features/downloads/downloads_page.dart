import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/download_manager.dart';
import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/features/player/download_bar.dart';

/// Downloads page showing all downloaded songs with sort, storage info,
/// swipe-to-delete, and tap-to-play.
class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  String _sortBy = 'date';

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);
    final downloaded = manager.getDownloaded(sortBy: _sortBy);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          // Sort menu.
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) => setState(() => _sortBy = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'date', child: Text('Sort by date')),
              const PopupMenuItem(value: 'name', child: Text('Sort by name')),
              const PopupMenuItem(value: 'artist', child: Text('Sort by artist')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Storage info bar.
          _buildStorageInfo(context, downloaded.length),
          const Divider(height: 1),
          // Downloaded tracks list.
          Expanded(
            child: downloaded.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    itemCount: downloaded.length,
                    itemBuilder: (context, index) {
                      final entry = downloaded[index];
                      return _buildDownloadedTile(
                        context,
                        ref,
                        entry.key,
                        entry.value,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageInfo(BuildContext context, int count) {
    // Simulated storage — each track ~4MB.
    final sizeMB = count * 4;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Row(
        children: [
          Icon(
            Icons.storage,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(width: 8),
          Text(
            '$count song${count != 1 ? 's' : ''} • ${sizeMB}MB',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const Spacer(),
          if (count > 0)
            TextButton(
              onPressed: () => _playAllDownloaded(context, ref),
              child: const Text('Play all'),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_done,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No downloaded songs',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Songs you download will appear here',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadedTile(
    BuildContext context,
    WidgetRef ref,
    String trackId,
    DownloadState dl,
  ) {
    return Dismissible(
      key: Key(trackId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove download?'),
            content: Text('Remove "${dl.title}" from downloads?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        ref.read(downloadManagerProvider.notifier).removeFromList(trackId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${dl.title}"'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Icon(
              Icons.music_note,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        title: Text(
          dl.title.isNotEmpty ? dl.title : 'Track $trackId',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          dl.artist.isNotEmpty ? dl.artist : 'Unknown artist',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          onSelected: (value) {
            if (value == 'play') {
              _playTrack(context, ref, dl, trackId);
            } else if (value == 'remove') {
              ref.read(downloadManagerProvider.notifier).removeFromList(trackId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Removed "${dl.title}"'),
                  duration: const Duration(seconds: 1),
                ),
              );
            } else if (value == 'delete') {
              ref.read(downloadManagerProvider.notifier).deleteDownload(
                Track(
                  id: trackId,
                  title: dl.title,
                  artist: dl.artist,
                  audioUrl: dl.audioUrl,
                ),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Deleted "${dl.title}"'),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'play', child: Text('Play')),
            const PopupMenuItem(value: 'remove', child: Text('Remove from list')),
            const PopupMenuItem(value: 'delete', child: Text('Delete file')),
          ],
        ),
        onTap: () => _playTrack(context, ref, dl, trackId),
      ),
    );
  }

  void _playTrack(
    BuildContext context,
    WidgetRef ref,
    DownloadState dl,
    String trackId,
  ) {
    final track = Track(
      id: trackId,
      title: dl.title,
      artist: dl.artist,
      audioUrl: dl.audioUrl,
    );
    // Play as a single track queue.
    ref.read(audioPlayerProvider.notifier).playTrack(track);
  }

  void _playAllDownloaded(BuildContext context, WidgetRef ref) {
    final manager = ref.read(downloadManagerProvider.notifier);
    final downloaded = manager.getDownloaded();
    if (downloaded.isEmpty) return;

    final tracks = downloaded
        .map((e) => Track(
              id: e.key,
              title: e.value.title,
              artist: e.value.artist,
              audioUrl: e.value.audioUrl,
            ))
        .toList();

    ref.read(audioPlayerProvider.notifier).playTrack(
          tracks.first,
          fromQueue: tracks,
          startIndex: 0,
        );
  }
}
