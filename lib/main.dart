import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/player/player_controller.dart';
import 'features/player/player_page.dart';
import 'features/search/search_page.dart';  // NEW

final audioPlayerProvider = StateNotifierProvider<AudioPlayerController, AudioPlayerState>((ref) {
  return AudioPlayerController();
});

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
      home: const HomePage(),
      routes: {
        '/player': (context) => PlayerPage(),
        '/search': (context) => const SearchPage(),  // NEW
      },
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.music_note),
            tooltip: 'Open search',
            onPressed: () {
              Navigator.pushNamed(context, '/search');
            },
          ),
        ],
      ),
      body: const Center(
        child: Text(
          'Home Page - Add your playlist grid here',
          style: TextStyle(fontSize: 18),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  BottomNavigationBar _buildBottomNav(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0,
      onTap: (index) {},
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: 'Queue'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ],
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ProviderScope(
      overrides: [
        audioPlayerProvider.overrideWith((ref) => AudioPlayerController()),
      ],
      child: const MusicPlayerApp(),
    ),
  );
}