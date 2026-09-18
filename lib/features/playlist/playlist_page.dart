import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:music_player/features/player/player_controller.dart';

class PlaylistPage extends ConsumerWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioPlayerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
      ),
      body: state.queue.isEmpty
          ? Center(
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
                    'Play a track or playlist to get started',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: state.queue.length,
              itemBuilder: (context, index) {
                final track = state.queue[index];
                final isPlaying = index == state.currentIndex;

                return ListTile(
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
                    ref.read(audioPlayerProvider.notifier).playTrack(
                          track,
                          fromQueue: state.queue,
                          startIndex: index,
                        );
                  },
                );
              },
            ),
    );
  }
}
