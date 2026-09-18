import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/models/track.dart';

/// Riverpod provider that exposes the audio player controller and its state
/// to the entire widget tree.
final audioPlayerProvider = StateNotifierProvider<AudioPlayerController, AudioPlayerState>((ref) {
  return AudioPlayerController();
});

/// Central audio player controller that manages playback, queue, shuffle,
/// loop, and all player state. Uses just_audio's AudioPlayer under the hood
/// and wraps it with a Riverpod StateNotifier for reactive UI updates.
class AudioPlayerController extends StateNotifier<AudioPlayerState> {
  final AudioPlayer _player = AudioPlayer();

  /// Reference to the current ConcatenatingAudioSource, used for queue
  /// operations like add, remove, and reorder.
  ConcatenatingAudioSource? _audioSource;

  AudioPlayerController() : super(AudioPlayerState()) {
    _initialize();
  }

  /// Sets up stream listeners on the AudioPlayer to keep AudioPlayerState
  /// in sync with the underlying player's position, duration, current index,
  /// and playback state.
  Future<void> _initialize() async {
    // Update current position as the track plays.
    _player.positionStream.listen((position) {
      state = state.copyWith(currentPosition: position);
    });

    // Update total duration when a new track loads.
    _player.durationStream.listen((duration) {
      state = state.copyWith(totalDuration: duration);
    });

    // When the player moves to a different track in the playlist, update
    // the current track info (title, artist, url) and navigation flags.
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

    // Sync isPlaying and processing (loading/buffering) flags.
    // Also detect when playback completes.
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

    // Catch playback errors from the event stream.
    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        state = state.copyWith(error: 'Playback error: $e');
      },
    );
  }

  /// Loads and plays a track. If [fromQueue] is provided, the entire list
  /// becomes the playback queue (using ConcatenatingAudioSource). [startIndex]
  /// determines which track in the queue to begin playing from.
  Future<void> playTrack(Track track, {List<Track>? fromQueue, int? startIndex}) async {
    final queue = fromQueue ?? [track];
    final index = startIndex ?? queue.indexOf(track);

    try {
      // Convert each Track into an AudioSource URI with the track ID as a tag.
      final sources = queue.map((t) => AudioSource.uri(
        Uri.parse(t.audioUrl),
        tag: t.id,
      )).toList();
      final concatenating = ConcatenatingAudioSource(children: sources);
      _audioSource = concatenating;

      // Set the audio source and start from the specified index.
      await _player.setAudioSource(
        concatenating,
        initialIndex: index.clamp(0, queue.length - 1),
      );

      // Update state with the new queue and current track info.
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

  /// Appends a single track to the end of the current queue.
  /// If nothing is playing yet, starts playing the track instead.
  Future<void> addToQueue(Track track) async {
    if (_audioSource != null) {
      await _audioSource!.add(AudioSource.uri(
        Uri.parse(track.audioUrl),
        tag: track.id,
      ));
      state = state.copyWith(queue: [...state.queue, track]);
    } else {
      await playTrack(track);
    }
  }

  /// Removes a track from the queue by index. Prevents removing the last
  /// track. If the removed track was playing, the next track (or previous
  /// if at the end) becomes the current track.
  Future<void> removeFromQueue(int index) async {
    if (_audioSource != null && index >= 0 && index < state.queue.length) {
      if (state.queue.length <= 1) return;
      final wasPlaying = index == state.currentIndex;
      await _audioSource!.removeAt(index);
      final newQueue = List<Track>.from(state.queue)..removeAt(index);
      if (wasPlaying) {
        final newIndex = index.clamp(0, newQueue.length - 1);
        final track = newQueue[newIndex];
        state = state.copyWith(
          queue: newQueue,
          currentIndex: newIndex,
          currentTitle: track.title,
          currentArtist: track.artist,
          currentUrl: track.audioUrl,
        );
      } else {
        // Adjust currentIndex if a track before it was removed.
        final newIndex = state.currentIndex > index ? state.currentIndex - 1 : state.currentIndex;
        state = state.copyWith(
          queue: newQueue,
          currentIndex: newIndex,
        );
      }
    }
  }

  /// Reorders the queue by moving a track from [oldIndex] to [newIndex].
  /// Also moves the track in the underlying ConcatenatingAudioSource and
  /// adjusts the current track index so playback continues on the same track.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_audioSource == null) return;
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    if (newIndex < 0 || newIndex >= state.queue.length) return;

    // Save the currently playing track's ID so we can re-locate it after the move.
    final currentTrackId = state.currentIndex < state.queue.length
        ? state.queue[state.currentIndex].id
        : null;

    await _audioSource!.move(oldIndex, newIndex);

    final newQueue = List<Track>.from(state.queue);
    final track = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, track);

    // Find where the currently playing track ended up after the move.
    int currentIdx = newQueue.indexWhere((t) => t.id == currentTrackId);
    if (currentIdx == -1) currentIdx = state.currentIndex;

    state = state.copyWith(
      queue: newQueue,
      currentIndex: currentIdx,
    );
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

  /// Toggles between play and pause.
  Future<void> playOrPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _updateState();
  }

  /// Seeks to a specific position within the current track.
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _updateState();
  }

  /// Skips to the next track in the queue, if one exists.
  Future<void> seekToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
      _updateState();
    }
  }

  /// Seeks to the previous track, or restarts the current track if more
  /// than 3 seconds have elapsed.
  Future<void> seekToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
    _updateState();
  }

  /// Sets the loop mode (off, all, one).
  setLoopMode(LoopMode mode) {
    _player.setLoopMode(mode);
    state = state.copyWith(loopMode: mode);
  }

  /// Enables or disables shuffle mode.
  setShuffleMode(bool enabled) {
    _player.setShuffleModeEnabled(enabled);
    state = state.copyWith(isShuffleEnabled: enabled);
  }

  /// Clears the current error message from state.
  clearError() {
    state = state.copyWith(error: null);
  }

  AudioPlayer get player => _player;

  /// Syncs the AudioPlayerState with the current AudioPlayer values.
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

/// Immutable state class that holds all playback-related data.
/// Updated via copyWith() to trigger Riverpod rebuilds.
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
