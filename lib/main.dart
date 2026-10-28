import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:url_launcher/url_launcher.dart';

import 'features/player/player_controller.dart';
import 'features/player/player_page.dart';
import 'features/player/mini_player.dart';
import 'features/player/download_bar.dart';
import 'features/playlist/playlist_page.dart';
import 'features/playlist/playlist_detail_page.dart';
import 'features/downloads/downloads_page.dart';
import 'features/genres/genres_page.dart';
import 'features/genres/genre_detail_page.dart';
import 'features/device/device_music_page.dart';
import 'providers/music_provider.dart';
import 'providers/playlist_manager.dart';
import 'providers/download_manager.dart';
import 'providers/settings_provider.dart';
import 'models/genre.dart';
import 'models/track.dart';
import 'services/music_api.dart';
import 'services/app_updater.dart';
import 'services/update_install_stub.dart'
    if (dart.library.js_interop) 'package:music_player/services/update_install_stub.dart'
    if (dart.library.io) 'package:music_player/services/update_install_io.dart';
import 'services/download_save_stub.dart'
    if (dart.library.js_interop) 'package:music_player/services/download_save_web.dart'
    if (dart.library.io) 'package:music_player/services/download_save_io.dart';
import 'widgets/horizontal_row.dart';
import 'widgets/track_menu.dart';
import 'audio_handler.dart';

/// Regions supported by YouTube Music charts (used by Settings and Home).
const Map<String, String> kRegions = {
  'US': 'United States',
  'GB': 'United Kingdom',
  'PH': 'Philippines',
  'CA': 'Canada',
  'AU': 'Australia',
  'DE': 'Germany',
  'FR': 'France',
  'JP': 'Japan',
  'KR': 'South Korea',
  'IN': 'India',
  'MX': 'Mexico',
  'BR': 'Brazil',
  'ID': 'Indonesia',
  'TH': 'Thailand',
  'VN': 'Vietnam',
  'SG': 'Singapore',
  'MY': 'Malaysia',
  'ES': 'Spain',
  'IT': 'Italy',
  'NL': 'Netherlands',
  'ZZ': 'Global (default)',
};

/// Languages supported by the backend (used by Settings).
const Map<String, String> kLanguages = {
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'pt': 'Portuguese',
  'ja': 'Japanese',
  'ko': 'Korean',
  'hi': 'Hindi',
  'id': 'Indonesian',
  'th': 'Thai',
  'vi': 'Vietnamese',
};

/// Reusable widget that scales up slightly on hover and responds to taps.
/// Used on track cards and playlist cards for a hover interaction effect.
class HoverScale extends StatefulWidget {
  final Widget child;
  final double scale;
  final VoidCallback? onTap;

  const HoverScale({
    super.key,
    required this.child,
    this.scale = 1.05,
    this.onTap,
  });

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 150),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Root app widget. Sets up Material 3 theming, routes, and the main screen.
class MusicPlayerApp extends ConsumerWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Musicap',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeMode,
      home: const MainScreen(),
      routes: {
        '/player': (context) => const PlayerPage(),
        '/playlist': (context) => const PlaylistPage(),
      },
    );
  }
}

