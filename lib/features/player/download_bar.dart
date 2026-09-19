import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/providers/download_manager.dart';

/// A collapsible download bar that shows at the bottom of the screen.
/// Displays active downloads with progress and completed downloads.
/// Tapping the bar expands it to show all downloads; tapping again collapses.
class DownloadBar extends ConsumerStatefulWidget {
  const DownloadBar({super.key});

  @override
  ConsumerState<DownloadBar> createState() => _DownloadBarState();
}

class _DownloadBarState extends ConsumerState<DownloadBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadManagerProvider);

    // Filter to only show downloading or downloaded items.
    final activeOrCompleted = downloads.entries
        .where((e) =>
            e.value.status == DownloadStatus.downloading ||
            e.value.status == DownloadStatus.downloaded)
        .toList();

    // Find the most recent active download for the compact bar.
    final activeDownload = activeOrCompleted
        .where((e) => e.value.status == DownloadStatus.downloading)
        .toList();

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compact bar — always visible when there are downloads.
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    // Download icon.
                    Icon(
                      Icons.download,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    // Status text.
                    Expanded(
                      child: activeDownload.isNotEmpty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Downloading ${activeDownload.length} track${activeDownload.length > 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // Show overall progress of the first active download.
                                LinearProgressIndicator(
                                  value: activeDownload.first.value.progress,
                                  minHeight: 3,
                                  backgroundColor:
                                      Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ],
                            )
                          : activeOrCompleted.isNotEmpty
                              ? Text(
                                  '${activeOrCompleted.length} download${activeOrCompleted.length > 1 ? 's' : ''} complete',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : Text(
                                  'Downloads',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.5),
                                  ),
                                ),
                    ),
                    const SizedBox(width: 8),
                    // Expand/collapse arrow.
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 22,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ],
                ),
              ),
            ),
            // Expanded list of downloads.
            if (_expanded)
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: activeOrCompleted.length,
                  itemBuilder: (context, index) {
                    final entry = activeOrCompleted[index];
                    final trackId = entry.key;
                    final dl = entry.value;

                    return _DownloadItem(
                      trackId: trackId,
                      title: dl.title,
                      artist: dl.artist,
                      status: dl.status,
                      progress: dl.progress,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single download item row in the expanded download bar.
class _DownloadItem extends StatelessWidget {
  final String trackId;
  final String title;
  final String artist;
  final DownloadStatus status;
  final double progress;

  const _DownloadItem({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.status,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Status icon.
          SizedBox(
            width: 28,
            height: 28,
            child: status == DownloadStatus.downloading
                ? CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.5,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : Icon(
                    Icons.download_done,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
          const SizedBox(width: 12),
          // Track info.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.isNotEmpty ? title : 'Track $trackId',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (artist.isNotEmpty)
                  Text(
                    artist,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Progress percentage or checkmark.
          if (status == DownloadStatus.downloading)
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
        ],
      ),
    );
  }
}
