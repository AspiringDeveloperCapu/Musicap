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
      final processingDone = playerState.processingState == ProcessingState.completed;
      state = state.copyWith(
        isPlaying: playerState.playing,
        processing: playerState.processingState == ProcessingState.loading ||
            playerState.processingState == ProcessingState.buffering,
      );
      if (processingDone) {
        state = state.copyWith(isPlaying: false);
      }
    });
  }

  Future<void> setUrl(String url, {String? title, String? artist}) async {
    await _player.setUrl(url);
    state = state.copyWith(
      currentTitle: title ?? 'Unknown',
      currentArtist: artist ?? 'Unknown',
      currentUrl: url,
    );
    _updateState();
  }

  Future<void> setAsset(String assetPath, {String? title, String? artist}) async {
    await _player.setAsset(assetPath);
    state = state.copyWith(
      currentTitle: title ?? 'Unknown',
      currentArtist: artist ?? 'Unknown',
    );
    _updateState();
  }

  Future<void> setPlaylist(List<String> urls, {int startIndex = 0, List<Map<String, String>>? tracks}) async {
    final sources = urls.map((url) => AudioSource.uri(Uri.parse(url))).toList();
    final playlist = ConcatenatingAudioSource(children: sources);
    await _player.setAudioSource(playlist, initialIndex: startIndex);
    if (tracks != null && startIndex < tracks.length) {
      state = state.copyWith(
        currentTitle: tracks[startIndex]['title'] ?? 'Unknown',
        currentArtist: tracks[startIndex]['artist'] ?? 'Unknown',
        currentUrl: urls[startIndex],
      );
    }
    _updateState();
  }

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

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _updateState();
  }

  Future<void> seekToNext() async {
    await _player.seekToNext();
    _updateState();
  }

  Future<void> seekToPrevious() async {
    await _player.seekToPrevious();
    _updateState();
  }

  setVolume(double volume) {
    _player.setVolume(volume);
    _updateState();
  }

  setSpeed(double speed) {
    _player.setSpeed(speed);
    _updateState();
  }

  setLoopMode(LoopMode mode) {
    _player.setLoopMode(mode);
    state = state.copyWith(loopMode: mode);
    _updateState();
  }

  setShuffleMode(bool enabled) {
    _player.setShuffleModeEnabled(enabled);
    state = state.copyWith(isShuffleEnabled: enabled);
    _updateState();
  }

  AudioPlayer get player => _player;

  void _updateState() {
    state = state.copyWith(
      isPlaying: _player.playing,
      processing: _player.processingState == ProcessingState.loading ||
          _player.processingState == ProcessingState.buffering,
      currentPosition: _player.position,
      totalDuration: _player.duration,
      hasNext: _player.hasNext,
      hasPrevious: _player.hasPrevious,
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
  final String currentTitle;
  final String currentArtist;
  final String? currentUrl;

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
    this.currentTitle = '',
    this.currentArtist = '',
    this.currentUrl,
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
    String? currentTitle,
    String? currentArtist,
    String? currentUrl,
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
      currentTitle: currentTitle ?? this.currentTitle,
      currentArtist: currentArtist ?? this.currentArtist,
      currentUrl: currentUrl ?? this.currentUrl,
    );
  }
}