/// Builds the Musicap-branded theme in [brightness]. The seed teal is
/// sampled from the Musicap logo gradient (~#0E5F52 → #2FD9C7) so both
/// light and dark modes carry the brand color through Material 3.
ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF17A79B),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Main screen with a bottom navigation bar and a persistent mini player.
/// Uses IndexedStack to preserve tab state across switches.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;

  /// Shows a dialog for a final failure ([message]) with Retry/Cancel.
  /// [onRetry] re-attempts the failed action; Cancel just dismisses.
  void _showRetryDialog({
    required String title,
    required String message,
    required VoidCallback onRetry,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onRetry();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  /// Back-press handler: pause playback and ask for confirmation before
  /// leaving. Exit also stops the audio service so the media notification
  /// doesn't linger after the app is gone.
  Future<void> _confirmExit() async {
    final player = ref.read(audioPlayerProvider.notifier);
    final playerState = ref.read(audioPlayerProvider);
    if (playerState.isPlaying) {
      await player.pause();
    }
    final hadMusic = playerState.currentTitle.isNotEmpty;
    if (!mounted) return;
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Musicap?'),
        content: Text(hadMusic ? 'Music will stop playing.' : 'Close the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (exit == true) {
      await player.exitPlayback();
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioPlayerProvider);

    // Apply playback speed whenever it changes (including initial load).
    ref.listen(settingsProvider.select((s) => s.playbackSpeed), (
      previous,
      next,
    ) {
      ref.read(audioPlayerProvider.notifier).setSpeed(next);
    });

    // Playback failures: final errors (auto-retries exhausted) get a
    // retry dialog; transient messages (e.g. "retrying 1/3") stay as
    // brief snackbars.
    if (state.error != null && mounted) {
      final canRetry = state.errorCanRetry;
      final message = state.error!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(audioPlayerProvider.notifier).clearError();
        if (canRetry) {
          _showRetryDialog(
            title: 'Playback failed',
            message: message,
            onRetry: () =>
                ref.read(audioPlayerProvider.notifier).retryCurrent(),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }

    // Download failures always get a retry dialog — they're final.
    final downloadError = ref.watch(downloadErrorProvider);
    if (downloadError != null && mounted) {
      final (message, track) = downloadError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(downloadErrorProvider.notifier).state = null;
        _showRetryDialog(
          title: 'Download failed',
          message: message,
          onRetry: () =>
              ref.read(downloadManagerProvider.notifier).startDownload(track),
        );
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: usesBackend
              ? const [
                  HomePage(),
                  GenresPage(),
                  PlaylistPage(),
                  DownloadsPage(),
                  SettingsPage(),
                ]
              : const [
                  HomePage(),
                  DeviceMusicPage(),
                  PlaylistPage(),
                  SettingsPage(),
                ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            // Bottom navigation bar for switching between main sections.
            // Backend platforms show Genres + Downloads; serverless Android
            // combines Local + Downloads into one "On Device" page.
            BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              items: usesBackend
                  ? const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.explore),
                        label: 'Genres',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.queue_music),
                        label: 'Library',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.download),
                        label: 'Downloads',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.settings),
                        label: 'Settings',
                      ),
                    ]
                  : const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.folder),
                        label: 'On Device',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.queue_music),
                        label: 'Library',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.settings),
                        label: 'Settings',
                      ),
                    ],
              selectedItemColor: Colors.blueAccent,
              unselectedItemColor: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

