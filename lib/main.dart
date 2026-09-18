import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';

import 'features/player/player_controller.dart';
import 'features/player/player_page.dart';
import 'features/playlist/playlist_page.dart';
import 'providers/music_provider.dart';
import 'models/track.dart';
import 'audio_handler.dart';

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

class MusicPlayerApp extends ConsumerWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
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

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;
  bool _isDraggingMini = false;
  double _dragMiniValue = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioPlayerProvider);

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

    final miniPosition = state.totalDuration != null &&
            state.totalDuration!.inMilliseconds > 0 &&
            state.currentPosition != null
        ? (_isDraggingMini
            ? _dragMiniValue
            : (state.currentPosition!.inMilliseconds / state.totalDuration!.inMilliseconds).clamp(0.0, 1.0))
        : 0.0;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomePage(),
          PlaylistPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.currentTitle.isNotEmpty)
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Theme.of(context).colorScheme.primary,
                      inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Slider(
                      value: miniPosition,
                      onChangeStart: (v) {
                        setState(() {
                          _isDraggingMini = true;
                          _dragMiniValue = v;
                        });
                      },
                      onChanged: (v) {
                        setState(() {
                          _dragMiniValue = v.clamp(0.0, 1.0);
                        });
                      },
                      onChangeEnd: (v) {
                        setState(() {
                          _isDraggingMini = false;
                        });
                        final clamped = v.clamp(0.0, 1.0);
                        final pos = Duration(
                          milliseconds: (clamped * state.totalDuration!.inMilliseconds).round(),
                        );
                        ref.read(audioPlayerProvider.notifier).seek(pos);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 4, bottom: 8),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/player'),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.music_note,
                              size: 22,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(context, '/player'),
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  state.currentTitle,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  state.currentArtist,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            state.hasPrevious ? Icons.skip_previous : Icons.skip_previous,
                            size: 24,
                          ),
                          onPressed: state.hasPrevious
                              ? () => ref.read(audioPlayerProvider.notifier).seekToPrevious()
                              : null,
                        ),
                        IconButton(
                          icon: Icon(
                            state.isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 28,
                          ),
                          onPressed: () {
                            ref.read(audioPlayerProvider.notifier).playOrPause();
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.skip_next,
                            size: 24,
                          ),
                          onPressed: state.hasNext
                              ? () => ref.read(audioPlayerProvider.notifier).seekToNext()
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: 'Queue'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        ],
      ),
    );
  }
}

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

  void _onSearchChanged() {
    ref.read(searchQueryProvider.notifier).state = _searchController.text;
  }

  void _playTrack(Track track, {required List<Track> fromQueue}) async {
    final controller = ref.read(audioPlayerProvider.notifier);
    final index = fromQueue.indexOf(track);
    await controller.playTrack(track, fromQueue: fromQueue, startIndex: index >= 0 ? index : 0);
    if (mounted) {
      Navigator.pushNamed(context, '/player');
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
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
      ),
      body: query.isNotEmpty
          ? _buildSearchResults(searchResults)
          : _buildDashboard(),
    );
  }

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

  Widget _buildDashboard() {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final playlists = ref.watch(playlistsProvider);

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

  Widget _buildTrackCard(Track track, {required List<Track> fromQueue}) {
    return HoverScale(
      onTap: () => _playTrack(track, fromQueue: fromQueue),
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

  Widget _buildPlaylistCard(Playlist playlist) {
    return HoverScale(
      onTap: () {
        if (playlist.tracks.isNotEmpty) {
          _playTrack(playlist.tracks.first, fromQueue: playlist.tracks);
        }
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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

late MusicAudioHandler _audioHandler;

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
