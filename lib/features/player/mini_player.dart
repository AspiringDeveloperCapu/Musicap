import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/features/player/player_controller.dart';

/// Reusable mini player widget that shows current track info, progress,
/// and playback controls. Used at the bottom of the main screen and
/// any pushed route that should keep the mini player visible.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  bool _isDragging = false;
  double _dragValue = 0;
  bool _showVolume = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioPlayerProvider);

    if (state.currentTitle.isEmpty) return const SizedBox.shrink();

    final position = state.totalDuration != null &&
            state.totalDuration!.inMilliseconds > 0 &&
            state.currentPosition != null
        ? (_isDragging
            ? _dragValue
            : (state.currentPosition!.inMilliseconds /
                    state.totalDuration!.inMilliseconds)
                .clamp(0.0, 1.0))
        : 0.0;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress slider.
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Slider(
              value: position,
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
                final pos = Duration(
                  milliseconds:
                      (clamped * state.totalDuration!.inMilliseconds).round(),
                );
                ref.read(audioPlayerProvider.notifier).seek(pos);
              },
            ),
          ),

          // Collapsible volume row — shown when the volume icon is tapped.
          if (_showVolume)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      state.volume == 0
                          ? Icons.volume_off
                          : state.volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                      size: 18,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                    onPressed: () =>
                        ref.read(audioPlayerProvider.notifier).toggleMute(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor:
                            Theme.of(context).colorScheme.primary,
                        inactiveTrackColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        thumbColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: Slider(
                        value: state.volume.clamp(0.0, 1.0),
                        onChanged: (v) =>
                            ref.read(audioPlayerProvider.notifier).setVolume(v),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${(state.volume * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Track info row — tapping navigates to full player.
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 4, bottom: 8),
            child: GestureDetector(
              onTap: () {
                if (ModalRoute.of(context)?.settings.name != '/player') {
                  Navigator.pushNamed(context, '/player');
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
              children: [
                // Album art.
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildMiniAlbumArt(context),
                ),
                const SizedBox(width: 10),
                // Track title and artist.
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.currentTitle,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        state.currentArtist,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Playback controls.
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    icon: const Icon(Icons.skip_previous, size: 24),
                    onPressed: () => ref
                        .read(audioPlayerProvider.notifier)
                        .seekToPrevious(),
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    icon: Icon(
                      state.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      size: 40,
                    ),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () =>
                        ref.read(audioPlayerProvider.notifier).playOrPause(),
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    icon: const Icon(Icons.skip_next, size: 24),
                    onPressed: () => ref
                        .read(audioPlayerProvider.notifier)
                        .seekToNext(),
                  ),
                ),
                // Volume toggle — shows/hides the volume slider row.
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    icon: Icon(
                      state.volume == 0
                          ? Icons.volume_off
                          : state.volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                      size: 22,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(
                              alpha: _showVolume ? 1.0 : 0.5),
                    ),
                    onPressed: () =>
                        setState(() => _showVolume = !_showVolume),
                  ),
                ),
                // Close button.
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                    ),
                    onPressed: () => ref
                        .read(audioPlayerProvider.notifier)
                        .stopAndClear(),
                  ),
                ),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniAlbumArt(BuildContext context) {
    // We need to watch the audioPlayerProvider to get the current track's imageUrl.
    // Since MiniPlayer is a ConsumerWidget, we can access ref here.
    return Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(audioPlayerProvider);
        String? imageUrl;
        if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
          imageUrl = state.queue[state.currentIndex].imageUrl;
        }
        if (imageUrl != null) {
          return Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, url, error) => Icon(
              Icons.music_note,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        return Icon(
          Icons.music_note,
          size: 22,
          color: Theme.of(context).colorScheme.primary,
        );
      },
    );
  }
}
