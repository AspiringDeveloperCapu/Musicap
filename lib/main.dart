import 'package:flutter/material.dart';
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
import 'providers/music_provider.dart';
import 'providers/playlist_manager.dart';
import 'providers/download_manager.dart';
import 'providers/settings_provider.dart';
import 'models/genre.dart';
import 'models/track.dart';
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
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      home: const MainScreen(),
      routes: {
        '/player': (context) => const PlayerPage(),
        '/playlist': (context) => const PlaylistPage(),
      },
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioPlayerProvider);

    // Apply playback speed whenever it changes (including initial load).
    ref.listen(settingsProvider.select((s) => s.playbackSpeed),
        (previous, next) {
      ref.read(audioPlayerProvider.notifier).setSpeed(next);
    });

    // Show error snackbar if the player encounters an error, then clear it.
    if (state.error != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.error!),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(audioPlayerProvider.notifier).clearError();
      });
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomePage(),
          GenresPage(),
          PlaylistPage(),
          DownloadsPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          // Bottom navigation bar for switching between main sections.
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Genres'),
              BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: 'Library'),
              BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Downloads'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
            ],
            selectedItemColor: Colors.blueAccent,
            unselectedItemColor: Colors.grey,
          ),
        ],
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

  /// Syncs the search text field input to the Riverpod search query provider.
  void _onSearchChanged() {
    ref.read(searchQueryProvider.notifier).state = _searchController.text;
  }

  /// Runs a search: fills the field, updates the query, saves to history,
  /// and hides the keyboard.
  void _runSearch(String query) {
    _searchController.text = query;
    ref.read(searchQueryProvider.notifier).state = query;
    ref.read(recentSearchesProvider.notifier).addSearch(query);
    _searchFocusNode.unfocus();
  }

  /// Plays a track within the context of a given queue (section or playlist).
  void _playTrack(Track track, {required List<Track> fromQueue}) async {
    final controller = ref.read(audioPlayerProvider.notifier);
    final index = fromQueue.indexOf(track);
    await controller.playTrack(track, fromQueue: fromQueue, startIndex: index >= 0 ? index : 0);
    ref.read(recentlyPlayedProvider.notifier).addTrack(track);
  }

  /// Shows a dialog listing all playlists, allowing the user to add a track.
  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref, Track track) {
    final playlists = ref.read(playlistManagerProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add "${track.title}" to playlist'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ListTile(
                leading: Icon(
                  Icons.queue_music,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                title: Text(playlist.name),
                subtitle: Text('${playlist.tracks.length} tracks'),
                onTap: () {
                  final added = ref.read(playlistManagerProvider.notifier).addTrackToPlaylist(
                    playlist.id,
                    track,
                  );
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        added
                            ? 'Added "${track.title}" to "${playlist.name}"'
                            : '"${track.title}" is already in "${playlist.name}"',
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteDownload(BuildContext context, WidgetRef ref, Track track) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete download?'),
        content: Text('Delete "${track.title}" from downloads? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(downloadManagerProvider.notifier).deleteDownload(track);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Deleted "${track.title}"'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
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
          decoration: InputDecoration(
            hintText: 'Search tracks, artists...',
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                    },
                  )
                : null,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ref.read(recentSearchesProvider.notifier).addSearch(value);
              _searchFocusNode.unfocus();
            }
          },
        ),
        actions: [
          // Download panel icon with active download badge.
          _DownloadIcon(),
        ],
      ),
      // Search results while typing, recent searches while focused on an
      // empty field, otherwise the dashboard.
      body: _buildBody(searchResultsAsync, query),
    );
  }

  Widget _buildBody(AsyncValue<List<Track>> resultsAsync, String query) {
    if (query.isNotEmpty) {
      return _buildSearchResults(resultsAsync, query);
    }
    // Recent searches replace the dashboard while the field is focused
    // (falls back to the dashboard when history is empty).
    if (_searchFocusNode.hasFocus) {
      return _buildRecentSearches();
    }
    return _buildDashboard();
  }

  /// Search view: list rows with art/title/artist/duration, suggestions
  /// while results load, and distinct loading/empty/error states.
  Widget _buildSearchResults(AsyncValue<List<Track>> resultsAsync, String query) {
    return resultsAsync.when(
      loading: () => _buildSuggestionList(),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text('Search failed: $err',
                style: const TextStyle(color: Colors.grey)),
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
                      const Icon(Icons.search_off,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(
                        'No results for "$query"',
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey),
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
            return _buildResultTile(track, results);
          },
        );
      },
    );
  }

  /// A single search result row: album art, title, artist, duration, menu.
  Widget _buildResultTile(Track track, List<Track> fromQueue) {
    final dlState = ref.watch(downloadManagerProvider)[track.id];
    final durationLabel = track.duration != null
        ? '${track.duration!.inMinutes}:${(track.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
        : null;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: track.imageUrl != null
              ? Image.network(
                  track.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, url, error) =>
                      const Icon(Icons.music_note),
                )
              : const Icon(Icons.music_note),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (durationLabel != null)
            Text(
              durationLabel,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          if (dlState?.status == DownloadStatus.downloaded)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.download_done, size: 16, color: Colors.green),
            ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            onSelected: (value) {
              if (value == 'queue') {
                ref.read(audioPlayerProvider.notifier).addToQueue(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added "${track.title}" to queue'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              } else if (value == 'download') {
                ref.read(downloadManagerProvider.notifier).startDownload(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Downloading "${track.title}"'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              } else if (value == 'playlist') {
                _showAddToPlaylistDialog(context, ref, track);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'queue', child: Text('Add to queue')),
              PopupMenuItem(value: 'download', child: Text('Download')),
              PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
            ],
          ),
        ],
      ),
      onTap: () => _playTrack(track, fromQueue: fromQueue),
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

  /// History list shown when the search field is focused but empty.
  Widget _buildRecentSearches() {
    final recents = ref.watch(recentSearchesProvider);
    if (recents.isEmpty) return _buildDashboard();

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent searches',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        for (final query in recents)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(query),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () =>
                  ref.read(recentSearchesProvider.notifier).removeSearch(query),
            ),
            onTap: () => _runSearch(query),
          ),
      ],
    );
  }

  /// Builds the dashboard view with quick genre picks, recently played,
  /// recommendations, region-based charts, and playlists.
  Widget _buildDashboard() {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);
    final chartsAsync = ref.watch(chartsProvider);
    final recommendationsAsync = ref.watch(recommendationsProvider);
    final genresAsync = ref.watch(genresProvider);
    final playlists = ref.watch(playlistManagerProvider);
    final region = ref.watch(settingsProvider.select((s) => s.region));
    final regionName = kRegions[region] ?? region;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Genre quick-picks — tap to open that genre's playlists.
          _buildGenreChips(genresAsync),
          if (recentlyPlayed.isNotEmpty)
            _buildSection(
              title: 'Recently Played',
              tracks: recentlyPlayed,
            ),
          // Personalized recommendations from the radio/watch playlist.
          recommendationsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            // Recommendations are optional — hide the section on failure.
            error: (_, __) => const SizedBox.shrink(),
            data: (recs) => recs.isEmpty
                ? const SizedBox.shrink()
                : _buildSection(
                    title: 'Made For You',
                    tracks: recs,
                  ),
          ),
          // Trending charts for the selected region.
          chartsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load charts: $err', style: const TextStyle(color: Colors.grey)),
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
        return SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return _buildTrackCard(track, fromQueue: tracks, width: 140);
            },
          ),
        ),
      ],
    );
  }

  /// Builds a single track card with album art placeholder, title, artist,
  /// a download status indicator, and a 3-dot menu for actions.
  Widget _buildTrackCard(Track track, {required List<Track> fromQueue, double? width}) {
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
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
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
                  child: PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (value) {
                      if (value == 'addQueue') {
                        ref.read(audioPlayerProvider.notifier).addToQueue(track);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added "${track.title}" to queue'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      } else if (value == 'addToPlaylist') {
                        _showAddToPlaylistDialog(context, ref, track);
                      } else if (value == 'download') {
                        ref.read(downloadManagerProvider.notifier).startDownload(track);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Downloading "${track.title}"'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      } else if (value == 'deleteDownload') {
                        _confirmDeleteDownload(context, ref, track);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'addQueue',
                        child: Text('Add to queue'),
                      ),
                      const PopupMenuItem(
                        value: 'addToPlaylist',
                        child: Text('Add to playlist'),
                      ),
                      if (status == DownloadStatus.downloaded)
                        const PopupMenuItem(
                          value: 'deleteDownload',
                          child: Text('Delete download'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'download',
                          child: Text('Download'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Playlists',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {});
                },
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _buildPlaylistCard(playlist);
            },
          ),
        ),
      ],
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
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (value) {
                      if (value == 'addAllQueue') {
                        for (final track in playlist.tracks) {
                          ref.read(audioPlayerProvider.notifier).addToQueue(track);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added ${playlist.tracks.length} tracks to queue'),
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
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
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
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
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

          const Divider(height: 1),

          // Downloads section.
          _sectionHeader('Downloads'),
          ListTile(
            leading: const Icon(Icons.delete_sweep, color: Colors.red),
            title: const Text('Clear All Downloads'),
            subtitle: const Text('Remove all downloaded tracks'),
            onTap: () => _confirmClearDownloads(context),
          ),

          const Divider(height: 1),

          // About section.
          _sectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Musicap'),
            subtitle: const Text('Version 1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Musicap',
                applicationVersion: '1.0.0',
                children: [
                  const Text('A Flutter music player app.'),
                  const SizedBox(height: 8),
                  const Text('Made with AI assistance'),
                  const SizedBox(height: 16),
                  const Text('GitHub:'),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => launchUrl(
                      Uri.parse('https://github.com/AspiringDeveloperCapu/Musicap'),
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
              applicationVersion: '1.0.0',
            ),
          ),
        ],
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No downloads to clear')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all downloads?'),
        content: Text('This will remove $count downloaded track${count > 1 ? 's' : ''}. This cannot be undone.'),
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

  await AudioService.init(
    builder: () => MusicAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_player.channel.audio',
      androidNotificationChannelName: 'Musicap',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    const ProviderScope(
      child: MusicPlayerApp(),
    ),
  );
}
