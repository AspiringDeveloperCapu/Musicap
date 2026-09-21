import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
      title: 'Musicap',
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
        ),
        actions: [
          // Download panel icon with active download badge.
          _DownloadIcon(),
        ],
      ),
      // Show search results grid if searching, otherwise show the dashboard.
      body: query.isNotEmpty
          ? _buildSearchResults(searchResultsAsync)
          : _buildDashboard(),
    );
  }

  /// Builds a 2-column grid of track cards from the search results.
  Widget _buildSearchResults(AsyncValue<List<Track>> resultsAsync) {
    return resultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text('Search failed: $err', style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
      data: (results) {
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
      },
    );
  }

  /// Builds the dashboard view with Recently Played, Recommended, and Playlists.
  Widget _buildDashboard() {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);
    final chartsAsync = ref.watch(chartsProvider);
    final playlists = ref.watch(playlistManagerProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recentlyPlayed.isNotEmpty)
            _buildSection(
              title: 'Recently Played',
              tracks: recentlyPlayed,
            ),
          // Trending charts section from API.
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
              title: 'Trending Now',
              tracks: charts,
            ),
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
                // Album art or placeholder.
                Container(
                  width: 140,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: track.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: track.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Center(
                            child: Icon(
                              Icons.music_note,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          errorWidget: (context, url, error) => Center(
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
                        ref.read(downloadManagerProvider.notifier).simulateDownload(track);
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
  ThemeMode _themeMode = ThemeMode.system;
  double _playbackSpeed = 1.0;

  @override
  Widget build(BuildContext context) {
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
              _themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : _themeMode == ThemeMode.light
                      ? Icons.light_mode
                      : Icons.brightness_auto,
            ),
            title: const Text('Theme'),
            subtitle: Text(_themeModeLabel()),
            onTap: () => _showThemeDialog(context),
          ),

          const Divider(height: 1),

          // Audio section.
          _sectionHeader('Audio'),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Playback Speed'),
            subtitle: Text('$_playbackSpeed x'),
            onTap: () => _showPlaybackSpeedDialog(context),
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

  String _themeModeLabel() {
    switch (_themeMode) {
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.system:
        return 'System default';
    }
  }

  void _showThemeDialog(BuildContext context) {
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
              groupValue: _themeMode,
              onChanged: (value) {
                setState(() => _themeMode = value!);
                Navigator.of(context).pop();
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: _themeMode,
              onChanged: (value) {
                setState(() => _themeMode = value!);
                Navigator.of(context).pop();
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: _themeMode,
              onChanged: (value) {
                setState(() => _themeMode = value!);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaybackSpeedDialog(BuildContext context) {
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
              groupValue: _playbackSpeed,
              onChanged: (value) {
                setState(() => _playbackSpeed = value!);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
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
