import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/features/genres/genre_detail_page.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/genre.dart';
import 'package:music_player/providers/music_provider.dart';

/// Genres tab — browses YouTube Music's Genres & Moods sections.
class GenresPage extends ConsumerWidget {
  const GenresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(genresProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Genres'),
      ),
      body: genresAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.explore_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Could not load genres',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(genresProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (sections) => ListView(
          children: [
            for (final section in sections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in section.items)
                      HoverScale(
                        onTap: () => _openGenre(context, item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.title,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _openGenre(BuildContext context, GenreItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GenreDetailPage(item: item),
      ),
    );
  }
}
