import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/download_task.dart';
import '../../providers/download_provider.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Downloads')),
        body: const Center(
          child: Text('Offline downloads are not available on web.'),
        ),
      );
    }

    final state = ref.watch(downloadProvider);
    final usage = ref.watch(storageUsageProvider);

    if (state.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Downloads')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final tasks = state.tasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (tasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Remove all downloads',
              onPressed: () => _confirmRemoveAll(context, ref, tasks),
            ),
        ],
      ),
      body: Column(
        children: [
          _StorageUsageBanner(usage: usage),
          Expanded(
            child: tasks.isEmpty
                ? _EmptyState()
                : _DownloadList(tasks: tasks),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveAll(
    BuildContext context,
    WidgetRef ref,
    List<DownloadTask> tasks,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove all downloads?'),
        content: const Text(
          'This will delete all downloaded files from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final notifier = ref.read(downloadProvider.notifier);
      for (final task in List.of(tasks)) {
        await notifier.removeDownload(task.serverId);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Storage usage banner
// ---------------------------------------------------------------------------

class _StorageUsageBanner extends StatelessWidget {
  const _StorageUsageBanner({required this.usage});

  final StorageUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.storage_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Offline storage',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${usage.formattedSize} · ${usage.trackCount} track${usage.trackCount == 1 ? '' : 's'}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.download_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No downloads yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Download albums to listen offline.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Download list — grouped by album
// ---------------------------------------------------------------------------

class _DownloadList extends ConsumerWidget {
  const _DownloadList({required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group tasks by albumId.
    final byAlbum = <int, List<DownloadTask>>{};
    for (final t in tasks) {
      byAlbum.putIfAbsent(t.albumId, () => []).add(t);
    }

    final albumIds = byAlbum.keys.toList();

    return ListView.builder(
      itemCount: albumIds.length,
      itemBuilder: (ctx, i) {
        final albumId = albumIds[i];
        final albumTasks = byAlbum[albumId]!;
        return _AlbumDownloadGroup(
          albumId: albumId,
          tasks: albumTasks,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Album group header + track rows
// ---------------------------------------------------------------------------

class _AlbumDownloadGroup extends ConsumerWidget {
  const _AlbumDownloadGroup({
    required this.albumId,
    required this.tasks,
  });

  final int albumId;
  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final albumTitle = tasks.first.albumTitle;
    final artistName = tasks.first.artistName;
    final allDone = tasks.every((t) => t.status == DownloadStatus.completed);
    final anyActive = tasks.any((t) => t.status == DownloadStatus.downloading);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Album header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      albumTitle,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      artistName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (allDone)
                Icon(Icons.download_done, size: 18, color: theme.colorScheme.primary)
              else if (anyActive)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              // Bulk delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Remove album',
                onPressed: () => _confirmRemoveAlbum(context, ref),
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16),
        // Track rows
        ...tasks.map(
          (t) => _TrackDownloadTile(task: t),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Future<void> _confirmRemoveAlbum(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove album?'),
        content: Text(
          'Delete all downloaded tracks for "${tasks.first.albumTitle}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final notifier = ref.read(downloadProvider.notifier);
      for (final task in List.of(tasks)) {
        await notifier.removeDownload(task.serverId);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Individual track download row
// ---------------------------------------------------------------------------

class _TrackDownloadTile extends ConsumerWidget {
  const _TrackDownloadTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(task.serverId),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
      confirmDismiss: (_) async => _confirmRemove(context),
      onDismissed: (_) =>
          ref.read(downloadProvider.notifier).removeDownload(task.serverId),
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 32,
          child: Center(
            child: Text(
              task.trackNumber,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        title: Text(
          task.trackTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _subtitle(context),
        trailing: _statusIcon(context, ref),
      ),
    );
  }

  Widget? _subtitle(BuildContext context) {
    if (task.status == DownloadStatus.downloading && task.progress != null) {
      return LinearProgressIndicator(
        value: task.progress,
        minHeight: 2,
        borderRadius: BorderRadius.circular(1),
      );
    }
    if (task.status == DownloadStatus.failed) {
      return Text(
        task.errorMessage ?? 'Failed',
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return null;
  }

  Widget _statusIcon(BuildContext context, WidgetRef ref) {
    switch (task.status) {
      case DownloadStatus.pending:
        return const Icon(Icons.schedule, size: 18);
      case DownloadStatus.downloading:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            value: task.progress,
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      case DownloadStatus.completed:
        return Icon(
          Icons.download_done,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        );
      case DownloadStatus.failed:
        return IconButton(
          icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.error),
          tooltip: 'Retry',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () =>
              ref.read(downloadProvider.notifier).cancelDownload(task.serverId),
        );
    }
  }

  Future<bool> _confirmRemove(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text('Delete "${task.trackTitle}" from offline storage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return result == true;
  }
}
