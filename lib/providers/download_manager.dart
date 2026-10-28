import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/services/download_save_stub.dart'
    if (dart.library.js_interop) 'package:music_player/services/download_save_web.dart'
    if (dart.library.io) 'package:music_player/services/download_save_io.dart';
import 'package:music_player/services/stream_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDownloadsKey = 'downloads.v1';

/// Transient download failure surfaced to the UI. Carries the track so
/// the retry dialog can re-run the download.
final downloadErrorProvider = StateProvider<(String message, Track track)?>(
  (ref) => null,
);

/// Tracks the download status of individual tracks.
enum DownloadStatus { notDownloaded, downloading, downloaded, canceled }

/// Holds the download state for a single track.
class DownloadState {
  final DownloadStatus status;
  final double progress;
  final String title;
  final String artist;
  final String audioUrl;
  final String? imageUrl;
  final String? videoId;
  final DateTime? downloadedAt;
  final int? sizeBytes;
  final String? filePath;
  final String? artPath;

  const DownloadState({
    this.status = DownloadStatus.notDownloaded,
    this.progress = 0.0,
    this.title = '',
    this.artist = '',
    this.audioUrl = '',
    this.imageUrl,
    this.videoId,
    this.downloadedAt,
    this.sizeBytes,
    this.filePath,
    this.artPath,
  });

  DownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    String? title,
    String? artist,
    String? audioUrl,
    String? imageUrl,
    String? videoId,
    DateTime? downloadedAt,
    int? sizeBytes,
    String? filePath,
    String? artPath,
  }) {
    return DownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      audioUrl: audioUrl ?? this.audioUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      videoId: videoId ?? this.videoId,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      filePath: filePath ?? this.filePath,
      artPath: artPath ?? this.artPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'progress': progress,
      'title': title,
      'artist': artist,
      'audioUrl': audioUrl,
      'imageUrl': imageUrl,
      'videoId': videoId,
      'downloadedAt': downloadedAt?.millisecondsSinceEpoch,
      'sizeBytes': sizeBytes,
      'filePath': filePath,
      'artPath': artPath,
    };
  }

  factory DownloadState.fromJson(Map<String, dynamic> json) {
    return DownloadState(
      status: DownloadStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => DownloadStatus.downloaded,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 1.0,
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      audioUrl: json['audioUrl'] ?? '',
      imageUrl: json['imageUrl'],
      videoId: json['videoId'],
      downloadedAt: json['downloadedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['downloadedAt'])
          : null,
      sizeBytes: json['sizeBytes'],
      filePath: json['filePath'],
      artPath: json['artPath'],
    );
  }
}

