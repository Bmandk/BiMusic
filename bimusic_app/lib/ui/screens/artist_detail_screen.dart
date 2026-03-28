import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/library_provider.dart';
import '../../services/auth_service.dart';
import '../widgets/album_card.dart';

class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistId = int.parse(id);
    final artistAsync = ref.watch(artistProvider(artistId));
    final albumsAsync = ref.watch(artistAlbumsProvider(artistId));
    final token = ref.watch(authServiceProvider).accessToken;
    final headers = token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : <String, String>{};

    return Scaffold(
      body: artistAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 8),
              const Text('Failed to load artist'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(artistProvider(artistId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (artist) => CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(artist.name),
                background: CachedNetworkImage(
                  imageUrl: artist.imageUrl,
                  httpHeaders: headers,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => ColoredBox(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, url, error) => ColoredBox(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.person, size: 64),
                  ),
                ),
              ),
            ),
            if (artist.overview != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    artist.overview!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Albums',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            albumsAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (err, _) => const SliverToBoxAdapter(
                child: Center(child: Text('Failed to load albums')),
              ),
              data: (albums) => SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final album = albums[index];
                      return AlbumCard(
                        album: album,
                        onTap: () =>
                            context.go('/library/album/${album.id}'),
                      );
                    },
                    childCount: albums.length,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
