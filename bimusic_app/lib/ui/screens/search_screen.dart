import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/lidarr_search_results.dart';
import '../../models/music_request.dart';
import '../../providers/requests_provider.dart';
import '../../providers/search_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchProvider.notifier).setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: TextField(
          controller: _searchController,
          autofocus: false,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search artists, albums...',
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchState.query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearSearch,
                  )
                : null,
          ),
          onChanged: (q) => ref.read(searchProvider.notifier).setQuery(q),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Library'),
            Tab(text: 'Request Music'),
            Tab(text: 'My Requests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _LibraryTab(),
          _LidarrTab(),
          _RequestsTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library tab
// ---------------------------------------------------------------------------

class _LibraryTab extends ConsumerWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);

    if (state.query.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('Search your library', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (state.isSearchingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.libraryError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            const Text('Search failed'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () =>
                  ref.read(searchProvider.notifier).setQuery(state.query),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final results = state.libraryResults;
    if (results == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final artists = results.artists;
    final albums = results.albums;

    if (artists.isEmpty && albums.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'No results for "${state.query}"',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (artists.isNotEmpty) ...[
          const _SectionHeader(title: 'Artists'),
          ...artists.map(
            (a) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(a.name),
              subtitle: Text('${a.albumCount} album${a.albumCount == 1 ? '' : 's'}'),
              onTap: () => context.go('/library/artist/${a.id}'),
            ),
          ),
        ],
        if (albums.isNotEmpty) ...[
          const _SectionHeader(title: 'Albums'),
          ...albums.map(
            (a) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.album)),
              title: Text(a.title),
              subtitle: Text(a.artistName),
              trailing: a.releaseDate != null && a.releaseDate!.length >= 4
                  ? Text(a.releaseDate!.substring(0, 4))
                  : null,
              onTap: () => context.go('/library/album/${a.id}'),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Lidarr tab
// ---------------------------------------------------------------------------

class _LidarrTab extends ConsumerWidget {
  const _LidarrTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);

    if (state.query.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Type a query then tap "Search Lidarr"',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Not yet searched — show prompt button
    if (state.lidarrResults == null && !state.isSearchingLidarr) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(searchProvider.notifier).searchLidarr(),
              icon: const Icon(Icons.search),
              label: Text('Search Lidarr for "${state.query}"'),
            ),
          ],
        ),
      );
    }

    if (state.isSearchingLidarr) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.lidarrError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            const Text('Lidarr search failed'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () =>
                  ref.read(searchProvider.notifier).searchLidarr(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final results = state.lidarrResults!;
    if (results.artists.isEmpty && results.albums.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'No Lidarr results for "${state.query}"',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.cloud, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                'Results from Lidarr',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
        if (results.artists.isNotEmpty) ...[
          const _SectionHeader(title: 'Artists'),
          ...results.artists.map(
            (a) => _LidarrArtistTile(artist: a),
          ),
        ],
        if (results.albums.isNotEmpty) ...[
          const _SectionHeader(title: 'Albums'),
          ...results.albums.map(
            (a) => _LidarrAlbumTile(album: a),
          ),
        ],
      ],
    );
  }
}

class _LidarrArtistTile extends ConsumerWidget {
  const _LidarrArtistTile({required this.artist});

  final LidarrArtistResult artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = 'artist:${artist.id}';
    final status = ref.watch(
      searchProvider.select((s) => s.requestStatuses[key] ?? RequestSubmitStatus.idle),
    );

    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(artist.artistName),
      subtitle: artist.overview != null
          ? Text(
              artist.overview!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: _RequestButton(
        status: status,
        onRequest: () => _showArtistRequestSheet(context, ref, artist),
      ),
    );
  }

  Future<void> _showArtistRequestSheet(
    BuildContext context,
    WidgetRef ref,
    LidarrArtistResult artist,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _RequestConfirmSheet(
        title: artist.artistName,
        subtitle: 'Lidarr will search for and download all albums by this artist.',
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.read(searchProvider.notifier).requestArtist(artist);
    }
  }
}

class _LidarrAlbumTile extends ConsumerWidget {
  const _LidarrAlbumTile({required this.album});

  final LidarrAlbumResult album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = 'album:${album.id}';
    final status = ref.watch(
      searchProvider.select((s) => s.requestStatuses[key] ?? RequestSubmitStatus.idle),
    );

    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.album)),
      title: Text(album.title),
      subtitle: Text(
        album.releaseYear != null
            ? '${album.artist.artistName} · ${album.releaseYear}'
            : album.artist.artistName,
      ),
      trailing: _RequestButton(
        status: status,
        onRequest: () => _showAlbumRequestSheet(context, ref, album),
      ),
    );
  }

  Future<void> _showAlbumRequestSheet(
    BuildContext context,
    WidgetRef ref,
    LidarrAlbumResult album,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _RequestConfirmSheet(
        title: album.title,
        subtitle:
            'By ${album.artist.artistName}. Lidarr will search for and download this album.',
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.read(searchProvider.notifier).requestAlbum(album);
    }
  }
}

class _RequestButton extends StatelessWidget {
  const _RequestButton({
    required this.status,
    required this.onRequest,
  });

  final RequestSubmitStatus status;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      RequestSubmitStatus.idle => TextButton(
          onPressed: onRequest,
          child: const Text('Request'),
        ),
      RequestSubmitStatus.submitting => const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      RequestSubmitStatus.submitted => const Tooltip(
          message: 'Requested',
          child: Icon(Icons.check_circle, color: Colors.green),
        ),
      RequestSubmitStatus.error => Tooltip(
          message: 'Request failed — tap to retry',
          child: IconButton(
            icon: const Icon(Icons.error_outline, color: Colors.red),
            onPressed: onRequest,
          ),
        ),
    };
  }
}

class _RequestConfirmSheet extends StatelessWidget {
  const _RequestConfirmSheet({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request "$title"?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(subtitle),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Request'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My Requests tab
// ---------------------------------------------------------------------------

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(requestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            const Text('Failed to load requests'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () =>
                  ref.read(requestsProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No pending requests',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.read(requestsProvider.notifier).refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: requests.length,
            itemBuilder: (context, index) =>
                _RequestTile(request: requests[index]),
          ),
        );
      },
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});

  final MusicRequest request;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (statusLabel, statusColor) = switch (request.status) {
      'available' => ('Available', Colors.green),
      'downloading' => ('Downloading', colorScheme.primary),
      _ => ('Pending', colorScheme.onSurfaceVariant),
    };

    final icon = request.type == 'artist' ? Icons.person : Icons.album;
    final date = _formatDate(request.requestedAt);

    return ListTile(
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(
        '${request.type[0].toUpperCase()}${request.type.substring(1)} #${request.lidarrId}',
      ),
      subtitle: Text('Requested $date'),
      trailing: _StatusBadge(label: statusLabel, color: statusColor),
    );
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