/// Manages downloading audio files: real bytes are fetched with progress,
/// saved to disk (desktop/mobile) or handed to the browser (web), and the
/// download history is persisted across restarts.
class DownloadManager extends StateNotifier<Map<String, DownloadState>> {
  final Ref _ref;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );
  bool _hydrated = false;

  DownloadManager(this._ref) : super({}) {
    _load();
  }

  /// Restores persisted download history. Files that disappeared from disk
  /// are dropped from the list.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDownloadsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List;
        final restored = <String, DownloadState>{};
        for (final item in decoded) {
          final dl = DownloadState.fromJson(Map<String, dynamic>.from(item));
          if (dl.status != DownloadStatus.downloaded) continue;
          final path = dl.filePath;
          if (path != null && !fileExists(path)) continue;
          restored[dl.videoId ?? dl.title] = dl;
          final vid = dl.videoId;
          if (vid != null && vid.isNotEmpty && path != null && path.isNotEmpty) {
            // Local-first playback: register the saved file so resolve()
            // plays it instead of streaming.
            StreamResolver.localFiles[vid] = path;
          }
        }
        state = {...restored, ...state};
      } catch (_) {
        // Corrupt history — start fresh.
      }
    }
    _hydrated = true;
    _save();
  }

  Future<void> _save() async {
    if (!_hydrated) return;
    final prefs = await SharedPreferences.getInstance();
    final entries = state.entries
        .where((e) => e.value.status == DownloadStatus.downloaded)
        .map((e) => e.value.toJson())
        .toList();
    await prefs.setString(_kDownloadsKey, jsonEncode(entries));
  }

  /// Builds a filesystem-safe filename from track metadata.
  String _filenameFor(Track track) {
    final raw = '${track.artist} - ${track.title}.mp3';
    final cleaned = raw.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return cleaned.isEmpty ? '${track.id}.mp3' : cleaned;
  }

  /// Cover art filename derived from the audio filename.
  String _artFilenameFor(Track track) =>
      _filenameFor(track).replaceFirst(RegExp(r'\.mp3$'), '.jpg');

  /// Fetches the cover image bytes and saves them next to the audio file.
  /// Returns null when there is no image or the save fails (art is optional).
  Future<String?> _saveArt(Track track) async {
    final url = track.imageUrl;
    if (url == null || url.isEmpty) return null;
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return await saveArtFile(bytes, _artFilenameFor(track));
    } catch (_) {
      return null;
    }
  }

  /// Downloads a track with real progress reporting.
  Future<void> startDownload(Track track) async {
    if (state[track.id]?.status == DownloadStatus.downloaded) return;
    if (state[track.id]?.status == DownloadStatus.downloading) return;

    // First download of the session may prompt for a save folder (web).
    await ensureDirectoryForDownload();

    state = {
      ...state,
      track.id: DownloadState(
        status: DownloadStatus.downloading,
        progress: 0.0,
        title: track.title,
        artist: track.artist,
        audioUrl: track.audioUrl,
        imageUrl: track.imageUrl,
        videoId: track.videoId ?? track.id,
      ),
    };

    try {
      // Resolve the audio URL device-first (backend fallback built in) so
      // downloads don't proxy through the backend's bandwidth quota.
      final streamUrl = await StreamResolver.instance.resolve(track);
      final response = await _dio.get<List<int>>(
        streamUrl,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (state[track.id]?.status == DownloadStatus.canceled) {
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: streamUrl),
              reason: 'Download canceled by user',
            );
          }
          if (total > 0) {
            _updateProgress(track.id, received / total);
          }
        },
      );

      if (state[track.id]?.status == DownloadStatus.canceled) return;

      // Save cover art alongside the audio (runs while the file writes).
      final artFuture = _saveArt(track);

      final bytes = response.data ?? <int>[];
      final path = await saveFile(bytes, _filenameFor(track));
      final artPath = await artFuture;

      state = {
        ...state,
        track.id: DownloadState(
          status: DownloadStatus.downloaded,
          progress: 1.0,
          title: track.title,
          artist: track.artist,
          audioUrl: track.audioUrl,
          imageUrl: track.imageUrl,
          videoId: track.videoId ?? track.id,
          downloadedAt: DateTime.now(),
          sizeBytes: bytes.length,
          filePath: path,
          artPath: artPath,
        ),
      };
      _save();
      // Local-first playback from here on.
      final vid = track.videoId ?? track.id;
      if (path != null && path.isNotEmpty) {
        StreamResolver.localFiles[vid] = path;
      }
    } on DioException catch (e) {
      // Canceled or network failure — keep canceled state if set,
      // otherwise reset so the user can retry.
      final current = state[track.id];
      if (current != null && current.status != DownloadStatus.canceled) {
        state = {
          ...state,
          track.id: current.copyWith(
            status: DownloadStatus.notDownloaded,
            progress: 0.0,
          ),
        };
        _ref.read(downloadErrorProvider.notifier).state = (
          _friendlyDioError(e, track),
          track,
        );
      }
    } catch (_) {
      // Reset to retryable state unless the user canceled it.
      final current = state[track.id];
      if (current != null && current.status != DownloadStatus.canceled) {
        state = {
          ...state,
          track.id: current.copyWith(
            status: DownloadStatus.notDownloaded,
            progress: 0.0,
          ),
        };
        _ref.read(downloadErrorProvider.notifier).state = (
          'Download failed for "${track.title}" — check your connection and retry',
          track,
        );
      }
    }
  }

  String _friendlyDioError(DioException e, Track track) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Download timed out for "${track.title}" — check your connection and retry';
      case DioExceptionType.connectionError:
        return 'No connection — couldn\'t download "${track.title}"';
      default:
        return 'Download failed for "${track.title}" — check your connection and retry';
    }
  }

  void _updateProgress(String trackId, double progress) {
    final current = state[trackId];
    if (current == null || current.status != DownloadStatus.downloading) return;
    state = {
      ...state,
      trackId: current.copyWith(progress: progress.clamp(0.0, 1.0)),
    };
  }

  /// Downloads multiple tracks sequentially (for "Download All").
  ///
  /// Each track awaits the previous one's full download (manifest resolve
  /// included), so at most one YouTube resolve is in flight and one file
  /// is being written at a time — the same safe shape as the automatic
  /// queue fills. Concurrency here would risk the rate limit for a
  /// little speed the user doesn't need.
  Future<void> startDownloadAll(List<Track> tracks) async {
    for (final track in tracks) {
      if (state[track.id]?.status != DownloadStatus.downloaded &&
          state[track.id]?.status != DownloadStatus.downloading) {
        await startDownload(track);
      }
    }
  }

  /// Removes a track from the download list (keeps any saved file).
  void removeFromList(String trackId) {
    final updated = Map<String, DownloadState>.from(state);
    final removed = updated.remove(trackId);
    // Drop the local-first registration — the track is no longer treated
    // as a downloaded one even when the file itself is kept.
    final vid = removed?.videoId;
    if (vid != null && vid.isNotEmpty) {
      StreamResolver.localFiles.remove(vid);
    }
    state = updated;
    _save();
  }

  /// Deletes the downloaded file (and its saved cover art) and removes it
  /// from the list.
  Future<void> deleteDownload(Track track) async {
    final entry = state[track.id];
    final path = entry?.filePath;
    if (path != null) {
      await deleteFile(path);
    }
    final artPath = entry?.artPath;
    if (artPath != null) {
      await deleteFile(artPath);
    }
    removeFromList(track.id);
  }

  /// Cancels an in-progress download.
  void cancelDownload(String trackId) {
    final current = state[trackId];
    if (current != null && current.status == DownloadStatus.downloading) {
      state = {
        ...state,
        trackId: current.copyWith(status: DownloadStatus.canceled),
      };
    }
  }

  /// Returns only downloaded tracks as a list, optionally sorted.
  List<MapEntry<String, DownloadState>> getDownloaded({
    String sortBy = 'date',
  }) {
    final downloaded = state.entries
        .where((e) => e.value.status == DownloadStatus.downloaded)
        .toList();

    switch (sortBy) {
      case 'name':
        downloaded.sort((a, b) => a.value.title.compareTo(b.value.title));
        break;
      case 'artist':
        downloaded.sort((a, b) => a.value.artist.compareTo(b.value.artist));
        break;
      case 'date':
      default:
        downloaded.sort(
          (a, b) => (b.value.downloadedAt ?? DateTime(0)).compareTo(
            a.value.downloadedAt ?? DateTime(0),
          ),
        );
        break;
    }

    return downloaded;
  }

  /// Number of completed downloads.
  int get downloadedCount =>
      state.values.where((d) => d.status == DownloadStatus.downloaded).length;

  /// Total bytes of all downloaded files.
  int get totalBytes => state.values
      .where((d) => d.status == DownloadStatus.downloaded)
      .fold(0, (sum, d) => sum + (d.sizeBytes ?? 0));

  DownloadState getState(String trackId) {
    return state[trackId] ?? const DownloadState();
  }
}

final downloadManagerProvider =
    StateNotifierProvider<DownloadManager, Map<String, DownloadState>>((ref) {
      return DownloadManager(ref);
    });
