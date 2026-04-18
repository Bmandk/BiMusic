import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../models/download_task.dart';
import '../../models/track.dart';
import '../../providers/backend_url_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/url_resolver.dart';
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
    final base = ref.watch(backendUrlProvider).valueOrNull;
    if (base == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
                    imageUrl: resolveBackendUrl(base, album.imageUrl),
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
                      if (!kIsWeb)
                        tracksAsync.whenOrNull(
                          data: (tracks) => Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _DownloadAlbumButton(
                              album: album,
                              tracks: tracks,
                            ),
                          ),
                        ) ??
                            const SizedBox.shrink(),
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
                error: (err, _) => SliverToBoxAdapter(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48),
                        const SizedBox(height: 8),
                        const Text('Failed to load tracks'),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () =>
                              ref.invalidate(albumTracksProvider(albumId)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (tracks) => tracks.isEmpty
                    ? const SliverFillRemaining(
                        child: Center(
                          child: Text('No tracks yet'),
                        ),
                      )
                    : SliverList(
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

// ---------------------------------------------------------------------------
// Download Album button (mobile/desktop only)
// ---------------------------------------------------------------------------

class _DownloadAlbumButton extends ConsumerWidget {
  const _DownloadAlbumButton({required this.album, required this.tracks});

  final Album album;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadTasks = ref.watch(downloadProvider).tasks;

    // Determine per-track offline status.
    final trackIds = tracks.map((t) => t.id).toSet();
    final relevant = downloadTasks.where((d) => trackIds.contains(d.trackId)).toList();

    final completedCount =
        relevant.where((d) => d.status == DownloadStatus.completed).length;
    final downloadingCount =
        relevant.where((d) => d.status == DownloadStatus.downloading).length;
    final pendingCount =
        relevant.where((d) => d.status == DownloadStatus.pending).length;

    final allDownloaded = tracks.isNotEmpty && completedCount == tracks.length;
    final anyActive = downloadingCount > 0 || pendingCount > 0;

    if (allDownloaded) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.download_done, size: 18),
        label: const Text('Downloaded'),
        onPressed: null, // already done
      );
    }

    if (anyActive) {
      final total = tracks.length;
      final done = completedCount;
      return OutlinedButton.icon(
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            value: total > 0 ? done / total : null,
            strokeWidth: 2,
          ),
        ),
        label: Text('Downloading… ($done / $total)'),
        onPressed: null,
      );
    }

    return FilledButton.icon(
      icon: const Icon(Icons.download_outlined, size: 18),
      label: const Text('Download Album'),
      onPressed: () => ref.read(downloadProvider.notifier).requestAlbumDownload(
        tracks,
        albumId: album.id,
        artistId: album.artistId,
        albumTitle: album.title,
        artistName: album.artistName,
      ),
    );
  }
}
