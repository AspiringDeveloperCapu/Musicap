import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/providers/download_manager.dart';

/// Shows a download panel as a modal bottom sheet.
class DownloadPanel {
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _DownloadPanelContent(),
    );
  }
}

class _DownloadPanelContent extends ConsumerWidget {
  const _DownloadPanelContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);

    // Group by status.
    final downloading = downloads.entries
        .where((e) => e.value.status == DownloadStatus.downloading)
        .toList();
    final completed = downloads.entries
        .where((e) => e.value.status == DownloadStatus.downloaded)
        .toList();
    final canceled = downloads.entries
        .where((e) => e.value.status == DownloadStatus.canceled)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.2,
      maxChildSize: 0.7,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle.
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.download,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Downloads',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content.
            Expanded(
              child: downloads.isEmpty
                  ? _emptyState(context)
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        if (downloading.isNotEmpty) ...[
                          _sectionHeader(context, 'Downloading', downloading.length),
                          ...downloading.map((e) => _DownloadTile(
                                trackId: e.key,
                                title: e.value.title,
                                artist: e.value.artist,
                                progress: e.value.progress,
                                status: DownloadStatus.downloading,
                              )),
                          const SizedBox(height: 8),
                        ],
                        if (completed.isNotEmpty) ...[
                          _sectionHeader(context, 'Completed', completed.length),
                          ...completed.map((e) => _DownloadTile(
                                trackId: e.key,
                                title: e.value.title,
                                artist: e.value.artist,
                                progress: 1.0,
                                status: DownloadStatus.downloaded,
                              )),
                          const SizedBox(height: 8),
                        ],
                        if (canceled.isNotEmpty) ...[
                          _sectionHeader(context, 'Canceled', canceled.length),
                          ...canceled.map((e) => _DownloadTile(
                                trackId: e.key,
                                title: e.value.title,
                                artist: e.value.artist,
                                progress: e.value.progress,
                                status: DownloadStatus.canceled,
                              )),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_done,
            size: 48,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'No downloads yet',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  final String trackId;
  final String title;
  final String artist;
  final double progress;
  final DownloadStatus status;

  const _DownloadTile({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.progress,
    required this.status,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      leading: _buildIcon(context),
      title: Text(
        title.isNotEmpty ? title : 'Track $trackId',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _buildSubtitle(context),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildIcon(BuildContext context) {
    switch (status) {
      case DownloadStatus.downloading:
        return SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              Text(
                '${(progress * 100).toInt()}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      case DownloadStatus.downloaded:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.download_done,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      case DownloadStatus.canceled:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.cancel_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.error,
          ),
        );
      default:
        return const SizedBox(width: 36, height: 36);
    }
  }

  Widget? _buildSubtitle(BuildContext context) {
    String? statusText;
    Color? statusColor;

    switch (status) {
      case DownloadStatus.downloading:
        statusText = 'Downloading... ${(progress * 100).toInt()}%';
        statusColor = Theme.of(context).colorScheme.primary;
        break;
      case DownloadStatus.downloaded:
        statusText = 'Download complete';
        statusColor = Theme.of(context).colorScheme.primary;
        break;
      case DownloadStatus.canceled:
        statusText = 'Download canceled';
        statusColor = Theme.of(context).colorScheme.error;
        break;
      default:
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
        if (statusText != null)
          Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: statusColor,
            ),
          ),
      ],
    );
  }

  Widget? _buildTrailing(BuildContext context, WidgetRef ref) {
    if (status == DownloadStatus.downloading) {
      return IconButton(
        icon: Icon(
          Icons.close,
          size: 18,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        ),
        onPressed: () {
          ref.read(downloadManagerProvider.notifier).cancelDownload(trackId);
        },
      );
    }
    return null;
  }
}
