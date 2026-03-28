import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/playlist_provider.dart';

class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.onRemoveFromPlaylist,
  });

  final Track track;
  final VoidCallback onTap;

  /// When non-null, "Remove from Playlist" is shown in the long-press menu.
  final VoidCallback? onRemoveFromPlaylist;

  String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: SizedBox(
        width: 32,
        child: Center(
          child: Text(
            track.trackNumber,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.hasFile)
            Icon(
              Icons.download_done,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          const SizedBox(width: 4),
          Text(
            _formatDuration(track.duration),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: onTap,
      onLongPress: () => _showContextSheet(context),
    );
  }

  void _showContextSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _TrackContextSheet(
        track: track,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Context sheet — transitions between main menu and playlist picker.
// ---------------------------------------------------------------------------

class _TrackContextSheet extends ConsumerStatefulWidget {
  const _TrackContextSheet({
    required this.track,
    this.onRemoveFromPlaylist,
  });

  final Track track;
  final VoidCallback? onRemoveFromPlaylist;

  @override
  ConsumerState<_TrackContextSheet> createState() => _TrackContextSheetState();
}

class _TrackContextSheetState extends ConsumerState<_TrackContextSheet> {
  bool _pickingPlaylist = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _pickingPlaylist ? _buildPicker(context) : _buildMenu(context),
    );
  }

  Widget _buildMenu(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.track.title,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.playlist_add),
          title: const Text('Add to Playlist'),
          onTap: () => setState(() => _pickingPlaylist = true),
        ),
        if (widget.onRemoveFromPlaylist != null)
          ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: const Text('Remove from Playlist'),
            onTap: () {
              Navigator.of(context).pop();
              widget.onRemoveFromPlaylist!();
            },
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPicker(BuildContext context) {
    final playlistsAsync = ref.watch(playlistProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _pickingPlaylist = false),
              ),
              Text(
                'Add to Playlist',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        playlistsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => const ListTile(
            title: Text('Could not load playlists'),
          ),
          data: (playlists) {
            if (playlists.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No playlists yet — create one first.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (ctx, i) {
                  final p = playlists[i];
                  return ListTile(
                    leading: const Icon(Icons.playlist_play),
                    title: Text(p.name),
                    subtitle:
                        Text('${p.trackCount} track${p.trackCount == 1 ? '' : 's'}'),
                    onTap: () => _addToPlaylist(context, p),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _addToPlaylist(BuildContext context, PlaylistSummary playlist) async {
    Navigator.of(context).pop();
    await ref
        .read(playlistProvider.notifier)
        .addTracks(playlist.id, [widget.track.id]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to "${playlist.name}"')),
      );
    }
  }
}
