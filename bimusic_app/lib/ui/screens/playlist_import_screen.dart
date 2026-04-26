import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/playlist_import.dart';
import '../../providers/playlist_provider.dart';
import '../../services/playlist_import_service.dart';
import '../../services/search_service.dart';

enum _Phase { pick, preview, importing, done }

class PlaylistImportScreen extends ConsumerStatefulWidget {
  const PlaylistImportScreen({super.key});

  @override
  ConsumerState<PlaylistImportScreen> createState() =>
      _PlaylistImportScreenState();
}

class _PlaylistImportScreenState extends ConsumerState<PlaylistImportScreen> {
  _Phase _phase = _Phase.pick;
  List<ImportAlbum> _albums = [];
  List<ImportItemResult> _results = [];
  int _currentIndex = 0;
  String _playlistName = '';
  bool _playlistCreated = false;
  String? _parseError;
  String? _importError;
  PlaylistImportService? _service;

  Future<void> _pickFile() async {
    setState(() => _parseError = null);

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    if (file.bytes == null) {
      setState(() => _parseError = 'Could not read file contents.');
      return;
    }

    String contents;
    try {
      contents = utf8.decode(file.bytes!, allowMalformed: true);
    } catch (e) {
      setState(() => _parseError = 'Failed to read file: $e');
      return;
    }

    final filename = file.name;
    final rawName = filename.endsWith('.csv')
        ? filename.substring(0, filename.length - 4)
        : filename;
    final playlistName = rawName.replaceAll('_', ' ');

    try {
      final service = PlaylistImportService(ref.read(searchServiceProvider));
      final rows = service.parseCsv(contents);
      final albums = service.dedupeAlbums(rows);

      if (albums.isEmpty) {
        setState(() => _parseError = 'No valid album data found in the CSV.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _albums = albums;
        _results = albums.map((a) => ImportItemResult(album: a)).toList();
        _playlistName = playlistName;
        _phase = _Phase.preview;
        _service = service;
      });
    } on FormatException catch (e) {
      setState(() => _parseError = e.message);
    } catch (e) {
      setState(() => _parseError = 'Failed to parse CSV: $e');
    }
  }

