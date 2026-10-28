import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/audio_handler.dart';
import 'package:music_player/models/track.dart';
import 'package:music_player/providers/settings_provider.dart';
import 'package:music_player/services/device_metadata.dart';
import 'package:music_player/services/music_api.dart';
import 'package:music_player/services/stream_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Riverpod provider that exposes the audio player controller and its state
/// to the entire widget tree.
final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerController, AudioPlayerState>((ref) {
      return AudioPlayerController(ref);
    });

/// Central audio player controller that manages playback, queue, shuffle,
/// loop, and all player state. Uses just_audio's AudioPlayer under the hood
/// and wraps it with a Riverpod StateNotifier for reactive UI updates.
///
/// On platforms with audio_service (Android/iOS) the controller drives the
/// handler's shared player, so the media notification/lock screen reflects
/// and controls playback. Elsewhere it owns a private player.
class AudioPlayerController extends StateNotifier<AudioPlayerState> {
  final AudioPlayer _player;
  final bool _ownsPlayer;

  /// Provider ref — used to read settings (autoplay) on demand.
  final Ref _ref;

  /// Reference to the current ConcatenatingAudioSource, used for queue
  /// operations like add, remove, and reorder.
  ConcatenatingAudioSource? _audioSource;

  /// Guards against overlapping autoplay fetches.
  bool _autoplayLoading = false;

  /// True while a retry of autoplay is scheduled — the stalled-at-end
  /// watchdog must not fire into the same failure loop the retry already
  /// covers.
  bool _autoplayPending = false;
  Timer? _autoplayRetryTimer;

  /// Position at the previous watchdog tick, used to detect a player
  /// frozen at the end of the last track between ticks.
  Duration? _lastStallPos;

  /// Set when the controller is disposed so pending autoplay timers and
  /// late stream callbacks can't touch a dead player.
  bool _disposed = false;

  /// True when the current track is within 1s of its end. Used by the
  /// watchdog below: if the player drops to idle without ever emitting
  /// `completed` (e.g. the last track errored out), we still know the
  /// track had essentially finished.
  bool _nearTrackEnd = false;

  /// Bumped whenever a new queue is loaded so stale background resolution
  /// loops (filling silence placeholders) stop touching the new source.
  int _queueGeneration = 0;

  AudioPlayerController(this._ref)
    : _player = musicAudioHandler?.player ?? AudioPlayer(),
      _ownsPlayer = musicAudioHandler == null,
      super(AudioPlayerState()) {
    _initialize();
  }

