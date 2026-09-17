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
    // Configure player - sequential loop mode
    // just_audio 0.9.x uses setLoopMode for repeat
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

  // Seek to position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
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
  setLoop(bool loop) {
    if (loop) {
      _player.setLoopMode(LoopMode.one);
    } else {
      _player.setLoopMode(LoopMode.off);
    }
    _updateState();
  }

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

  AudioPlayerState({
    this.isPlaying = false,
    this.processing = false,
    this.currentPosition,
    this.totalDuration,
  });

  AudioPlayerState copyWith({
    bool? isPlaying,
    bool? processing,
    Duration? currentPosition,
    Duration? totalDuration,
  }) {
    return AudioPlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      processing: processing ?? this.processing,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
    );
  }
}