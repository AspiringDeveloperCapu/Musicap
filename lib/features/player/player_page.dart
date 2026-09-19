import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/providers/download_manager.dart';
import 'package:music_player/models/track.dart';

/// Full-screen "Now Playing" page. Shows album art, track info, a seek bar,
/// playback controls, shuffle/loop toggles, and a reorderable queue list.
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioPlayerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
      ),
      // ListView makes the entire page scrollable, including the queue list.
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        children: [
          // Album art placeholder — shows a loading spinner while buffering.
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: state.processing
                    ? const CircularProgressIndicator()
                    : Icon(
                        Icons.music_note,
                        size: 80,
                        color: Theme.of(context).colorScheme.primary,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Track title.
          Center(
            child: Text(
              state.currentTitle.isNotEmpty ? state.currentTitle : 'No Track',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),

          // Artist name.
          Center(
            child: Text(
              state.currentArtist.isNotEmpty ? state.currentArtist : 'Unknown Artist',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 32),

          // Interactive seek bar — handles drag-to-seek.
          _InteractiveSeekBar(
            position: state.currentPosition ?? Duration.zero,
            duration: state.totalDuration ?? Duration.zero,
            onSeek: (position) {
              ref.read(audioPlayerProvider.notifier).seek(position);
            },
          ),
          const SizedBox(height: 8),

          // Time labels (current position / total duration).
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(state.currentPosition ?? Duration.zero),
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                _formatDuration(state.totalDuration ?? Duration.zero),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Main playback controls: previous, play/pause, next.
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
          const SizedBox(height: 24),

          // Shuffle, loop, and download toggles.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle,
                  color: state.isShuffleEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: () {
                  ref.read(audioPlayerProvider.notifier).setShuffleMode(!state.isShuffleEnabled);
                },
              ),
              const SizedBox(width: 24),
              // Download button for current track.
              _buildDownloadButton(context, ref, state),
              const SizedBox(width: 24),
              IconButton(
                icon: Icon(
                  state.loopMode == LoopMode.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                  color: state.loopMode != LoopMode.off
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: () {
                  // Cycle through: off -> all -> one -> off
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

          // Up Next queue section — only shown when there are tracks in the queue.
          if (state.queue.isNotEmpty) ...[
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Up Next',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
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
            const SizedBox(height: 8),
            // Reorderable list — drag tracks to rearrange the queue.
            // Default drag handles disabled; using a custom drag icon instead.
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: state.queue.length,
              onReorder: (oldIndex, newIndex) {
                ref.read(audioPlayerProvider.notifier).reorderQueue(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final track = state.queue[index];
                final isPlaying = index == state.currentIndex;

                return MouseRegion(
                  key: ValueKey(track.id + '_' + index.toString()),
                  cursor: SystemMouseCursors.click,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    // Leading: track number, or equalizer icon if currently playing.
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
                            : isPlaying
                                ? Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                      ),
                    ),
                    title: Text(
                      track.title,
                      style: TextStyle(
                        fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                        color: isPlaying ? Theme.of(context).colorScheme.primary : null,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12),
                    ),
                    // Trailing: 3-dot menu (remove) + drag handle for reordering.
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                          ),
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'remove') {
                              ref.read(audioPlayerProvider.notifier).removeFromQueue(index);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove from queue'),
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        ReorderableDragStartListener(
                          index: index,
                          child: Icon(
                            Icons.reorder,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                          ),
                        ),
                      ],
                    ),
                    // Tapping a track jumps to it in the queue.
                    onTap: () {
                      ref.read(audioPlayerProvider.notifier).playTrack(
                            track,
                            fromQueue: state.queue,
                            startIndex: index,
                          );
                    },
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Formats a Duration into "MM:SS" string.
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  /// Builds the download button for the current track.
  Widget _buildDownloadButton(BuildContext context, WidgetRef ref, AudioPlayerState state) {
    if (state.currentUrl == null) return const SizedBox(width: 48, height: 48);

    final track = Track(
      id: state.currentIndex.toString(),
      title: state.currentTitle,
      artist: state.currentArtist,
      audioUrl: state.currentUrl!,
    );

    final dlState = ref.watch(downloadManagerProvider)[track.id];

    if (dlState?.status == DownloadStatus.downloading) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              value: dlState!.progress,
              strokeWidth: 2.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final isDownloaded = dlState?.status == DownloadStatus.downloaded;

    return IconButton(
      icon: Icon(
        isDownloaded ? Icons.download_done : Icons.download,
        color: isDownloaded
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
      ),
      onPressed: () {
        ref.read(downloadManagerProvider.notifier).simulateDownload(track);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloading "${track.title}"'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
    );
  }
}

/// A seek bar that supports drag-to-seek. Pauses position updates while
/// the user is dragging to avoid jitter.
class _InteractiveSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const _InteractiveSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<_InteractiveSeekBar> createState() => _InteractiveSeekBarState();
}

class _InteractiveSeekBarState extends State<_InteractiveSeekBar> {
  bool _isDragging = false;
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final value = widget.duration.inMilliseconds > 0
        ? (_isDragging
            ? _dragValue
            : widget.position.inMilliseconds / widget.duration.inMilliseconds)
        : 0.0;

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: Theme.of(context).colorScheme.primary,
        inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        thumbColor: Theme.of(context).colorScheme.primary,
      ),
      child: Slider(
        value: value.clamp(0.0, 1.0),
        onChangeStart: (v) {
          setState(() {
            _isDragging = true;
            _dragValue = v;
          });
        },
        onChanged: (v) {
          setState(() {
            _dragValue = v.clamp(0.0, 1.0);
          });
        },
        onChangeEnd: (v) {
          setState(() {
            _isDragging = false;
          });
          final clamped = v.clamp(0.0, 1.0);
          final position = Duration(
            milliseconds: (clamped * widget.duration.inMilliseconds).round(),
          );
          widget.onSeek(position);
        },
      ),
    );
  }
}

/// Row of playback control buttons: previous, play/pause, and next.
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
          icon: isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
          onPressed: onPlayPause,
          label: isPlaying ? 'Pause' : 'Play',
          size: 56,
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

/// A single playback control button with a tooltip and pointer cursor.
/// Disabled buttons are dimmed and non-interactive.
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String label;
  final double size;

  const _ControlButton({
    required this.icon,
    this.onPressed,
    required this.label,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: MouseRegion(
        cursor: onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: IconButton(
          icon: Icon(icon, size: size),
          onPressed: onPressed,
          color: onPressed != null
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
        ),
      ),
    );
  }
}
