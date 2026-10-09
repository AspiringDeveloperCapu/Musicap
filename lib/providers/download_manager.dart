import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tracks the download status of individual tracks.
enum DownloadStatus { notDownloaded, downloading, downloaded, canceled }

/// Holds the download state for a single track.
class DownloadState {
  final DownloadStatus status;
  final double progress;
  final String title;
  final String artist;
  final String audioUrl;
  final DateTime? downloadedAt;

  const DownloadState({
    this.status = DownloadStatus.notDownloaded,
    this.progress = 0.0,
    this.title = '',
    this.artist = '',
    this.audioUrl = '',
    this.downloadedAt,
  });

  DownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    String? title,
    String? artist,
    String? audioUrl,
    DateTime? downloadedAt,
  }) {
    return DownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      audioUrl: audioUrl ?? this.audioUrl,
      downloadedAt: downloadedAt ?? this.downloadedAt,
    );
  }
}

/// Manages downloading audio files.
class DownloadManager extends StateNotifier<Map<String, DownloadState>> {
  final Dio _dio = Dio();
  DownloadManager() : super({});

  /// Simulates a download with progress updates for testing.
  Future<void> simulateDownload(Track track) async {
    if (state[track.id]?.status == DownloadStatus.downloaded) return;
    if (state[track.id]?.status == DownloadStatus.downloading) return;

    state = {
      ...state,
      track.id: DownloadState(
        status: DownloadStatus.downloading,
        progress: 0.0,
        title: track.title,
        artist: track.artist,
        audioUrl: track.audioUrl,
      ),
    };

    for (double p = 0.0; p <= 1.0; p += 0.05) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (state[track.id]?.status == DownloadStatus.canceled) return;
      state = {
        ...state,
        track.id: DownloadState(
          status: DownloadStatus.downloading,
          progress: p.clamp(0.0, 1.0),
          title: track.title,
          artist: track.artist,
          audioUrl: track.audioUrl,
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
        audioUrl: track.audioUrl,
        downloadedAt: DateTime.now(),
      ),
    };
  }

  /// Simulates downloading multiple tracks (for "Download All").
  Future<void> simulateDownloadAll(List<Track> tracks) async {
    for (final track in tracks) {
      if (state[track.id]?.status != DownloadStatus.downloaded &&
          state[track.id]?.status != DownloadStatus.downloading) {
        // Stagger downloads slightly so they don't all start at once.
        simulateDownload(track);
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  /// Removes a track from the download list (does not delete the file).
  void removeFromList(String trackId) {
    final updated = Map<String, DownloadState>.from(state);
    updated.remove(trackId);
    state = updated;
  }

  /// Deletes the downloaded file and removes from list.
  Future<void> deleteDownload(Track track) async {
    // In a real app, delete the file from disk here.
    removeFromList(track.id);
  }

  /// Cancels an in-progress download.
  void cancelDownload(String trackId) {
    final current = state[trackId];
    if (current != null && current.status == DownloadStatus.downloading) {
      state = {
        ...state,
        trackId: DownloadState(
          status: DownloadStatus.canceled,
          progress: current.progress,
          title: current.title,
          artist: current.artist,
          audioUrl: current.audioUrl,
        ),
      };
    }
  }

  /// Returns only downloaded tracks as a list, optionally sorted.
  List<MapEntry<String, DownloadState>> getDownloaded({String sortBy = 'date'}) {
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
        downloaded.sort((a, b) =>
            (b.value.downloadedAt ?? DateTime(0))
                .compareTo(a.value.downloadedAt ?? DateTime(0)));
        break;
    }

    return downloaded;
  }

  /// Returns the total number of downloaded tracks.
  int get downloadedCount =>
      state.values.where((d) => d.status == DownloadStatus.downloaded).length;

  DownloadState getState(String trackId) {
    return state[trackId] ?? const DownloadState();
  }
}

final downloadManagerProvider =
    StateNotifierProvider<DownloadManager, Map<String, DownloadState>>((ref) {
  return DownloadManager();
});
