import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioPlayerProvider = StateNotifierProvider<AudioPlayerController, AudioPlayerState>((ref) {
  return AudioPlayerController();
});

class AudioPlayerController extends StateNotifier<AudioPlayerState> {
  final AudioPlayer _player = AudioPlayer();

  AudioPlayerController() : super(AudioPlayerState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    _player.positionStream.listen((position) {
      state = state.copyWith(currentPosition: position);
    });

    _player.durationStream.listen((duration) {
      state = state.copyWith(totalDuration: duration);
    });

    _player.playerStateStream.listen((playerState) {
      state = state.copyWith(
        isPlaying: playerState.playing,
        processing: playerState.processingState == ProcessingState.loading ||
            playerState.processingState == ProcessingState.buffering,
      );
    });
  }

  // Set audio source from URL
  Future<void> setUrl(String url) async {
    try {
      await _player.setUrl(url);
      _updateState();
    } catch (e) {
      rethrow;
    }
  }

  // Set audio source from asset
  Future<void> setAsset(String assetPath) async {
    try {
      await _player.setAsset(assetPath);
      _updateState();
    } catch (e) {
      rethrow;
    }
  }

  // Play playlist
  Future<void> setPlaylist(List<String> urls, {int startIndex = 0}) async {
    try {
      final sources = urls.map((url) => AudioSource.uri(Uri.parse(url))).toList();
      final playlist = ConcatenatingAudioSource(children: sources);
      await _player.setAudioSource(playlist, initialIndex: startIndex);
      _updateState();
    } catch (e) {
      rethrow;
    }
  }

  // Playback controls
  Future<void> play() async {
    await _player.play();
    _updateState();
  }

  Future<void> pause() async {
    await _player.pause();
    _updateState();
  }

  Future<void> stop() async {
    await _player.stop();
    _updateState();
  }

  Future<void> playOrPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _updateState();
  }

  // Seek to position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _updateState();
  }

  // Next/Previous (for playlist)
  Future<void> seekToNext() async {
    await _player.seekToNext();
    _updateState();
  }

  Future<void> seekToPrevious() async {
    await _player.seekToPrevious();
    _updateState();
  }

  // Volume & speed
  setVolume(double volume) {
    _player.setVolume(volume);
    _updateState();
  }

  setSpeed(double speed) {
    _player.setSpeed(speed);
    _updateState();
  }

  // Loop/Repeat
  setLoopMode(LoopMode mode) {
    _player.setLoopMode(mode);
    _updateState();
  }

  // Shuffle
  setShuffleMode(bool enabled) {
    _player.setShuffleModeEnabled(enabled);
    _updateState();
  }

  // Get current player
  AudioPlayer get player => _player;

  // State updates from player streams
  void _updateState() {
    state = state.copyWith(
      isPlaying: _player.playing,
      processing: _player.processingState == ProcessingState.loading ||
          _player.processingState == ProcessingState.buffering,
      currentPosition: _player.position,
      totalDuration: _player.duration,
    );
  }
}

class AudioPlayerState {
  final bool isPlaying;
  final bool processing;
  final Duration? currentPosition;
  final Duration? totalDuration;
  final int currentIndex;
  final bool hasNext;
  final bool hasPrevious;
  final bool isShuffleEnabled;
  final LoopMode loopMode;

  AudioPlayerState({
    this.isPlaying = false,
    this.processing = false,
    this.currentPosition,
    this.totalDuration,
    this.currentIndex = 0,
    this.hasNext = false,
    this.hasPrevious = false,
    this.isShuffleEnabled = false,
    this.loopMode = LoopMode.off,
  });

  AudioPlayerState copyWith({
    bool? isPlaying,
    bool? processing,
    Duration? currentPosition,
    Duration? totalDuration,
    int? currentIndex,
    bool? hasNext,
    bool? hasPrevious,
    bool? isShuffleEnabled,
    LoopMode? loopMode,
  }) {
    return AudioPlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      processing: processing ?? this.processing,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
      currentIndex: currentIndex ?? this.currentIndex,
      hasNext: hasNext ?? this.hasNext,
      hasPrevious: hasPrevious ?? this.hasPrevious,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      loopMode: loopMode ?? this.loopMode,
    );
  }
}