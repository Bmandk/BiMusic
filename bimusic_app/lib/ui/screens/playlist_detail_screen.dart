import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/track.dart';
import '../../providers/player_provider.dart';
import '../../providers/playlist_provider.dart';
import '../widgets/track_tile.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(playlistDetailProvider(id));

    return Scaffold(
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 8),
              const Text('Failed to load playlist'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(playlistDetailProvider(id)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (detail) => CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Text(detail.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Rename',
                  onPressed: () =>
                      _showRenameDialog(context, ref, detail.name),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete playlist',
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            ),
            if (detail.tracks.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.music_off, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'No tracks yet — long-press a track to add it.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            _playAll(context, ref, detail.tracks, detail.name),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play All'),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${detail.tracks.length} track${detail.tracks.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: detail.tracks.length,
                  onReorder: (oldIndex, newIndex) =>
                      _onReorder(ref, detail.tracks, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final track = detail.tracks[index];
                    return KeyedSubtree(
                      key: ValueKey(track.id),
                      child: TrackTile(
                        track: track,
                        onTap: () => _playFrom(
                          context,
                          ref,
                          track,
                          detail.tracks,
                          detail.name,
                        ),
                        onRemoveFromPlaylist: () => ref
                            .read(playlistProvider.notifier)
                            .removeTrack(id, track.id),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _playAll(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
    String playlistName,
  ) {
    if (tracks.isEmpty) return;
    ref.read(playerNotifierProvider.notifier).play(
      tracks.first,
      tracks,
      artistName: 'Playlist',
      albumTitle: playlistName,
      imageUrl: '',
    );
  }

  void _playFrom(
    BuildContext context,
    WidgetRef ref,
    Track track,
    List<Track> tracks,
    String playlistName,
  ) {
    ref.read(playerNotifierProvider.notifier).play(
      track,
      tracks,
      artistName: 'Playlist',
      albumTitle: playlistName,
      imageUrl: '',
    );
  }

  void _onReorder(
    WidgetRef ref,
    List<Track> tracks,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<Track>.from(tracks)
      ..removeAt(oldIndex)
      ..insert(newIndex, tracks[oldIndex]);
    final trackIds = reordered.map((t) => t.id).toList();
    ref.read(playlistProvider.notifier).reorderTracks(id, trackIds);
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenamePlaylistDialog(initialName: currentName),
    );
    if (newName != null && newName.isNotEmpty && context.mounted) {
      await ref.read(playlistProvider.notifier).updatePlaylist(id, newName);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: const Text(
          'Are you sure you want to delete this playlist? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(playlistProvider.notifier).deletePlaylist(id);
      if (context.mounted) {
        context.go('/playlists');
      }
    }
  }
}

class _RenamePlaylistDialog extends StatefulWidget {
  const _RenamePlaylistDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<_RenamePlaylistDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