  /// Builds a media-item tag so the audio_service notification can show
  /// title/artist/artwork for the current track.
  MediaItem _mediaItem(Track t) {
    Uri? art;
    final img = t.imageUrl;
    if (img != null && img.isNotEmpty) {
      try {
        art = Uri.parse(img);
      } catch (_) {
        art = null;
      }
    }
    return MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      duration: t.duration,
      artUri: art,
    );
  }

  /// debugPrint is a no-op in release builds — print() survives, keeping
  /// playback diagnostics visible in `adb logcat` for shipped APKs.
  void _log(String msg) {
    if (kDebugMode) {
      debugPrint(msg);
    } else {
      print(msg);
    }
  }

  /// Sets up stream listeners on the AudioPlayer to keep AudioPlayerState
  /// in sync with the underlying player's position, duration, current index,
  /// and playback state.
  Future<void> _initialize() async {
    // Let notification/lock-screen skips past the end of the queue pull
    // related music (same fill used when the queue finishes naturally).
    final handler = musicAudioHandler;
    if (handler != null) {
      handler.onQueueExhausted = () => _autoplayRelated();
    }

    // Stalled-at-end watchdog: ExoPlayer can reach the end of the last
    // item without ever emitting `completed` — it stays "playing" with
    // the position pinned at the track's end, which the stream-based
    // checks below miss because the playing flag never turns off. Parked
    // at the end (frozen or paused), with nowhere else to go, means the
    // queue is exhausted: pull related music.
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed || _autoplayLoading || _autoplayPending) return;
      // Heartbeat for the keep-ahead prefetch (expires no-ops cheaply).
      unawaited(_prefetchAhead());
      if (!_nearTrackEnd) {
        _lastStallPos = null;
        return;
      }
      if (_player.hasNext || state.loopMode != LoopMode.off) return;
      if (state.queue.isEmpty) return;
      final position = _player.position;
      if (_player.playing) {
        // Still advancing — the natural completion path handles it.
        if (position != _lastStallPos) {
          _lastStallPos = position;
          return;
        }
      } else {
        _lastStallPos = null;
      }
      _lastStallPos = null;
      _nearTrackEnd = false;
      state = state.copyWith(isPlaying: false);
      unawaited(_autoplayRelated());
    });

    // Update current position as the track plays.
    _player.positionStream.listen((position) {
      final duration = _player.duration;
      _nearTrackEnd =
          duration != null &&
          duration.inMilliseconds > 0 &&
          position.inMilliseconds >= duration.inMilliseconds - 1000;
      state = state.copyWith(currentPosition: position);
    });

    // Update total duration when a new track loads.
    _player.durationStream.listen((duration) {
      state = state.copyWith(totalDuration: duration);
    });

    // When the player moves to a different track in the playlist, update
    // the current track info (title, artist, url) and navigation flags.
    _player.currentIndexStream.listen((index) {
      _nearTrackEnd = false;
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
        // If the slot we just entered is still a silence placeholder
        // (its background fill never swapped the real stream in), give
        // it one last chance from cache/disk — otherwise skip the dead
        // air so the queue keeps moving.
        unawaited(_maybeSkipSilence(index, track));
        // And make sure the *next* tracks are ready before they're
        // needed, when autoplay is on.
        unawaited(_prefetchAhead());
      }
    });

    // Sync isPlaying and processing (loading/buffering) flags.
    // Also detect when playback completes.
    _player.playerStateStream.listen((playerState) {
      final processingDone =
          playerState.processingState == ProcessingState.completed;
      state = state.copyWith(
        isPlaying: playerState.playing,
        processing:
            playerState.processingState == ProcessingState.loading ||
            playerState.processingState == ProcessingState.buffering,
        hasNext: _player.hasNext,
        hasPrevious: _player.hasPrevious,
        // Keep loop mode in sync with the player — the notification's
        // repeat button changes it without going through setLoopMode.
        loopMode: _player.loopMode,
      );
      if (processingDone) {
        state = state.copyWith(isPlaying: false);
        // Queue exhausted (loop off): pull related music and keep going.
        if (!_player.hasNext && state.loopMode == LoopMode.off) {
          _autoplayRelated();
        }
      }

      // Watchdog: the last track reached its end (or errored right at the
      // end) but `completed` never fired, so the queue-exhausted branch
      // above was missed. Trigger autoplay anyway so playback continues.
      if ((playerState.processingState == ProcessingState.idle ||
              playerState.processingState == ProcessingState.ready) &&
          !playerState.playing &&
          _nearTrackEnd &&
          !_player.hasNext &&
          state.loopMode == LoopMode.off &&
          state.queue.isNotEmpty) {
        _nearTrackEnd = false;
        _autoplayRelated();
      }
    });

    // Keep the UI volume control in sync with the player.
    _player.volumeStream.listen((volume) {
      state = state.copyWith(volume: volume);
    });

    // Catch playback errors from the event stream. Also clear the
    // processing flag — an errored player stays in STATE_IDLE and never
    // emits another state event, which would otherwise leave the UI
    // spinner running forever. When the last track dies mid-playback
    // (expired stream URL etc.), kick off autoplay so the queue doesn't
    // just stop.
    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        state = state.copyWith(error: 'Playback error: $e', processing: false);
        final duration = _player.duration;
        final position = _player.position;
        final halfway =
            duration == null ||
            duration.inMilliseconds == 0 ||
            position.inMilliseconds >= duration.inMilliseconds ~/ 2;
        if (state.queue.isNotEmpty &&
            !_player.hasNext &&
            halfway &&
            state.loopMode == LoopMode.off) {
          unawaited(_autoplayRelated());
        }
      },
    );

    // Restore the previous queue so the mini player shows where the user
    // left off. Playback stays paused until they press play.
    unawaited(_loadPersistedQueue());
  }

  static const _kQueueKey = 'player.queue.v1';

  /// Persists the current queue, index, and shuffle/loop modes so the app
  /// can restore them after a restart.
  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state.queue.isEmpty) {
        await prefs.remove(_kQueueKey);
        return;
      }
      await prefs.setString(
        _kQueueKey,
        jsonEncode({
          'queue': state.queue.map((t) => t.toJson()).toList(),
          'index': state.currentIndex,
          'shuffle': state.isShuffleEnabled,
          'loop': state.loopMode.name,
        }),
      );
    } catch (_) {
      // Persistence is best-effort — never break playback for it.
    }
  }

  /// Restores a previously saved queue into state (paused). The audio
  /// source is only rebuilt when the user presses play.
  Future<void> _loadPersistedQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kQueueKey);
      if (raw == null || state.queue.isNotEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final queue = (data['queue'] as List)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
      if (queue.isEmpty) return;
      final index = (data['index'] as int? ?? 0).clamp(0, queue.length - 1);
      final loopName = data['loop'] as String?;
      state = state.copyWith(
        queue: queue,
        currentIndex: index,
        currentTitle: queue[index].title,
        currentArtist: queue[index].artist,
        currentUrl: queue[index].audioUrl,
        isShuffleEnabled: data['shuffle'] as bool? ?? false,
        loopMode: LoopMode.values.firstWhere(
          (m) => m.name == loopName,
          orElse: () => LoopMode.off,
        ),
      );
    } catch (_) {
      // Corrupt payload — start fresh.
    }
  }

  /// Loads and plays a track. If [fromQueue] is provided, the entire list
  /// becomes the playback queue (using ConcatenatingAudioSource). [startIndex]
  /// determines which track in the queue to begin playing from.
  ///
  /// Only the starting track is resolved before playback begins (device-side
  /// resolution takes ~1–3s); the rest of the queue starts as silence
  /// placeholders that are swapped for real streams in the background.
  /// Resolving every queue entry up front stalls start-of-playback and
  /// YouTube rate-limits mass parallel manifest fetches.
  ///
  /// Failed attempts are retried up to 3 times with increasing backoff
  /// (2s, 4s) before surfacing a final error.
  Future<void> playTrack(
    Track track, {
    List<Track>? fromQueue,
    int? startIndex,
    }) async {
    // User playback takes over — drop any pending autoplay retry.
    _cancelAutoplayRetry();
    final queue = fromQueue ?? [track];
    final index = (startIndex ?? queue.indexOf(track)).clamp(
      0,
      queue.length - 1,
    );
    final gen = ++_queueGeneration;

    state = state.copyWith(processing: true, error: null);

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        // Resolve only the track about to play.
        final targetUrl = await StreamResolver.instance.resolve(queue[index]);
        if (gen != _queueGeneration) return; // A newer queue took over.

        final sources = [
          for (var i = 0; i < queue.length; i++)
            i == index
                ? AudioSource.uri(
                    Uri.parse(targetUrl),
                    tag: _mediaItem(queue[i]),
                  )
                : SilenceAudioSource(
                    tag: _mediaItem(queue[i]),
                    // Unknown-duration tracks used to get a 1s placeholder,
                    // which made the player skip them the moment resolution
                    // lagged behind. 30s holds the slot long enough for the
                    // background fill to catch up.
                    duration: queue[i].duration ?? const Duration(seconds: 30),
                  ),
        ];
        final concatenating = ConcatenatingAudioSource(children: sources);
        _audioSource = concatenating;

        // Set the audio source and start from the specified index.
        await _player.setAudioSource(concatenating, initialIndex: index);

        // Update state with the new queue and current track info.
        state = state.copyWith(
          queue: queue,
          currentIndex: index,
          currentTitle: queue[index].title,
          currentArtist: queue[index].artist,
          currentUrl: queue[index].audioUrl,
          hasNext: _player.hasNext,
          hasPrevious: _player.hasPrevious,
          error: null,
        );

        await _player.play();

        _saveQueue();

        // Fill the remaining queue entries behind the playback start.
        unawaited(_fillQueueSources(queue, index, gen));
        return;
      } catch (e) {
        _log('[playTrack] attempt $attempt/$maxAttempts failed: $e');
        if (gen != _queueGeneration) return;
        if (attempt < maxAttempts) {
          state = state.copyWith(
            error: "Couldn't play — retrying ($attempt/$maxAttempts)…",
          );
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
        } else {
          state = state.copyWith(
            processing: false,
            error: 'Failed to play: $e',
            errorCanRetry: true,
          );
        }
      }
    }
  }

  /// Resolves the remaining queue entries with a small worker pool and
  /// swaps each silence placeholder for the real stream as it becomes
  /// available. Stops early when a newer queue is loaded ([gen]).
  ///
  /// The next 3 tracks after the current one are resolved first so
  /// track-to-track transitions stay gapless; the rest follow behind.
  ///
  /// Fetches are spaced out (~400ms apart per worker): slamming YouTube
  /// with parallel manifest requests trips its rate limit, after which
  /// every subsequent resolve hangs and times out.
  Future<void> _fillQueueSources(
    List<Track> queue,
    int resolvedIndex,
    int gen,
  ) async {
    const workers = 3;
    // Upcoming tracks first, then everything else.
    final seen = <int>{};
    for (var i = resolvedIndex + 1; i < queue.length; i++) {
      seen.add(i);
    }
    for (var i = 0; i < resolvedIndex; i++) {
      seen.add(i);
    }
    final order = seen.toList();
    var next = 0;
    Future<void> worker() async {
      while (next < order.length && gen == _queueGeneration) {
        final i = order[next++];
        if (i == resolvedIndex) continue;
        final track = queue[i];
        String url;
        try {
          url = await StreamResolver.instance.resolve(track);
        } catch (_) {
          // Unresolvable on this platform — keep the silence placeholder.
          // Warn when it's the very next track: the user would otherwise
          // hear dead air when it comes up.
          if (gen == _queueGeneration && i == resolvedIndex + 1) {
            state = state.copyWith(
              error: '"${track.title}" couldn\'t load — skipping ahead',
            );
          }
          continue;
        }
        if (gen != _queueGeneration) return;
        await _replacePending(track, url, gen);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }

    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  }

  /// Replaces the silence placeholder for [track] with the real stream at
  /// its current position. Serialized: index-based mutations must not
  /// interleave or they'd hit stale indices.
  Future<void> _replacePending(Track track, String url, int gen) async {
    final prev = _replaceMutex;
    final gate = Completer<void>();
    _replaceMutex = gate.future;
    await prev;
    try {
      if (gen != _queueGeneration) return;
      final source = _audioSource;
      if (source == null) return;
      final tag = track.id;
      final seq = source.sequence;
      final i = seq.indexWhere(
        (s) => s.tag is MediaItem && (s.tag as MediaItem).id == tag,
      );
      if (i < 0 || seq[i] is! SilenceAudioSource) return;
      await source.removeAt(i);
      await source.insert(
        i,
        AudioSource.uri(Uri.parse(url), tag: _mediaItem(track)),
      );
    } catch (_) {
      // Queue was mutated concurrently (track removed/reordered) — skip.
    } finally {
      gate.complete();
    }
  }

  Future<void> _replaceMutex = Future.value();

  /// Appends a single track to the end of the current queue.
  /// If nothing is playing yet, starts playing the track instead.
  Future<void> addToQueue(Track track) async {
    if (_audioSource != null) {
      final url = await StreamResolver.instance.resolve(track);
      await _audioSource!.add(
        AudioSource.uri(Uri.parse(url), tag: _mediaItem(track)),
      );
      state = state.copyWith(queue: [...state.queue, track]);
      _saveQueue();
    } else {
      await playTrack(track);
    }
  }

  /// Inserts a single track right after the current one so it plays next.
  /// If nothing is playing yet, starts playing the track instead.
  Future<void> playNext(Track track) async {
    if (_audioSource != null && state.queue.isNotEmpty) {
      final insertAt = (state.currentIndex + 1).clamp(0, state.queue.length);
      final url = await StreamResolver.instance.resolve(track);
      await _audioSource!.insert(
        insertAt,
        AudioSource.uri(Uri.parse(url), tag: _mediaItem(track)),
      );
      final newQueue = List<Track>.from(state.queue)..insert(insertAt, track);
      state = state.copyWith(queue: newQueue, hasNext: _player.hasNext);
      _saveQueue();
    } else {
      await playTrack(track);
    }
  }

  /// Sets the playback volume (0.0 – 1.0).
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    await _player.setVolume(v);
    state = state.copyWith(volume: v);
  }

  double _lastAudibleVolume = 1.0;

  /// Mutes (volume 0) or restores the previous audible volume.
  Future<void> toggleMute() async {
    if (state.volume > 0) {
      _lastAudibleVolume = state.volume;
      await setVolume(0);
    } else {
      await setVolume(_lastAudibleVolume > 0 ? _lastAudibleVolume : 1.0);
    }
  }

  /// Plays [tracks] starting at a random index with shuffle mode enabled.
  Future<void> shufflePlay(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    setShuffleMode(true);
    final start = Random().nextInt(tracks.length);
    await playTrack(tracks[start], fromQueue: tracks, startIndex: start);
  }

  /// When the queue runs out, fetch tracks related to the last played song
  /// and continue playback with them. Uses the backend radio on web/desktop;
  /// serverless Android falls back to an on-device search for similar music.
  /// Reentrancy guard so concurrent index events don't double-skip.
  bool _silenceSkipping = false;

  /// A silence placeholder that reaches the front (its background fill
  /// never replaced it — e.g. YouTube rate-limited the resolution) plays
  /// ~30s of dead air before the queue moves on. Give the slot one
  /// last-chance resolve (cache/disk URLs work even during a cooldown);
  /// if that fails too, skip past it instead of sitting silently.
  Future<void> _maybeSkipSilence(int index, Track track) async {
    if (_silenceSkipping || _disposed) return;
    final source = _audioSource;
    if (source == null) return;
    final seq = source.sequence;
    final slot = seq.indexWhere(
      (s) => s.tag is MediaItem && (s.tag as MediaItem).id == track.id,
    );
    if (slot < 0 || seq[slot] is! SilenceAudioSource) return;
    _silenceSkipping = true;
    try {
      _log('[queue] silence slot reached (${track.title}) — last-chance resolve');
      final url = await StreamResolver.instance.resolve(track);
      if (_disposed) return;
      await _replacePending(track, url, _queueGeneration);
      if (_player.currentIndex == index) {
        await _player.seek(Duration.zero, index: index);
      }
    } catch (e) {
      _log('[queue] silence slot unresolvable (${track.title}) — skipping: $e');
      try {
        if (_player.hasNext) {
          await _player.seek(Duration.zero, index: index + 1);
        } else {
          state = state.copyWith(isPlaying: false, processing: false);
          await _player.pause();
          unawaited(_autoplayRelated());
        }
      } catch (_) {
        // Seek raced another state change — the watchdogs cover it.
      }
    } finally {
      _silenceSkipping = false;
    }
  }

  /// Fresh related tracks for [seed], minus whatever is already queued.
  /// Backend sessions use the recommendations API with a charts
  /// fallback; serverless Android goes through the (memoized) on-device
  /// related feed. Empty list = feed unreachable or exhausted.
  Future<List<Track>> _fetchRelated(Track seed) async {
    var fresh = const <Track>[];
    if (usesBackend) {
      if (seed.videoId != null) {
        try {
          final related = await musicApi.getRecommendations(
            videoId: seed.videoId!,
            limit: 10,
          );
          final existing = state.queue.map((t) => t.id).toSet();
          fresh = related.where((t) => !existing.contains(t.id)).toList();
        } catch (_) {
          // Demo/invalid seed or radio error — try the charts feed.
        }
      }
      if (fresh.isEmpty) {
        try {
          final charts = await musicApi.getCharts(limit: 10);
          final existing = state.queue.map((t) => t.id).toSet();
          fresh = charts.where((t) => !existing.contains(t.id)).take(10).toList();
        } catch (_) {
          // No fallback available.
        }
      }
    } else if (seed.videoId != null) {
      try {
        final existing = state.queue.map((t) => t.id).toSet();
        fresh = await DeviceMetadata.instance.related(
          seed,
          limit: 10,
          excludeIds: existing,
        );
      } catch (_) {
        // Related feed unavailable — let playback end quietly.
      }
    }
    return fresh;
  }

  /// How many slots ahead prefetch pre-resolves URLs for. Metadata only
  /// (a few KB per track) — audio stays lazily buffered by the player.
  static const _prefetchDepth = 2;

  /// How many related tracks the tail top-up appends at a time, keeping
  /// data use well under a single track's worth of stream size.
  static const _prefetchTail = 3;

  /// Only top up when fewer than this many tracks remain ahead.
  static const _prefetchKeepAhead = 3;

  /// Keeps the queue a short distance ahead of the playhead whenever
  /// autoplay is on, so playback is continuous without bulk-loading:
  ///
  /// 1. *URL warming* — the next one or two slots are resolved now
  ///    instead of on transition. Manifest lookups are metadata-sized
  ///    and cache-first, so a warmed later slot never re-requests.
  /// 2. *Tail top-up* — when fewer than [_prefetchKeepAhead] tracks
  ///    remain ahead, a few related tracks are appended mid-playback
  ///    (single add()s — no pause, no timeline rebuild, zero
  ///    interruption) and only after each resolves.
  ///
  /// Small numbers by design: pre-resolving the whole queue would spam
  /// YouTube's anonymous limits, and pre-buffering real audio would
  /// burn data the user didn't ask for. The rate limit is protected the
  /// same way playback is: resolveAll stays sequential, paced and
  /// cache-first, and cooldowns make the prefetch stand aside (failures
  /// here never schedule retries — exhaustion recovery owns recovery).
  Future<void> _prefetchAhead() async {
    if (_disposed || _autoplayLoading || _autoplayPending) return;
    final enabled = _ref.read(
      settingsProvider.select((s) => s.autoplayRelated),
    );
    if (!enabled) return;
    if (state.queue.isEmpty || _audioSource == null) return;

    final index = state.currentIndex;
    final queue = state.queue;
    final remaining = queue.length - index - 1;

    if (remaining > _prefetchKeepAhead) {
      // 1) Warm the next slots that aren't already in cache/local.
      final toWarm = <Track>[];
      for (var j = 1; j <= _prefetchDepth && index + j < queue.length; j++) {
        final track = queue[index + j];
        if (!StreamResolver.instance.hasCachedUrl(track)) toWarm.add(track);
      }
      if (toWarm.isEmpty) return;
      _autoplayLoading = true;
      try {
        final gen = _queueGeneration;
        final urls = await StreamResolver.instance.resolveAll(toWarm);
        if (_disposed || gen != _queueGeneration) return;
        final warmed = urls.where((u) => u.isNotEmpty).length;
        if (warmed > 0) {
          _log('[prefetch] warmed $warmed/${toWarm.length} ahead');
        }
      } catch (e) {
        // Cooldowns and dead URLs are expected here; exhaustion
        // recovery deals with them if they matter.
        _log('[prefetch] warm failed: $e');
      } finally {
        _autoplayLoading = false;
      }
      return;
    }

    // 2) Tail top-up: append a few related tracks, resolved one by one.
    final seedIndex = index.clamp(0, queue.length - 1);
    final seed = queue[seedIndex];
    _autoplayLoading = true;
    try {
      final fresh = await _fetchRelated(seed);
      if (fresh.isEmpty || _disposed) return;
      final gen = _queueGeneration;
      final toAppend = fresh.take(_prefetchTail).toList();
      final urls = await StreamResolver.instance.resolveAll(toAppend);
      if (_disposed || gen != _queueGeneration) return;
      var appended = 0;
      for (var i = 0; i < toAppend.length; i++) {
        if (urls[i].isEmpty) continue;
        final source = _audioSource;
        if (source == null || gen != _queueGeneration) break;
        await source.add(
          AudioSource.uri(Uri.parse(urls[i]), tag: _mediaItem(toAppend[i])),
        );
        state = state.copyWith(
          queue: [...state.queue, toAppend[i]],
          hasNext: _player.hasNext,
        );
        appended++;
      }
      if (appended > 0) {
        _saveQueue();
        _cancelAutoplayRetry();
        _log('[prefetch] topped up tail (+$appended)');
      }
    } catch (e) {
      // Never schedule a retry from prefetch — the exhaustion
      // watchdogs handle recovery when the tail genuinely runs dry.
      _log('[prefetch] top-up failed: $e');
    } finally {
      _autoplayLoading = false;
    }
  }

  Future<void> _autoplayRelated() async {
    final enabled = _ref.read(
      settingsProvider.select((s) => s.autoplayRelated),
    );
    if (!enabled || _autoplayLoading) return;
    if (state.queue.isEmpty) return;

    final seedIndex = state.currentIndex.clamp(0, state.queue.length - 1);
    final seed = state.queue[seedIndex];

    _autoplayLoading = true;
    try {
      final fresh = await _fetchRelated(seed);
      if (fresh.isEmpty) {
        // Feed empty or unreachable — schedule a retry so playback
        // resumes when it recovers instead of stopping for good.
        _log('[autoplay] related feed empty — scheduling retry');
        _scheduleAutoplayRetry();
        return;
      }

      // While the player is still in its ended state with playback flag on,
      // ExoPlayer auto-jumps into whatever is appended next — combined with
      // the explicit seek below that would skip the first fresh track.
      // Freeze first so the seek is the only step.
      if (_player.playing) {
        await _player.pause();
      }

      if (_audioSource == null) {
        await playTrack(
          fresh.first,
          fromQueue: [...state.queue, ...fresh],
          startIndex: state.queue.length,
        );
        return;
      }

      // Append in one batched timeline change instead of a burst of
      // single-item updates, keeping media-session/notification churn low.
      // Only resolve a handful up front — resolveAll paces them
      // sequentially to avoid YouTube's rate limit, and the queue-fill
      // logic picks up any that come back empty later.
      final toResolve = fresh.take(5).toList();
      final urls = await StreamResolver.instance.resolveAll(toResolve);
      final playable = <(Track, String)>[
        for (var i = 0; i < toResolve.length; i++)
          if (urls[i].isNotEmpty) (toResolve[i], urls[i]),
      ];
      _log(
        '[autoplay] resolved ${playable.length}/${toResolve.length} streams',
      );
      if (playable.isEmpty) {
        state = state.copyWith(
          error: 'YouTube is busy — related music will resume shortly',
        );
        _scheduleAutoplayRetry();
        return;
      }
      // Append the playable related tracks via a full timeline rebuild.
      // Plain ConcatenatingAudioSource.addAll kept failing in release
      // sessions with a runtime type error deep inside just_audio's
      // dynamic-children handling (List<AudioSource> vs
      // Iterable<IndexedAudioSource>), and rebuilding is cheap here: every
      // previously played slot re-resolves from the resolver's in-memory
      // or disk cache instead of touching YouTube again.
      final appended = playable.map((p) => p.$1).toList();
      final newQueue = [...state.queue, ...appended];
      _cancelAutoplayRetry();
      state = state.copyWith(queue: newQueue);
      _saveQueue();
      await _rebuildQueue(newQueue, newQueue.length - appended.length);
    } catch (e) {
      _log('[autoplay] append/play failed: $e');
      _log('[autoplay] stack: ${StackTrace.current}');
      _scheduleAutoplayRetry();
    } finally {
      _autoplayLoading = false;
    }
  }

  /// Rebuilds the entire player timeline from [queue] starting at
  /// [startIndex]. Each slot resolves through the resolver first — cache
  /// hits (memory or disk) attach their real stream without touching
  /// YouTube; anything unresolvable falls back to a silence placeholder,
  /// which the fill logic and silence-skip handle as usual.
  ///
  /// Only used at queue-end append time, when the old timeline is already
  /// spent — slots reload from cache in a beat.
  Future<void> _rebuildQueue(List<Track> queue, int startIndex) async {
    final gen = _queueGeneration;
    final sources = <AudioSource>[];
    for (var i = 0; i < queue.length; i++) {
      String url;
      try {
        url = await StreamResolver.instance.resolve(queue[i]);
      } catch (e) {
        sources.add(
          SilenceAudioSource(
            tag: _mediaItem(queue[i]),
            duration: queue[i].duration ?? const Duration(seconds: 30),
          ),
        );
        _log('[queue] rebuild slot unresolved (${queue[i].title}): $e');
        continue;
      }
      sources.add(AudioSource.uri(Uri.parse(url), tag: _mediaItem(queue[i])));
    }
    final concatenating = ConcatenatingAudioSource(children: sources);
    if (gen != _queueGeneration) return;
    _audioSource = concatenating;
    await _player.setAudioSource(concatenating, initialIndex: startIndex);
    await _player.play();
    _updateState();
  }

  /// Schedules one retry after autoplay-related music failed to load
  /// (rate limit, feed timeout). When the resolver is cooling down,
  /// waits out the cooldown so the retry lands after YouTube is
  /// reachable again instead of failing straight back into it.
  void _scheduleAutoplayRetry() {
    _autoplayRetryTimer?.cancel();
    _autoplayPending = true;
    final remaining = StreamResolver.instance.cooldownRemaining;
    final delay = remaining > const Duration(seconds: 45)
        ? remaining + const Duration(seconds: 5)
        : const Duration(seconds: 60);
    _log('[autoplay] retry scheduled in ${delay.inSeconds}s');
    _autoplayRetryTimer = Timer(delay, () {
      _autoplayRetryTimer = null;
      final atEnd = !_disposed &&
          state.queue.isNotEmpty &&
          !_player.hasNext &&
          state.loopMode == LoopMode.off;
      _autoplayPending = false;
      if (!atEnd) return;
      _nearTrackEnd = false;
      unawaited(_autoplayRelated());
    });
  }

  /// Cancels any pending autoplay retry — the user started playback
  /// themselves (playTrack) or playback is being torn down.
  void _cancelAutoplayRetry() {
    _autoplayRetryTimer?.cancel();
    _autoplayRetryTimer = null;
    _autoplayPending = false;
    _lastStallPos = null;
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
        // Adjust currentIndex if a track before it was removed, and re-sync
        // the displayed track — the index stream fires while the old queue is
        // still in state, which would otherwise leave a stale title behind.
        final newIndex = state.currentIndex > index
            ? state.currentIndex - 1
            : state.currentIndex;
        final track = newQueue[newIndex.clamp(0, newQueue.length - 1)];
        state = state.copyWith(
          queue: newQueue,
          currentIndex: newIndex,
          currentTitle: track.title,
          currentArtist: track.artist,
          currentUrl: track.audioUrl,
        );
      }
      _saveQueue();
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

    // Re-sync the displayed track in case the index stream fired mid-move
    // while the old queue was still in state.
    final current = newQueue[currentIdx.clamp(0, newQueue.length - 1)];
    state = state.copyWith(
      queue: newQueue,
      currentIndex: currentIdx,
      currentTitle: current.title,
      currentArtist: current.artist,
      currentUrl: current.audioUrl,
    );
    _saveQueue();
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

  /// Stops playback and clears the queue, hiding the mini player.
  Future<void> stopAndClear() async {
    _cancelAutoplayRetry();
    await _player.stop();
    _audioSource = null;
    state = AudioPlayerState();
    _saveQueue();
  }

  /// Shutdown for app exit: stops playback and the audio handler so the
  /// media notification doesn't linger, but keeps the queue and its
  /// persisted copy intact so the next launch restores where the user
  /// left off (paused).
  Future<void> exitPlayback() async {
    _cancelAutoplayRetry();
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await musicAudioHandler?.stop();
    } catch (_) {}
    state = state.copyWith(
      isPlaying: false,
      processing: false,
      currentPosition: Duration.zero,
    );
  }

  /// Toggles between play and pause. When resuming after an app restart
  /// (queue restored but no audio source yet), rebuilds the queue from
  /// the persisted state first.
  Future<void> playOrPause() async {
    if (_player.playing) {
      await _player.pause();
    } else if (_audioSource == null && state.queue.isNotEmpty) {
      // Restored-from-disk queue — the player has no source yet. Rebuild
      // it starting at the previously current track.
      final index = state.currentIndex.clamp(0, state.queue.length - 1);
      await playTrack(
        state.queue[index],
        fromQueue: state.queue,
        startIndex: index,
      );
      return;
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

  /// Skips to the next track in the queue. When the queue is exhausted,
  /// pulls related music first so Next keeps working (same as when the
  /// queue finishes naturally).
  Future<void> seekToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
      _updateState();
      return;
    }
    final before = _player.currentIndex;
    await _autoplayRelated();
    if (_player.currentIndex == before && _player.hasNext) {
      await _player.seekToNext();
    }
    _updateState();
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

  /// Sets the playback speed (0.5x - 2.0x).
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  /// Clears the current error message from state.
  clearError() {
    state = state.copyWith(error: null);
  }

  /// Re-attempts the current track after a retryable failure. Keeps the
  /// existing queue so the rest of the session is preserved.
  Future<void> retryCurrent() async {
    if (state.queue.isEmpty) return;
    final index = state.currentIndex.clamp(0, state.queue.length - 1);
    await playTrack(
      state.queue[index],
      fromQueue: state.queue,
      startIndex: index,
    );
  }

  AudioPlayer get player => _player;

  @override
  void dispose() {
    _disposed = true;
    _autoplayRetryTimer?.cancel();
    // Only dispose a player this controller created — the audio handler's
    // shared player outlives the controller.
    if (_ownsPlayer) {
      _player.dispose();
    }
    super.dispose();
  }

  /// Syncs the AudioPlayerState with the current AudioPlayer values.
  void _updateState() {
    state = state.copyWith(
      isPlaying: _player.playing,
      processing:
          _player.processingState == ProcessingState.loading ||
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

  /// True when [error] is a final playback failure the user can retry
  /// (auto-retries are exhausted). Transient messages don't set it.
  final bool errorCanRetry;
  final double volume;

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
    this.errorCanRetry = false,
    this.volume = 1.0,
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
    bool? errorCanRetry,
    double? volume,
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
      errorCanRetry: errorCanRetry ?? false,
      volume: volume ?? this.volume,
    );
  }
}

