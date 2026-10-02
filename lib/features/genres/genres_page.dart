import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_player/features/genres/genre_detail_page.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/genre.dart';
import 'package:music_player/providers/music_provider.dart';
import 'package:music_player/widgets/mood_palette.dart';

/// Genres tab — browses YouTube Music's Genres & Moods sections.
///
/// Each genre/mood is a gradient tile whose colors derive from its title
/// (see [MoodPalette]).
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
        data: (sections) {
          if (sections.isEmpty || sections.every((s) => s.items.isEmpty)) {
            return const Center(
              child: Text(
                'No genres found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          return ListView(
            children: [
              for (final section in sections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final columns =
                          width >= 900 ? 4 : (width >= 600 ? 3 : 2);
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: 1.7,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: section.items.length,
                        itemBuilder: (context, index) => _GenreTile(
                          item: section.items[index],
                          onTap: () =>
                              _openGenre(context, section.items[index]),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
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

/// One gradient genre card on the landing grid.
class _GenreTile extends StatelessWidget {
  final GenreItem item;
  final VoidCallback onTap;

  const _GenreTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = MoodPalette.primary(item.title);
    return HoverScale(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: MoodPalette.gradient(item.title),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: primary.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Decorative note tucked into the top-right corner.
            Positioned(
              right: -8,
              top: -8,
              child: Transform.rotate(
                angle: -0.35,
                child: Icon(
                  Icons.music_note,
                  size: 72,
                  color: Colors.white.withOpacity(0.18),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 10,
              bottom: 10,
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(blurRadius: 6, color: Colors.black38),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
