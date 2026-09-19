import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';

import 'features/player/player_controller.dart';
import 'features/player/player_page.dart';
import 'features/player/mini_player.dart';
import 'features/player/download_bar.dart';
import 'features/playlist/playlist_page.dart';
import 'features/playlist/playlist_detail_page.dart';
import 'features/downloads/downloads_page.dart';
import 'providers/music_provider.dart';
import 'providers/playlist_manager.dart';
import 'providers/download_manager.dart';
import 'models/track.dart';
import 'audio_handler.dart';

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Music Player',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
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
          PlaylistPage(),
          DownloadsPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          // Bottom navigation bar for switching between Home, Library, and Settings.
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
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

  /// Plays a track within the context of a given queue (section or playlist).
  void _playTrack(Track track, {required List<Track> fromQueue}) async {
    final controller = ref.read(audioPlayerProvider.notifier);
    final index = fromQueue.indexOf(track);
    await controller.playTrack(track, fromQueue: fromQueue, startIndex: index >= 0 ? index : 0);
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

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(searchResultsProvider);
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
        ),
        actions: [
          // Download panel icon with active download badge.
          _DownloadIcon(),
        ],
      ),
      // Show search results grid if searching, otherwise show the dashboard.
      body: query.isNotEmpty
          ? _buildSearchResults(searchResults)
          : _buildDashboard(),
    );
  }

  /// Builds a 2-column grid of track cards from the search results.
  Widget _buildSearchResults(List<Track> results) {
    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No results found',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final track = results[index];
        return _buildTrackCard(track, fromQueue: results);
      },
    );
  }

  /// Builds the dashboard view with Recently Played, Recommended, and Playlists.
  Widget _buildDashboard() {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final playlists = ref.watch(playlistManagerProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            title: 'Recently Played',
            tracks: recentlyPlayed,
          ),
          _buildSection(
            title: 'Recommended',
            tracks: recommendations,
          ),
          _buildPlaylistsSection(playlists),
          const SizedBox(height: 24),
        ],
      ),
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
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return _buildTrackCard(track, fromQueue: tracks);
            },
          ),
        ),
      ],
    );
  }

  /// Builds a single track card with album art placeholder, title, artist,
  /// a download status indicator, and a 3-dot menu for actions.
  Widget _buildTrackCard(Track track, {required List<Track> fromQueue}) {
    final dlState = ref.watch(downloadManagerProvider)[track.id];
    final status = dlState?.status;

    return HoverScale(
      onTap: () => _playTrack(track, fromQueue: fromQueue),
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // Album art placeholder.
                Container(
                  width: 140,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
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
                        ref.read(downloadManagerProvider.notifier).simulateDownload(track);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Downloading "${track.title}"'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
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
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Audio',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('Music Player v1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Music Player',
                applicationVersion: '1.0.0',
                children: [
                  const Text('A Flutter music player app.'),
                  const SizedBox(height: 8),
                  const Text('Made with AI assistance'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Global audio handler instance for background audio playback via audio_service.
late MusicAudioHandler _audioHandler;

/// App entry point. Initializes Flutter bindings, audio service for background
/// playback, and launches the app with a Riverpod ProviderScope.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _audioHandler = await AudioService.init(
    builder: () => MusicAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_player.channel.audio',
      androidNotificationChannelName: 'Music Player',
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
