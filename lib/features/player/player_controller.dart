import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';

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

    _player.currentIndexStream.listen((index) {
      if (index != null && index < state.queue.length) {
        final track = state.queue[index];
        state = state.copyWith(
          currentIndex: index,
          currentTitle: track.title,
          currentArtist: track.artist,
          currentUrl: track.audioUrl,
          hasNext: _player.hasNext,
          hasPrevious: _player.hasPrevious,
        );
      }
    });

    _player.playerStateStream.listen((playerState) {
      final processingDone = playerState.processingState == ProcessingState.completed;
      state = state.copyWith(
        isPlaying: playerState.playing,
        processing: playerState.processingState == ProcessingState.loading ||
            playerState.processingState == ProcessingState.buffering,
        hasNext: _player.hasNext,
        hasPrevious: _player.hasPrevious,
      );
      if (processingDone) {
        state = state.copyWith(isPlaying: false);
      }
    });

    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        state = state.copyWith(error: 'Playback error: $e');
      },
    );
  }

  Future<void> playTrack(Track track, {List<Track>? fromQueue, int? startIndex}) async {
    final queue = fromQueue ?? [track];
    final index = startIndex ?? queue.indexOf(track);

    try {
      final sources = queue.map((t) => AudioSource.uri(
        Uri.parse(t.audioUrl),
        tag: t.id,
      )).toList();
      final concatenating = ConcatenatingAudioSource(children: sources);

      await _player.setAudioSource(
        concatenating,
        initialIndex: index.clamp(0, queue.length - 1),
      );

      final current = queue[index.clamp(0, queue.length - 1)];
      state = state.copyWith(
        queue: queue,
        currentIndex: index.clamp(0, queue.length - 1),
        currentTitle: current.title,
        currentArtist: current.artist,
        currentUrl: current.audioUrl,
        hasNext: _player.hasNext,
        hasPrevious: _player.hasPrevious,
        error: null,
      );

      await _player.play();
    } catch (e) {
      state = state.copyWith(error: 'Failed to play: $e');
    }
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
    if (_player.hasNext) {
      await _player.seekToNext();
      _updateState();
    }
  }

  Future<void> seekToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
    _updateState();
  }

  setLoopMode(LoopMode mode) {
    _player.setLoopMode(mode);
    state = state.copyWith(loopMode: mode);
  }

  setShuffleMode(bool enabled) {
    _player.setShuffleModeEnabled(enabled);
    state = state.copyWith(isShuffleEnabled: enabled);
  }

  clearError() {
    state = state.copyWith(error: null);
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
  final List<Track> queue;
  final String? error;

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
    this.queue = const [],
    this.error,
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
    List<Track>? queue,
    String? error,
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
      queue: queue ?? this.queue,
      error: error,
    );
  }
}
