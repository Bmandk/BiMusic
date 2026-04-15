import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../widgets/artist_card.dart';
import '../widgets/album_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final artistsAsync = ref.watch(libraryProvider);

    final username = authState is AuthStateAuthenticated
        ? authState.tokens.user.username
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Text(
                username != null ? 'Welcome back, $username!' : 'Welcome back!',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),

            // Quick-nav shortcuts
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Browse',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Row(
                children: [
                  Expanded(
                    child: _QuickNavCard(
                      icon: Icons.library_music,
                      label: 'Library',
                      onTap: () => context.go('/library'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickNavCard(
                      icon: Icons.search,
                      label: 'Search',
                      onTap: () => context.go('/search'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickNavCard(
                      icon: Icons.queue_music,
                      label: 'Playlists',
                      onTap: () => context.go('/playlists'),
                    ),
                  ),
                ],
              ),
            ),

            // Artists section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Artists',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => context.go('/library'),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),

            artistsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Failed to load artists'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(libraryProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (artists) {
                if (artists.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Text('No artists in your library yet.'),
                  );
                }
                final displayArtists = artists.take(6).toList();
                return SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: displayArtists.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final artist = displayArtists[index];
                      return SizedBox(
                        width: 110,
                        child: ArtistCard(
                          artist: artist,
                          onTap: () =>
                              context.go('/library/artist/${artist.id}'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Albums section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Recent Albums',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),

            artistsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (artists) {
                // Collect albums by fetching from the first few artists
                if (artists.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Text('No albums in your library yet.'),
                  );
                }
                return _RecentAlbumsRow(
                  artistIds: artists.take(4).map((a) => a.id).toList(),
                );
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick-nav card widget
// ---------------------------------------------------------------------------

class _QuickNavCard extends StatelessWidget {
  const _QuickNavCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colorScheme.onSecondaryContainer, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent albums row — fetches albums for the first few artists
// ---------------------------------------------------------------------------

class _RecentAlbumsRow extends ConsumerWidget {
  const _RecentAlbumsRow({required this.artistIds});

  final List<int> artistIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Collect all albums from the watched artists.
    final allAlbums = <dynamic>[];
    for (final id in artistIds) {
      final albumsAsync = ref.watch(artistAlbumsProvider(id));
      albumsAsync.whenData((albums) => allAlbums.addAll(albums));
    }

    // Check if still loading any artist's albums.
    final isLoading = artistIds.any(
      (id) => ref.watch(artistAlbumsProvider(id)).isLoading,
    );

    if (isLoading && allAlbums.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (allAlbums.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Text('No albums available.'),
      );
    }

    final displayAlbums = allAlbums.take(8).toList();

    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: displayAlbums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final album = displayAlbums[index];
          return SizedBox(
            width: 120,
            child: AlbumCard(
              album: album,
              onTap: () => context.go('/library/album/${album.id}'),
            ),
          );
        },
      ),
    );
  }
}
