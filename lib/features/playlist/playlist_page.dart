import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:music_player/features/player/player_controller.dart';

class PlaylistPage extends ConsumerWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioPlayerProvider);
    final controller = ref.read(audioPlayerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add URL',
            onPressed: () => _showAddUrlDialog(context, ref),
          ),
        ],
      ),
      body: state.processing
          ? const Center(child: CircularProgressIndicator())
          : _buildPlaylist(context, ref, state, controller),
    );
  }

  Widget _buildPlaylist(
    BuildContext context,
    WidgetRef ref,
    AudioPlayerState state,
    AudioPlayerController controller,
  ) {
    if (state.totalDuration == null || state.totalDuration == Duration.zero) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.queue_music,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No tracks in queue',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Search for a track to add',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        _buildNowPlaying(context, ref, state, controller),
        const Divider(),
        _buildQueueSection(context, ref, state, controller),
      ],
    );
  }

  Widget _buildNowPlaying(
    BuildContext context,
    WidgetRef ref,
    AudioPlayerState state,
    AudioPlayerController controller,
  ) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.music_note, color: Colors.white, size: 24),
        ),
      ),
      title: const Text(
        'Now Playing',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${_formatDuration(state.currentPosition ?? Duration.zero)} / ${_formatDuration(state.totalDuration ?? Duration.zero)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.isPlaying)
            const Icon(Icons.play_arrow, color: Colors.green)
          else
            const Icon(Icons.pause, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildQueueSection(
    BuildContext context,
    WidgetRef ref,
    AudioPlayerState state,
    AudioPlayerController controller,
  ) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(
        child: Text(
          'Queue functionality coming soon',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  void _showAddUrlDialog(BuildContext context, WidgetRef ref) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Track URL'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'Enter audio URL',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final url = textController.text.trim();
              if (url.isNotEmpty) {
                _addTrack(context, ref, url);
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addTrack(BuildContext context, WidgetRef ref, String url) async {
    try {
      final controller = ref.read(audioPlayerProvider.notifier);
      await controller.setUrl(url);
      await controller.play();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playing: $url'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
