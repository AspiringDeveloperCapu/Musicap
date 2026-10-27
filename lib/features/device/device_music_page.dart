import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/download_manager.dart';
import 'package:music_player/providers/music_provider.dart';
import 'package:music_player/providers/playlist_manager.dart';
import 'package:music_player/widgets/track_menu.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:music_player/features/downloads/download_art_stub.dart'
    if (dart.library.js_interop) 'package:music_player/features/downloads/download_art_web.dart'
    if (dart.library.io) 'package:music_player/features/downloads/download_art_io.dart';

/// Combined "On Device" page: downloads and MediaStore-scanned local files
/// behind a section filter. Downloaded files that MediaStore also indexes
/// are hidden from the device list to avoid duplicates.
class DeviceMusicPage extends ConsumerStatefulWidget {
  const DeviceMusicPage({super.key});

  @override
  ConsumerState<DeviceMusicPage> createState() => _DeviceMusicPageState();
}

class _DeviceMusicPageState extends ConsumerState<DeviceMusicPage> {
  static const _channel = MethodChannel('music_player/local_audio');

  String _filter = 'downloads'; // 'downloads' | 'device' | 'all'
  String _sortBy = 'date';

  List<Track>? _localTracks;
  final Map<String, int> _mediaIds = {};
  bool _scanning = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
      _permissionDenied = false;
      _permissionPermanentlyDenied = false;
    });

    var status = await Permission.audio.status;
    if (!status.isGranted) status = await Permission.audio.request();
    if (!status.isGranted) status = await Permission.storage.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _permissionDenied = true;
          _permissionPermanentlyDenied = status.isPermanentlyDenied;
        });
      }
      return;
    }

    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listSongs');
      // Paths already registered as downloads — hide them from the
      // device list so a track never shows up in both sections.
      final downloadPaths = <String>{};
      for (final dl in ref.read(downloadManagerProvider.notifier).getDownloaded()) {
        final p = dl.value.filePath;
        if (p != null && p.isNotEmpty) downloadPaths.add(p.toLowerCase());
      }

      final tracks = <Track>[];
      _mediaIds.clear();
      for (final entry in raw ?? const <dynamic>[]) {
        if (entry is! Map) continue;
        final item = Map<String, dynamic>.from(entry);
        final id = item['id']?.toString() ?? '';
        final path = item['path']?.toString() ?? '';
        if (id.isEmpty && path.isEmpty) continue;
        if (downloadPaths.contains(path.toLowerCase())) continue;

        final title = item['title']?.toString() ?? '';
        final artist = item['artist']?.toString() ?? '';
        final durationMs = (item['durationMs'] as num?)?.toInt() ?? 0;
        final trackId = 'local:$id';
        final mediaId = int.tryParse(id);
        if (mediaId != null) _mediaIds[trackId] = mediaId;
        tracks.add(Track(
          id: trackId,
          title: title.isNotEmpty ? title : path.split('/').last,
          artist: artist.isNotEmpty ? artist : 'Unknown artist',
          audioUrl: item['uri']?.toString() ?? 'file://$path',
          duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
        ));
      }
      if (mounted) setState(() => _localTracks = tracks);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Scan failed');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _deleteLocal(Track track) async {
    final mediaId = _mediaIds[track.id];
    if (mediaId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(
          'Delete "${track.title}" from this device? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final ok = await _channel.invokeMethod<bool>('deleteSong', {
        'mediaId': mediaId,
      });
      if (!mounted) return;
      if (ok == true) {
        setState(() {
          _localTracks?.removeWhere((t) => t.id == track.id);
          _mediaIds.remove(track.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${track.title}"'),
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete "${track.title}"')),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: ${e.message}')),
        );
      }
    }
  }

  void _playLocalAt(int index) {
    final tracks = _localTracks;
    if (tracks == null || index < 0 || index >= tracks.length) return;
    final track = tracks[index];
    ref.read(audioPlayerProvider.notifier).playTrack(
          track,
          fromQueue: tracks,
          startIndex: index,
        );
    ref.read(recentlyPlayedProvider.notifier).addTrack(track);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(downloadManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('On Device'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan',
            onPressed: _scanning ? null : _loadLocal,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'downloads', label: Text('Downloads')),
                ButtonSegment(value: 'device', label: Text('On Device')),
                ButtonSegment(value: 'all', label: Text('All')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(child: _buildFilteredBody()),
        ],
      ),
    );
  }

  Widget _buildFilteredBody() {
    switch (_filter) {
      case 'downloads':
        return _buildDownloadsSection();
      case 'device':
        return _buildDeviceSection();
      case 'all':
      default:
        return ListView(
          children: [
            _buildDownloadsHeader(),
            ..._buildDownloadTiles(),
            const SizedBox(height: 8),
            const Divider(height: 1),
            _buildDeviceHeader(),
            ..._buildDeviceTiles(),
          ],
        );
    }
  }

  // ---- Downloads section ----

  Widget _buildDownloadsSection() {
    final manager = ref.read(downloadManagerProvider.notifier);
    final downloaded = manager.getDownloaded(sortBy: _sortBy);
    if (downloaded.isEmpty) {
      return _emptyMessage(
        icon: Icons.download_done,
        title: 'No downloaded songs',
        subtitle: 'Songs you download will appear here',
      );
    }
    return Column(
      children: [
        _storageBar(context, downloaded.length, manager.totalBytes),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              for (final entry in downloaded)
                _downloadTile(context, entry.key, entry.value),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDownloadTiles() {
    final manager = ref.read(downloadManagerProvider.notifier);
    final downloaded = manager.getDownloaded(sortBy: _sortBy);
    if (downloaded.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No downloads',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ),
      ];
    }
    return [
      _storageBar(context, downloaded.length, manager.totalBytes),
      for (final entry in downloaded)
        _downloadTile(context, entry.key, entry.value),
    ];
  }

  Widget _buildDownloadsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Text(
            'Downloads',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, size: 20),
            tooltip: 'Sort downloads',
            onSelected: (value) => setState(() => _sortBy = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'date', child: Text('Sort by date')),
              PopupMenuItem(value: 'name', child: Text('Sort by name')),
              PopupMenuItem(value: 'artist', child: Text('Sort by artist')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _storageBar(BuildContext context, int count, int totalBytes) {
    final sizeMB = totalBytes / (1024 * 1024);
    final sizeLabel =
        sizeMB >= 100 ? sizeMB.toStringAsFixed(0) : sizeMB.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withOpacity(0.3),
      child: Row(
        children: [
          Icon(
            Icons.storage,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(width: 8),
          Text(
            '$count song${count != 1 ? 's' : ''} • ${sizeLabel}MB',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const Spacer(),
          if (count > 0)
            TextButton(
              onPressed: () => _playAllDownloaded(),
              child: const Text('Play all'),
            ),
        ],
      ),
    );
  }

  Widget _downloadTile(BuildContext context, String trackId, DownloadState dl) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: buildDownloadArt(context, dl),
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
            _playDownload(trackId, dl);
          } else if (value == 'playNext') {
            _queueDownloadNext(trackId, dl);
          } else if (value == 'addQueue') {
            _queueDownload(trackId, dl);
          } else if (value == 'addToPlaylist') {
            _showAddDownloadToPlaylist(trackId, dl);
          } else if (value == 'remove') {
            ref.read(downloadManagerProvider.notifier).removeFromList(trackId);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed "${dl.title}"'),
                duration: const Duration(seconds: 1),
              ),
            );
          } else if (value == 'delete') {
            _confirmDeleteDownload(trackId, dl);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'play', child: Text('Play')),
          PopupMenuItem(value: 'playNext', child: Text('Play next')),
          PopupMenuItem(value: 'addQueue', child: Text('Add to queue')),
          PopupMenuItem(value: 'addToPlaylist', child: Text('Add to playlist')),
          PopupMenuItem(value: 'remove', child: Text('Remove from list')),
          PopupMenuItem(value: 'delete', child: Text('Delete download')),
        ],
      ),
      onTap: () => _playDownload(trackId, dl),
    );
  }

  void _playDownload(String trackId, DownloadState dl) {
    final audioUrl = (!kIsWeb && dl.filePath != null)
        ? Uri.file(dl.filePath!).toString()
        : dl.audioUrl;
    ref.read(audioPlayerProvider.notifier).playTrack(Track(
          id: trackId,
          title: dl.title,
          artist: dl.artist,
          imageUrl: dl.imageUrl,
          audioUrl: audioUrl,
          videoId: dl.videoId,
        ));
  }

  void _queueDownloadNext(String trackId, DownloadState dl) {
    final url = (!kIsWeb && dl.filePath != null)
        ? Uri.file(dl.filePath!).toString()
        : dl.audioUrl;
    ref.read(audioPlayerProvider.notifier).playNext(Track(
          id: trackId,
          title: dl.title,
          artist: dl.artist,
          audioUrl: url,
          videoId: dl.videoId,
        ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${dl.title}" will play next'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _queueDownload(String trackId, DownloadState dl) {
    final url = (!kIsWeb && dl.filePath != null)
        ? Uri.file(dl.filePath!).toString()
        : dl.audioUrl;
    ref.read(audioPlayerProvider.notifier).addToQueue(Track(
          id: trackId,
          title: dl.title,
          artist: dl.artist,
          audioUrl: url,
          videoId: dl.videoId,
        ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${dl.title}" to queue'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _playAllDownloaded() {
    final manager = ref.read(downloadManagerProvider.notifier);
    final downloaded = manager.getDownloaded();
    if (downloaded.isEmpty) return;
    final tracks = downloaded
        .map((e) => Track(
              id: e.key,
              title: e.value.title,
              artist: e.value.artist,
              imageUrl: e.value.imageUrl,
              audioUrl: !kIsWeb && e.value.filePath != null
                  ? Uri.file(e.value.filePath!).toString()
                  : e.value.audioUrl,
              videoId: e.value.videoId,
            ))
        .toList();
    ref.read(audioPlayerProvider.notifier).playTrack(
          tracks.first,
          fromQueue: tracks,
          startIndex: 0,
        );
  }

  void _showAddDownloadToPlaylist(String trackId, DownloadState dl) {
    final playlists = ref.read(playlistManagerProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add "${dl.title}" to playlist'),
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
                            .addTrackToPlaylist(
                              playlist.id,
                              Track(
                                id: trackId,
                                title: dl.title,
                                artist: dl.artist,
                                audioUrl: dl.audioUrl,
                              ),
                            );
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              added
                                  ? 'Added "${dl.title}" to "${playlist.name}"'
                                  : '"${dl.title}" is already in "${playlist.name}"',
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

  void _confirmDeleteDownload(String trackId, DownloadState dl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete download?'),
        content:
            Text('Delete "${dl.title}" from downloads? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(downloadManagerProvider.notifier).deleteDownload(
                    Track(
                        id: trackId,
                        title: dl.title,
                        artist: dl.artist,
                        audioUrl: dl.audioUrl),
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Deleted "${dl.title}"'),
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

  // ---- Device section ----

  Widget _buildDeviceSection() {
    if (_scanning && _localTracks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permissionDenied) {
      return _permissionMessage();
    }
    if (_error != null) {
      return _emptyMessage(
        icon: Icons.error_outline,
        title: 'Could not read local music',
        subtitle: _error!,
        actionLabel: 'Retry',
        onAction: _loadLocal,
      );
    }
    final tracks = _localTracks ?? const <Track>[];
    if (tracks.isEmpty) {
      return _emptyMessage(
        icon: Icons.music_off,
        title: 'No music found on this device',
        subtitle: 'Files in your download folder are listed under Downloads',
        actionLabel: 'Rescan',
        onAction: _loadLocal,
      );
    }
    return ListView(
      children: _buildDeviceTiles(),
    );
  }

  Widget _buildDeviceHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Text(
            'On This Device',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Rescan',
            onPressed: _scanning ? null : _loadLocal,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDeviceTiles() {
    if (_scanning && _localTracks == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_permissionDenied) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: _permissionMessage(),
        ),
      ];
    }
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: _emptyMessage(
            icon: Icons.error_outline,
            title: 'Could not read local music',
            subtitle: _error!,
            actionLabel: 'Retry',
            onAction: _loadLocal,
          ),
        ),
      ];
    }
    final tracks = _localTracks ?? const <Track>[];
    if (tracks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No music found on this device',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < tracks.length; i++)
        TrackTile(
          track: tracks[i],
          showDuration: true,
          onTap: () => _playLocalAt(i),
          onDeleteLocal: () => _deleteLocal(tracks[i]),
        ),
    ];
  }

  Widget _permissionMessage() {
    return _emptyMessage(
      icon: Icons.folder_off,
      title:
          'Allow Musicap to access your music to list songs stored on this device.',
      actionLabel: 'Grant access',
      onAction: _loadLocal,
      secondaryLabel:
          _permissionPermanentlyDenied ? 'Open settings' : null,
      onSecondary: _permissionPermanentlyDenied ? openAppSettings : null,
    );
  }

  Widget _emptyMessage({
    required IconData icon,
    required String title,
    String subtitle = '',
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(onPressed: onAction, child: Text(actionLabel)),
                  if (secondaryLabel != null && onSecondary != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                        onPressed: onSecondary, child: Text(secondaryLabel)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
