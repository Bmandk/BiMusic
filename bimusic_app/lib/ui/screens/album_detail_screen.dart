import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/auth_service.dart';
import '../widgets/track_tile.dart';

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumId = int.parse(id);
    final albumAsync = ref.watch(albumProvider(albumId));
    final tracksAsync = ref.watch(albumTracksProvider(albumId));
    final token = ref.watch(authServiceProvider).accessToken;
    final headers = token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : <String, String>{};

    return Scaffold(
      body: albumAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 8),
              const Text('Failed to load album'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(albumProvider(albumId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (album) {
          final year =
              album.releaseDate != null && album.releaseDate!.length >= 4
                  ? album.releaseDate!.substring(0, 4)
                  : null;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(album.title),
                  background: CachedNetworkImage(
                    imageUrl: album.imageUrl,
                    httpHeaders: headers,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
                    errorWidget: (context, url, error) => ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.album, size: 64),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.artistName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (year != null)
                        Text(
                          year,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
              ),
              tracksAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (err, _) => const SliverToBoxAdapter(
                  child: Center(child: Text('Failed to load tracks')),
                ),
                data: (tracks) => SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => TrackTile(
                      track: tracks[index],
                      onTap: () {
                        ref.read(playerNotifierProvider.notifier).play(
                          tracks[index],
                          tracks,
                          artistName: album.artistName,
                          albumTitle: album.title,
                          imageUrl: album.imageUrl,
                        );
                      },
                    ),
                    childCount: tracks.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
