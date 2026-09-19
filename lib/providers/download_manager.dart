import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:music_player/models/track.dart';

/// Tracks the download status of individual tracks.
enum DownloadStatus { notDownloaded, downloading, downloaded }

/// Holds the download state for a single track.
class DownloadState {
  final DownloadStatus status;
  final double progress; // 0.0 to 1.0
  final String title;
  final String artist;

  const DownloadState({
    this.status = DownloadStatus.notDownloaded,
    this.progress = 0.0,
    this.title = '',
    this.artist = '',
  });

  DownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    String? title,
    String? artist,
  }) {
    return DownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      title: title ?? this.title,
      artist: artist ?? this.artist,
    );
  }
}

/// Manages downloading audio files to local storage and tracking their status.
class DownloadManager extends StateNotifier<Map<String, DownloadState>> {
  final Dio _dio = Dio();
  DownloadManager() : super({});

  /// Returns the app's local music directory for storing downloaded files.
  Future<Directory> get _musicDir async {
    final dir = await getApplicationDocumentsDirectory();
    final musicDir = Directory(p.join(dir.path, 'music_downloads'));
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  /// Returns the local file path for a given track.
  Future<String> _getTrackPath(Track track) async {
    final dir = await _musicDir;
    // Sanitize filename
    final safeName = '${track.id}_${track.title.replaceAll(RegExp(r'[^\w\s-]'), '')}.mp3';
    return p.join(dir.path, safeName);
  }

  /// Checks if a track has already been downloaded.
  Future<bool> isDownloaded(Track track) async {
    final path = await _getTrackPath(track);
    return File(path).existsSync();
  }

  /// Returns the local file for a downloaded track, or null.
  Future<File?> getDownloadedFile(Track track) async {
    final path = await _getTrackPath(track);
    final file = File(path);
    if (await file.exists()) return file;
    return null;
  }

  /// Downloads a track to local storage with progress tracking.
  Future<void> downloadTrack(Track track) async {
    // Skip if already downloaded or currently downloading.
    if (state[track.id]?.status == DownloadStatus.downloaded) return;
    if (state[track.id]?.status == DownloadStatus.downloading) return;

    state = {
      ...state,
      track.id: DownloadState(
        status: DownloadStatus.downloading,
        progress: 0.0,
        title: track.title,
        artist: track.artist,
      ),
    };

    try {
      final path = await _getTrackPath(track);
      await _dio.download(
        track.audioUrl,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            state = {
              ...state,
              track.id: DownloadState(
                status: DownloadStatus.downloading,
                progress: received / total,
                title: track.title,
                artist: track.artist,
              ),
            };
          }
        },
      );
      state = {
        ...state,
        track.id: DownloadState(
          status: DownloadStatus.downloaded,
          progress: 1.0,
          title: track.title,
          artist: track.artist,
        ),
      };
    } catch (e) {
      // On error, reset to not downloaded.
      state = {
        ...state,
        track.id: DownloadState(
          status: DownloadStatus.notDownloaded,
          progress: 0.0,
          title: track.title,
          artist: track.artist,
        ),
      };
    }
  }

  /// Deletes a downloaded track from local storage.
  Future<void> deleteDownload(Track track) async {
    final path = await _getTrackPath(track);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    state = {
      ...state,
      track.id: const DownloadState(status: DownloadStatus.notDownloaded, progress: 0.0),
    };
  }

  /// Returns the download state for a specific track.
  DownloadState getState(String trackId) {
    return state[trackId] ?? const DownloadState();
  }
}

/// Provider for the download manager.
final downloadManagerProvider =
    StateNotifierProvider<DownloadManager, Map<String, DownloadState>>((ref) {
  return DownloadManager();
});