/// Home page with a search bar in the AppBar and a dashboard of
/// Recently Played, Recommended, and Playlists sections.
/// Search results display in a grid view.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Syncs the search text field input to the Riverpod search query
  /// provider, and returns to the dashboard as soon as the field goes
  /// empty (no input = dashboard, per the search contract).
  void _onSearchChanged() {
    ref.read(searchQueryProvider.notifier).state = _searchController.text;
    if (_searchController.text.trim().isEmpty) {
      // Either the clear button or deleting the text — drop the
      // committed query so the dashboard comes back.
      ref.read(searchSubmittedProvider.notifier).state = '';
    }
  }

  /// Runs a search: fills the field, commits the query, saves to
  /// history, and hides the keyboard.
  void _runSearch(String query) {
    _searchController.text = query;
    ref.read(searchQueryProvider.notifier).state = query;
    ref.read(searchSubmittedProvider.notifier).state = query;
    ref.read(recentSearchesProvider.notifier).addSearch(query);
    _searchFocusNode.unfocus();
  }

  /// Plays a track as a single-song queue (search results should only
  /// queue the song the user picked, not the whole result list).
  void _playTrack(Track track, {List<Track>? fromQueue}) async {
    final controller = ref.read(audioPlayerProvider.notifier);
    final queue = fromQueue ?? [track];
    final index = queue.indexOf(track);
    await controller.playTrack(
      track,
      fromQueue: queue,
      startIndex: index >= 0 ? index : 0,
    );
    ref.read(recentlyPlayedProvider.notifier).addTrack(track);
  }

  @override
  Widget build(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        // Search bar is permanently in the AppBar for quick access.
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search tracks, artists...',
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                    },
                  )
                : null,
          ),
          onSubmitted: (value) {
            final query = value.trim();
            if (query.isNotEmpty) {
              // Results only load now — tapping the search action is
              // what triggers the YouTube fetch, not the typing.
              ref.read(searchSubmittedProvider.notifier).state = query;
              ref.read(recentSearchesProvider.notifier).addSearch(query);
            }
            _searchFocusNode.unfocus();
          },
        ),
        actions: [
          // Download panel icon with active download badge.
          _DownloadIcon(),
        ],
      ),
      // Search results only after the search action was tapped; with no
      // input in the field the dashboard is shown instead of anything
      // search-related.
      body: _buildBody(searchResultsAsync, ref.watch(searchSubmittedProvider)),
    );
  }

  Widget _buildBody(
    AsyncValue<List<Track>> resultsAsync,
    String submittedQuery,
  ) {
    if (submittedQuery.trim().isNotEmpty) {
      return _buildSearchResults(resultsAsync, submittedQuery);
    }
    return _buildDashboard();
  }

  /// Search view: list rows with art/title/artist/duration, suggestions
  /// while results load, and distinct loading/empty/error states.
  Widget _buildSearchResults(
    AsyncValue<List<Track>> resultsAsync,
    String query,
  ) {
    return resultsAsync.when(
      loading: () => _buildSuggestionList(),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'Search failed: $err',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(searchResultsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (results) {
        if (results.isEmpty) {
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.search_off,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No results for "$query"',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _suggestionsBelow(),
            ],
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final track = results[index];
            return _buildResultTile(track);
          },
        );
      },
    );
  }

  /// A single search result row. Tapping queues only the picked song.
  Widget _buildResultTile(Track track) {
    return TrackTile(
      track: track,
      showDuration: true,
      showDownloadBadge: true,
      onTap: () => _playTrack(track),
    );
  }

  /// Autocomplete suggestion rows shown while results are loading.
  Widget _buildSuggestionList() {
    final suggestionsAsync = ref.watch(searchSuggestionsProvider);
    return suggestionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: CircularProgressIndicator()),
      data: (suggestions) {
        if (suggestions.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          children: [
            for (final suggestion in suggestions)
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(suggestion),
                onTap: () => _runSearch(suggestion),
              ),
          ],
        );
      },
    );
  }

  /// Suggestions shown below the "no results" empty state.
  Widget _suggestionsBelow() {
    final suggestionsAsync = ref.watch(searchSuggestionsProvider);
    return suggestionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Divider(height: 1),
                for (final suggestion in suggestions)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.search, size: 18),
                    title: Text(suggestion),
                    onTap: () => _runSearch(suggestion),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds the dashboard view with quick genre picks, recently played,
  /// recommendations, region-based charts, and playlists.
  Widget _buildDashboard() {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);
    final chartsAsync = usesBackend ? ref.watch(chartsProvider) : null;
    final recommendationsAsync = usesBackend
        ? ref.watch(recommendationsProvider)
        : null;
    final genresAsync = usesBackend ? ref.watch(genresProvider) : null;
    final playlists = ref.watch(playlistManagerProvider);
    final region = ref.watch(settingsProvider.select((s) => s.region));
    final regionName = kRegions[region] ?? region;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Genre quick-picks — tap to open that genre's playlists.
          if (genresAsync != null) _buildGenreChips(genresAsync),
          if (recentlyPlayed.isNotEmpty)
            _buildSection(title: 'Recently Played', tracks: recentlyPlayed),
          // Personalized recommendations from the radio/watch playlist.
          if (recommendationsAsync != null)
            recommendationsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              // Recommendations are optional — hide the section on failure.
              error: (_, __) => const SizedBox.shrink(),
              data: (recs) => recs.isEmpty
                  ? const SizedBox.shrink()
                  : _buildSection(title: 'Made For You', tracks: recs),
            ),
          // Trending charts for the selected region.
          if (chartsAsync != null)
            chartsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Could not load charts: $err',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
              data: (charts) => _buildSection(
                title: 'Trending in $regionName',
                tracks: charts,
              ),
            ),
          _buildPlaylistsSection(playlists),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Horizontal row of genre chips (first genres section) for quick access.
  Widget _buildGenreChips(AsyncValue<List<GenreSection>> genresAsync) {
    return genresAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (sections) {
        final items = sections.isNotEmpty
            ? sections.first.items
            : const <GenreItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: HorizontalRow(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemSpacing: 8,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return HoverScale(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GenreDetailPage(item: item),
                  ),
                ),
                scale: 1.03,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Builds a horizontally scrollable section with a title and track cards.
  Widget _buildSection({required String title, required List<Track> tracks}) {
    return HorizontalRow(
      title: title,
      height: 200,
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _buildTrackCard(track, fromQueue: tracks, width: 140);
      },
    );
  }

  /// Builds a single track card with album art placeholder, title, artist,
  /// a download status indicator, and a 3-dot menu for actions.
  Widget _buildTrackCard(
    Track track, {
    required List<Track> fromQueue,
    double? width,
  }) {
    final dlState = ref.watch(downloadManagerProvider)[track.id];
    final status = dlState?.status;

    return HoverScale(
      onTap: () => _playTrack(track, fromQueue: fromQueue),
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // Album art or placeholder.
                Container(
                  width: double.infinity,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: track.imageUrl != null
                      ? Image.network(
                          track.imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, url, error) => Center(
                            child: Icon(
                              Icons.music_note,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.music_note,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                ),
                // Download status indicator (bottom-left corner).
                if (status != null && status != DownloadStatus.notDownloaded)
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface
                            .withOpacity(0.85),
                        shape: BoxShape.circle,
                      ),
                      child: status == DownloadStatus.downloading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                value: dlState!.progress,
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : Icon(
                              Icons.download_done,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                    ),
                  ),
                // 3-dot menu overlay for queue actions.
                Positioned(
                  top: 4,
                  right: 4,
                  child: TrackMenuButton(
                    track,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              track.artist,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a horizontally scrollable playlist section.
  Widget _buildPlaylistsSection(List<Playlist> playlists) {
    return HorizontalRow(
      title: 'Your Playlists',
      titleTrailing: TextButton(
        onPressed: () {
          Navigator.pushNamed(context, '/playlist');
        },
        child: const Text('See all'),
      ),
      height: 140,
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _buildPlaylistCard(playlist);
      },
    );
  }

  /// Builds a single playlist card with a 3-dot menu for "Add all to queue".
  Widget _buildPlaylistCard(Playlist playlist) {
    return HoverScale(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaylistDetailPage(playlistId: playlist.id),
          ),
        );
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: 120,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.queue_music,
                      size: 32,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
                // 3-dot menu overlay for queue actions.
                Positioned(
                  top: 2,
                  right: 2,
                  child: PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurface
                          .withOpacity(0.6),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (value) async {
                      if (value == 'addAllQueue') {
                        // Await each add: a fire-and-forget loop lets the first
                        // track's playTrack (started when the queue is empty)
                        // overwrite the state written by later appends, leaving
                        // the queue list out of sync with the player.
                        for (final track in playlist.tracks) {
                          await ref
                              .read(audioPlayerProvider.notifier)
                              .addToQueue(track);
                        }
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added ${playlist.tracks.length} tracks to queue',
                            ),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'addAllQueue',
                        child: Text('Add all to queue'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${playlist.tracks.length} tracks',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Download icon with a badge showing the number of active downloads.
class _DownloadIcon extends ConsumerWidget {
  const _DownloadIcon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final activeCount = downloads.values
        .where((d) => d.status == DownloadStatus.downloading)
        .length;

    return IconButton(
      onPressed: () => DownloadPanel.show(context),
      icon: Badge(
        label: activeCount > 0 ? Text('$activeCount') : null,
        isLabelVisible: activeCount > 0,
        child: const Icon(Icons.download),
      ),
    );
  }
}

/// Simple settings page with an About dialog.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// Display name of the download folder (web) or its path (desktop).
  String? _downloadDir;

  /// Backend reachability: null = not checked yet, true/false after a ping.
  bool? _serverOnline;
  bool _checkingServer = false;

  @override
  void initState() {
    super.initState();
    _loadDownloadDir();
    _checkServer();
  }

  Future<void> _loadDownloadDir() async {
    final label = await directoryLabel();
    if (mounted) setState(() => _downloadDir = label);
  }

  /// Whether a failed startup ping already scheduled its one-shot retry.
  bool _serverRetryScheduled = false;

  /// Pings the backend's /api/health endpoint and stores the result.
  ///
  /// A failure right after a cold launch is often just the OS bringing up
  /// networking, so schedule a single delayed retry to self-heal.
  Future<void> _checkServer() async {
    if (!usesBackend) return;
    if (_checkingServer) return;
    setState(() => _checkingServer = true);
    final ok = await musicApi.checkHealth();
    if (!mounted) return;
    setState(() {
      _serverOnline = ok;
      _checkingServer = false;
    });
    if (!ok && !_serverRetryScheduled) {
      _serverRetryScheduled = true;
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted && _serverOnline == false) {
        await _checkServer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Appearance section.
          _sectionHeader('Appearance'),
          ListTile(
            leading: Icon(
              settings.themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : settings.themeMode == ThemeMode.light
                  ? Icons.light_mode
                  : Icons.brightness_auto,
            ),
            title: const Text('Theme'),
            subtitle: Text(_themeModeLabel(settings.themeMode)),
            onTap: () => _showThemeDialog(context),
          ),

          const Divider(height: 1),

          // Audio section.
          _sectionHeader('Audio'),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Playback Speed'),
            subtitle: Text('${settings.playbackSpeed} x'),
            onTap: () => _showPlaybackSpeedDialog(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.playlist_play),
            title: const Text('Autoplay Related Music'),
            subtitle: const Text(
              'When the queue ends, keep playing similar songs',
            ),
            value: settings.autoplayRelated,
            onChanged: (value) =>
                ref.read(settingsProvider.notifier).setAutoplayRelated(value),
          ),

          const Divider(height: 1),

          // Content section.
          _sectionHeader('Content'),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Country / Region'),
            subtitle: Text(_regionLabel(settings.region)),
            onTap: () => _showRegionDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            subtitle: Text(_languageLabel(settings.language)),
            onTap: () => _showLanguageDialog(context),
          ),

          if (usesBackend) ...[
            const Divider(height: 1),
            _sectionHeader('Server'),
            ListTile(
              leading: _serverStatusIcon(),
              title: const Text('Backend Address'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(musicApi.serverUrl),
                  const SizedBox(height: 2),
                  _serverStatusText(),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Check connection',
                onPressed: _checkingServer ? null : _checkServer,
              ),
              onTap: () async {
                await _showServerDialog(context);
                if (mounted) {
                  setState(() {});
                  _checkServer();
                }
              },
            ),
          ],

          const Divider(height: 1),

          // Downloads section.
          _sectionHeader('Downloads'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Save downloads to'),
            subtitle: Text(
              _downloadDir ??
                  (kIsWeb
                      ? 'Browser default (tap to choose a folder)'
                      : 'App downloads folder'),
            ),
            onTap: !directoryPickerSupported
                ? null
                : () async {
                    final name = await pickDirectory();
                    if (name != null) {
                      setState(() => _downloadDir = name);
                    }
                  },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep, color: Colors.red),
            title: const Text('Clear All Downloads'),
            subtitle: const Text('Remove all downloaded tracks'),
            onTap: () => _confirmClearDownloads(context),
          ),

          const Divider(height: 1),

          // About section.
          _sectionHeader('About'),
          if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb)
            ListTile(
              leading: _checkingUpdate
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update),
              title: const Text('Check for updates'),
              subtitle: Text('Current version ${AppUpdater.currentVersion}'),
              onTap: _checkingUpdate ? null : _checkForUpdates,
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Musicap'),
            subtitle: Text('Version ${AppUpdater.currentVersion}'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Musicap',
                applicationVersion: AppUpdater.currentVersion,
                applicationIcon: Image.asset(
                  'assets/icon/musicap_light.png',
                  width: 48,
                  height: 48,
                ),
                children: [
                  const Text('A Flutter music player app.'),
                  const SizedBox(height: 8),
                  const Text('Made with AI assistance'),
                  const SizedBox(height: 16),
                  const Text('GitHub:'),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => launchUrl(
                      Uri.parse(
                        'https://github.com/AspiringDeveloperCapu/Musicap',
                      ),
                    ),
                    child: Text(
                      'https://github.com/AspiringDeveloperCapu/Musicap',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Author'),
            subtitle: const Text('Aaron Jacob Capulong'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Licenses'),
            subtitle: const Text('View open source licenses'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Musicap',
              applicationVersion: AppUpdater.currentVersion,
            ),
          ),
        ],
      ),
    );
  }

  /// Serverless in-app updates: GitHub hosts the release APK, the app
  /// checks its Releases API, downloads and hands it to Android's
  /// installer. Modern emulators open the sideload prompt directly.
  bool _checkingUpdate = false;

  /// Asks GitHub whether a newer Musicap release exists and reports the
  /// outcome in a dialog/snackbar.
  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);
    final release = await AppUpdater.checkLatest();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    if (release == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't check for updates - check your connection"),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!AppUpdater.isNewer(release.version, AppUpdater.currentVersion)) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("You're up to date"),
          content: Text(
            'Musicap ${AppUpdater.currentVersion} is the latest released '
            'version.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    await _showUpdateAvailableDialog(release);
  }

  /// Newer release exists: show what changed and offer the APK download.
  Future<void> _showUpdateAvailableDialog(RemoteRelease release) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${release.name} (${release.tag})'),
            if (release.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Flexible(child: SingleChildScrollView(child: Text(release.notes))),
            ],
            const SizedBox(height: 12),
            Text(
              'Installed version: ${AppUpdater.currentVersion}\n'
              "You'll download the APK and Android will ask to install it.",
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              launchUrl(Uri.parse(release.pageUrl));
            },
            child: const Text('View on GitHub'),
          ),
          if (release.hasApk())
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _downloadUpdate(release);
              },
              child: const Text('Download update'),
            ),
        ],
      ),
    );
  }

  /// Downloads the release APK (with a progress dialog) and, when it
  /// lands intact, opens Android's installer for it.
  Future<void> _downloadUpdate(RemoteRelease release) async {
    var progress = 0.0;
    void Function(void Function())? setDialogState;
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, set) {
          setDialogState = set;
          return AlertDialog(
            title: Text('Downloading ${release.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress > 0 ? progress.clamp(0.0, 1.0) : null,
                ),
                const SizedBox(height: 12),
                Text(
                  progress > 0
                      ? '${(progress * 100).toStringAsFixed(0)}%'
                      : 'Starting...'
                      '${progress >= 0.99 ? ' - launching installer...' : ''}',
                ),
              ],
            ),
          );
        },
      ),
    );
    final opened = await downloadAndPromptApk(
      release,
      onProgress: (value) {
        progress = value;
        setDialogState?.call(() {});
      },
    );
    await progressDialog;
    if (!mounted) return;

    if (opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Installer opened - Android will ask to install the update"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't download the update"),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Open GitHub',
            onPressed: () => launchUrl(Uri.parse(release.pageUrl)),
          ),
        ),
      );
    }
  }

  /// Leading icon for the Backend Address tile: colored by reachability.
  Widget _serverStatusIcon() {
    if (_checkingServer) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_serverOnline == null) {
      return const Icon(Icons.dns_outlined);
    }
    return Icon(
      Icons.dns_outlined,
      color: _serverOnline! ? Colors.green : Colors.red,
    );
  }

  /// Status line under the backend URL.
  Widget _serverStatusText() {
    final (label, color) = _checkingServer
        ? ('Checking connection…', Colors.grey)
        : _serverOnline == null
        ? ('Not checked yet', Colors.grey)
        : _serverOnline!
        ? ('Connected', Colors.green)
        : ('Cannot reach server', Colors.red);
    return Row(
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Future<void> _showServerDialog(BuildContext context) async {
    final controller = TextEditingController(text: musicApi.serverUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backend Address'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://your-backend.example.com',
            prefixIcon: Icon(Icons.dns_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      await ref.read(settingsProvider.notifier).setServerUrl(controller.text);
    }
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.system:
        return 'System default';
    }
  }

  void _showThemeDialog(BuildContext context) {
    final current = ref.read(settingsProvider).themeMode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('System default'),
              value: ThemeMode.system,
              groupValue: current,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setThemeMode(value!);
                Navigator.of(context).pop();
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: current,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setThemeMode(value!);
                Navigator.of(context).pop();
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: current,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setThemeMode(value!);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaybackSpeedDialog(BuildContext context) {
    final current = ref.read(settingsProvider).playbackSpeed;
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playback Speed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: speeds.map((speed) {
            return RadioListTile<double>(
              title: Text('$speed x'),
              value: speed,
              groupValue: current,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setPlaybackSpeed(value!);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Curated list of regions supported by YouTube Music charts.
  String _regionLabel(String code) => kRegions[code] ?? code;
  String _languageLabel(String code) => kLanguages[code] ?? code;

  void _showRegionDialog(BuildContext context) {
    final current = ref.read(settingsProvider).region;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Country / Region'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: kRegions.entries.map((e) {
              return RadioListTile<String>(
                title: Text(e.value),
                subtitle: Text(e.key),
                value: e.key,
                groupValue: current,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).setRegion(value!);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final current = ref.read(settingsProvider).language;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Language'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: kLanguages.entries.map((e) {
              return RadioListTile<String>(
                title: Text(e.value),
                subtitle: Text(e.key),
                value: e.key,
                groupValue: current,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).setLanguage(value!);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _confirmClearDownloads(BuildContext context) {
    final downloads = ref.read(downloadManagerProvider);
    final count = downloads.values
        .where((d) => d.status == DownloadStatus.downloaded)
        .length;
    if (count == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No downloads to clear')));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all downloads?'),
        content: Text(
          'This will remove $count downloaded track${count > 1 ? 's' : ''}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              final manager = ref.read(downloadManagerProvider.notifier);
              for (final entry in downloads.entries.toList()) {
                manager.deleteDownload(
                  Track(
                    id: entry.key,
                    title: entry.value.title,
                    artist: entry.value.artist,
                    audioUrl: entry.value.audioUrl,
                  ),
                );
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All downloads cleared')),
              );
            },
            child: const Text('Clear all', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// App entry point. Initializes Flutter bindings, audio service for background
/// playback, and launches the app with a Riverpod ProviderScope.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Point the API at the saved backend before providers fire their first
  // requests, so startup fetches don't race the async settings load and hit
  // the stale default host.
  await applyPersistedServerUrl();

  // Never let audio_service init brick startup — a failure here only means
  // no background/notification controls.
  try {
    musicAudioHandler = await AudioService.init(
      builder: () => MusicAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.music_player.channel.audio',
        androidNotificationChannelName: 'Musicap',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    debugPrint('AudioService.init failed: $e');
  }

  runApp(const ProviderScope(child: MusicPlayerApp()));
}
