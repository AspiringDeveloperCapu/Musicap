import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:music_player/features/player/player_controller.dart';

class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioPlayer = ref.watch(audioPlayerProvider.notifier);
    final textController = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: textController,
              decoration: InputDecoration(
                hintText: 'Enter track name or URL',
                labelText: 'Search',
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    final text = textController.text.trim();
                    if (text.isNotEmpty) {
                      _playUrl(context, text, ref, audioPlayer);
                    }
                  },
                ),
              ),
              onSubmitted: (String value) {
                if (value.isNotEmpty) {
                  _playUrl(context, value, ref, audioPlayer);
                }
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Enter a music URL or track name:',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: const Center(
                child: Text(
                  'Paste a music URL or type a track name',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _playUrl(
    BuildContext context,
    String url,
    WidgetRef ref,
    AudioPlayerController audioPlayer,
  ) async {
    try {
      await audioPlayer.play();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playing: $url'),
          duration: const Duration(seconds: 2),
        ),
      );
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not play: $url\nError: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}