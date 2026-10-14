import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/features/player/player_controller.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/music_provider.dart';
import 'package:music_player/widgets/track_menu.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android-only tab listing music stored on the device (MediaStore scan).
/// Tracks play through the normal queue/mini-player like any other song.
class LocalMusicPage extends ConsumerStatefulWidget {
  const LocalMusicPage({super.key});

  @override
  ConsumerState<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends ConsumerState<LocalMusicPage> {
  static const _channel = MethodChannel('music_player/local_audio');

  List<Track>? _tracks;
  bool _scanning = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      final tracks = <Track>[];
      for (final entry in raw ?? const <dynamic>[]) {
        if (entry is! Map) continue;
        final item = Map<String, dynamic>.from(entry);
        final id = item['id']?.toString() ?? '';
        final path = item['path']?.toString() ?? '';
        if (id.isEmpty && path.isEmpty) continue;
        final title = item['title']?.toString() ?? '';
        final artist = item['artist']?.toString() ?? '';
        final durationMs = (item['durationMs'] as num?)?.toInt() ?? 0;
        tracks.add(Track(
          id: 'local:$id',
          title: title.isNotEmpty ? title : path.split('/').last,
          artist: artist.isNotEmpty ? artist : 'Unknown artist',
          audioUrl: item['uri']?.toString() ?? 'file://$path',
          duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
        ));
      }
      if (mounted) setState(() => _tracks = tracks);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Scan failed');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _playAt(int index) {
    final tracks = _tracks;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('On This Device'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan',
            onPressed: _scanning ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_scanning && _tracks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permissionDenied) {
      return _message(
        icon: Icons.folder_off,
        text:
            'Allow DaviCap to access your music to list songs stored on this device.',
        actionLabel: 'Grant access',
        onAction: _load,
        secondaryLabel: _permissionPermanentlyDenied ? 'Open settings' : null,
        onSecondary: _permissionPermanentlyDenied ? openAppSettings : null,
      );
    }
    if (_error != null) {
      return _message(
        icon: Icons.error_outline,
        text: 'Could not read local music: $_error',
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    final tracks = _tracks ?? const <Track>[];
    if (tracks.isEmpty) {
      return _message(
        icon: Icons.music_off,
        text: 'No music found on this device.',
        actionLabel: 'Rescan',
        onAction: _load,
      );
    }
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) => TrackTile(
        track: tracks[index],
        showDuration: true,
        onTap: () => _playAt(index),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String text,
    required String actionLabel,
    required VoidCallback onAction,
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
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
                if (secondaryLabel != null && onSecondary != null) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
