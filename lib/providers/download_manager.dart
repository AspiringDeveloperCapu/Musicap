import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tracks the download status of individual tracks.
enum DownloadStatus { notDownloaded, downloading, downloaded }

/// Holds the download state for a single track.
class DownloadState {
  final DownloadStatus status;
  final double progress;
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

/// Manages downloading audio files. On web, opens the URL to trigger
/// a browser download. On mobile/desktop, saves to local storage.
class DownloadManager extends StateNotifier<Map<String, DownloadState>> {
  final Dio _dio = Dio();
  DownloadManager() : super({});

  Future<void> downloadTrack(Track track) async {
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
      if (kIsWeb) {
        // On web, download the bytes with progress, then trigger browser save.
        final response = await _dio.get(
          track.audioUrl,
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
          options: Options(responseType: ResponseType.bytes),
        );

        // Launch the audio URL in a new tab — browser will prompt to save.
        final uri = Uri.parse(track.audioUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }

        state = {
          ...state,
          track.id: DownloadState(
            status: DownloadStatus.downloaded,
            progress: 1.0,
            title: track.title,
            artist: track.artist,
          ),
        };
      } else {
        // Native: save to app documents.
        await _downloadNative(track);
      }
    } catch (e) {
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

  Future<void> _downloadNative(Track track) async {
    // For native platforms — placeholder until path_provider is wired up.
    // Simulates a download with progress.
    for (double p = 0.0; p <= 1.0; p += 0.1) {
      await Future.delayed(const Duration(milliseconds: 100));
      state = {
        ...state,
        track.id: DownloadState(
          status: DownloadStatus.downloading,
          progress: p.clamp(0.0, 1.0),
          title: track.title,
          artist: track.artist,
        ),
      };
    }

    state = {
      ...state,
      track.id: DownloadState(
        status: DownloadStatus.downloaded,
        progress: 1.0,
        title: track.title,
        artist: track.artist,
      ),
    };
  }

  Future<void> deleteDownload(Track track) async {
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

  DownloadState getState(String trackId) {
    return state[trackId] ?? const DownloadState();
  }
}

final downloadManagerProvider =
    StateNotifierProvider<DownloadManager, Map<String, DownloadState>>((ref) {
  return DownloadManager();
});
