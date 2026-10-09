import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Audio handler for background/media session integration via audio_service.
/// Bridges just_audio's AudioPlayer with the system's media notification controls
/// (lock screen, notification bar, Bluetooth, etc.).
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  MusicAudioHandler() {
    _init();
  }

  /// Sets up stream listeners to pipe playback events to the system
  /// and track current media item changes.
  Future<void> _init() async {
    // Transform just_audio playback events into audio_service PlaybackState
    // and pipe them to the system media session.
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Update the current media item (shown in notification) when the
    // track index changes in the playlist.
    _player.currentIndexStream.listen((index) {
      if (index != null && _player.sequence != null) {
        final sequence = _player.sequence!;
        if (index < sequence.length) {
          mediaItem.add(sequence[index].tag as MediaItem?);
        }
      }
    });
  }

  /// Loads and plays a single audio URL with optional metadata.
  Future<void> loadUrl(String url, {String? title, String? artist}) async {
    await _player.setUrl(url);
    mediaItem.add(MediaItem(
      id: url,
      title: title ?? 'Unknown Title',
      artist: artist ?? 'Unknown Artist',
      duration: _player.duration,
    ));
  }

  /// Loads a list of audio URLs as a playlist and starts from [startIndex].
  Future<void> loadPlaylist(List<String> urls, {int startIndex = 0}) async {
    final sources = urls.map((url) => AudioSource.uri(
      Uri.parse(url),
      tag: MediaItem(id: url, title: 'Track ${urls.indexOf(url) + 1}'),
    )).toList();
    final playlist = ConcatenatingAudioSource(children: sources);
    await _player.setAudioSource(playlist, initialIndex: startIndex);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  /// Maps audio_service repeat modes to just_audio loop modes.
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode mode) async {
    switch (mode) {
      case AudioServiceRepeatMode.none:
        _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
        _player.setLoopMode(LoopMode.all);
        break;
      case AudioServiceRepeatMode.group:
        break;
    }
  }

  /// Enables or disables shuffle based on the audio_service shuffle mode.
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    _player.setShuffleModeEnabled(mode == AudioServiceShuffleMode.all);
  }

  /// Converts a just_audio PlaybackEvent into an audio_service PlaybackState
  /// that the system media session can understand and display.
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  /// Called when the app is removed from recent tasks — stops playback cleanly.
  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await super.onTaskRemoved();
  }

  /// Exposes the underlying AudioPlayer for direct access if needed.
  AudioPlayer get player => _player;
}