  Future<void> _startImport() async {
    setState(() {
      _phase = _Phase.importing;
      _currentIndex = 0;
    });

    final service = _service ??
        PlaylistImportService(ref.read(searchServiceProvider));

    for (int i = 0; i < _albums.length; i++) {
      if (!mounted) return;
      setState(() {
        _results[i] = ImportItemResult(
          album: _albums[i],
          status: ImportStatus.searching,
        );
      });

      final result = await service.processAlbum(_albums[i]);

      if (!mounted) return;
      setState(() {
        _results[i] = result;
        _currentIndex = i + 1;
      });
    }

    try {
      await ref.read(playlistProvider.notifier).createPlaylist(_playlistName);
      if (mounted) setState(() => _playlistCreated = true);
    } catch (e) {
      if (mounted) setState(() => _importError = 'Playlist creation failed: $e');
    }

    if (mounted) setState(() => _phase = _Phase.done);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Playlist')),
      body: switch (_phase) {
        _Phase.pick => _buildPick(context),
        _Phase.preview => _buildPreview(context),
        _Phase.importing => _buildImporting(context),
        _Phase.done => _buildDone(context),
      },
    );
  }

  Widget _buildPick(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_add,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Import from CSV',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Supports Spotify/Exportify CSV exports.\nEach album will be requested from Lidarr.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_parseError != null) ...[
              const SizedBox(height: 16),
              Text(
                _parseError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose CSV file'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final trackCount = _results.fold(0, (sum, r) => sum + r.album.trackCount);
    return Column(
      children: [
        ListTile(
          leading: Icon(
            Icons.playlist_add,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            _playlistName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${_albums.length} album${_albums.length == 1 ? '' : 's'} · '
            '$trackCount track${trackCount == 1 ? '' : 's'}',
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _albums.length,
            itemBuilder: (ctx, i) {
              final album = _albums[i];
              return ListTile(
                title: Text(album.albumName),
                subtitle: Text(album.artistName),
                trailing: Text(
                  '${album.trackCount} track${album.trackCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _phase = _Phase.pick;
                  _albums = [];
                  _results = [];
                  _service = null;
                }),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _startImport,
                child: const Text('Start Import'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImporting(BuildContext context) {
    final total = _albums.length;
    return Column(
      children: [
        LinearProgressIndicator(
          value: total == 0 ? null : _currentIndex / total,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            'Requesting $_currentIndex of $total albums…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _results.length,
            itemBuilder: (ctx, i) => _ResultTile(result: _results[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    final requested =
        _results.where((r) => r.status == ImportStatus.requestedAlbum).length;
    final artistFallback =
        _results.where((r) => r.status == ImportStatus.requestedArtist).length;
    final notFound =
        _results.where((r) => r.status == ImportStatus.notFound).length;
    final failed =
        _results.where((r) => r.status == ImportStatus.failed).length;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (requested > 0)
                    Chip(
                      avatar: Icon(Icons.album, size: 16, color: cs.onPrimary),
                      label: Text(
                        '$requested album${requested == 1 ? '' : 's'} requested',
                      ),
                      backgroundColor: cs.primary,
                      labelStyle: TextStyle(color: cs.onPrimary),
                    ),
                  if (artistFallback > 0)
                    Chip(
                      avatar: const Icon(Icons.person, size: 16),
                      label: Text(
                        '$artistFallback artist${artistFallback == 1 ? '' : 's'} requested',
                      ),
                    ),
                  if (notFound > 0)
                    Chip(
                      avatar: Icon(Icons.search_off, size: 16, color: cs.onError),
                      label: Text('$notFound not found'),
                      backgroundColor: cs.error,
                      labelStyle: TextStyle(color: cs.onError),
                    ),
                  if (failed > 0)
                    Chip(
                      avatar: Icon(Icons.error_outline, size: 16, color: cs.onError),
                      label: Text('$failed failed'),
                      backgroundColor: cs.error,
                      labelStyle: TextStyle(color: cs.onError),
                    ),
                ],
              ),
              if (_playlistCreated) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.playlist_add_check, size: 16, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Playlist "$_playlistName" created',
                      style: TextStyle(color: cs.primary),
                    ),
                  ],
                ),
              ],
              if (_importError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _importError!,
                  style: TextStyle(color: cs.error),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _results.length,
            itemBuilder: (ctx, i) => _ResultTile(result: _results[i]),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => context.go('/playlists'),
              child: const Text('Done'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final ImportItemResult result;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: _statusIcon(context, result.status),
      title: Text(result.album.albumName),
      subtitle: Text(result.album.artistName),
      trailing: result.status == ImportStatus.requestedArtist
          ? const Chip(
              label: Text('Artist'),
              visualDensity: VisualDensity.compact,
            )
          : (result.status == ImportStatus.failed &&
                  result.errorMessage != null)
              ? Tooltip(
                  message: result.errorMessage!,
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                )
              : null,
    );
  }

  Widget _statusIcon(BuildContext context, ImportStatus status) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      ImportStatus.pending =>
        Icon(Icons.circle_outlined, color: cs.outline, size: 20),
      ImportStatus.searching => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ImportStatus.requestedAlbum =>
        Icon(Icons.check_circle, color: cs.tertiary, size: 20),
      ImportStatus.requestedArtist =>
        Icon(Icons.person, color: cs.secondary, size: 20),
      ImportStatus.notFound =>
        Icon(Icons.search_off, color: cs.error, size: 20),
      ImportStatus.failed =>
        Icon(Icons.error_outline, color: cs.error, size: 20),
    };
  }
}
