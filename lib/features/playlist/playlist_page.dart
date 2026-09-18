import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/providers/music_provider.dart';
import 'package:music_player/models/track.dart';

class PlaylistPage extends ConsumerWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioPlayerProvider);
    final playlists = ref.watch(playlistsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
      ),
      body: ListView(
        children: [
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
          ...playlists.map((playlist) => _PlaylistTile(
                playlist: playlist,
                onTap: () {
                  ref.read(audioPlayerProvider.notifier).playTrack(
                        playlist.tracks.first,
                        fromQueue: playlist.tracks,
                        startIndex: 0,
                      );
                },
              )),
          const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Now Playing',
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
                ),
              );
            }),
        ],
      ),
    );
  }
}

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
