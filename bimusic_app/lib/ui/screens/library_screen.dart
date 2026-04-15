import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/library_provider.dart';
import '../layouts/breakpoints.dart';
import '../widgets/artist_card.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsAsync = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: artistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 8),
              const Text('Failed to load library'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(libraryProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (artists) => RefreshIndicator(
          onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
          child: artists.isEmpty
              ? const Center(child: Text('No artists in library'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = width >= Breakpoints.desktop
                        ? 5
                        : width >= Breakpoints.tablet
                            ? 4
                            : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: artists.length,
                      itemBuilder: (context, index) {
                        final artist = artists[index];
                        return ArtistCard(
                          artist: artist,
                          onTap: () =>
                              context.go('/library/artist/${artist.id}'),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}
