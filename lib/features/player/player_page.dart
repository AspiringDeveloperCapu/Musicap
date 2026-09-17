import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:music_player/features/player/player_controller.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioPlayerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Artwork
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Icon(Icons.music_note, color: Colors.white, size: 48),
              ),
            ),
            const SizedBox(height: 24),

            // Track info
            Column(
              children: [
                Text(
                  'Now Playing',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sample Track',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Artist Name',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const Spacer(),

            // Seek bar + progress
            _SeekBar(
              position: state.currentPosition ?? Duration.zero,
              duration: state.totalDuration ?? Duration.zero,
              onSeek: () {
                // Seek to 30 seconds as example
                ref.read(audioPlayerProvider.notifier).seek(Duration(seconds: 30));
              },
            ),
            const SizedBox(height: 16),

            // Duration text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state.currentPosition != null
                      ? _formatDuration(state.currentPosition!)
                      : '0:00',
                ),
                Text(
                  state.totalDuration != null
                      ? _formatDuration(state.totalDuration!)
                      : '0:00',
                ),
              ],
            ),
            const Spacer(),

            // Playback controls - using state from provider
            _PlaybackControls(
              isPlaying: state.isPlaying,
              hasNext: state.hasNext,
              hasPrevious: state.hasPrevious,
              onPlayPause: () {
                ref.read(audioPlayerProvider.notifier).playOrPause();
              },
              onNext: () {
                ref.read(audioPlayerProvider.notifier).seekToNext();
              },
              onPrevious: () {
                ref.read(audioPlayerProvider.notifier).seekToPrevious();
              },
            ),
            const SizedBox(height: 16),

            // Shuffle & Loop controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: state.isShuffleEnabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  onPressed: () {
                    ref.read(audioPlayerProvider.notifier).setShuffleMode(!state.isShuffleEnabled);
                  },
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: Icon(
                    state.loopMode == LoopMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color: state.loopMode != LoopMode.off
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  onPressed: () {
                    final nextMode = state.loopMode == LoopMode.off
                        ? LoopMode.all
                        : state.loopMode == LoopMode.all
                            ? LoopMode.one
                            : LoopMode.off;
                    ref.read(audioPlayerProvider.notifier).setLoopMode(nextMode);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

class _SeekBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final VoidCallback onSeek;

  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: duration.inSeconds > 0 ? position.inSeconds / duration.inSeconds : 0.0,
          semanticsLabel: 'Progress',
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(position),
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              _formatDuration(duration),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

class _PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final bool hasNext;
  final bool hasPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const _PlaybackControls({
    required this.isPlaying,
    required this.hasNext,
    required this.hasPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlButton(
          icon: Icons.skip_previous,
          onPressed: hasPrevious ? onPrevious : null,
          label: 'Prev',
        ),
        const SizedBox(width: 24),
        _ControlButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          onPressed: onPlayPause,
          label: isPlaying ? 'Pause' : 'Play',
        ),
        const SizedBox(width: 24),
        _ControlButton(
          icon: Icons.skip_next,
          onPressed: hasNext ? onNext : null,
          label: 'Next',
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String label;

  const _ControlButton({
    required this.icon,
    this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon, size: 36),
        onPressed: onPressed,
        color: onPressed != null
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
      ),
    );
  }
}