import 'package:bimusic_app/models/playlist.dart';
import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/services/playlist_service.dart';
import 'package:bimusic_app/ui/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlaylistService extends Mock implements PlaylistService {}

const _testTrack = Track(
  id: 1,
  title: 'Test Track',
  trackNumber: '3',
  duration: 213000, // 3:33
  albumId: 1,
  artistId: 10,
  hasFile: true,
  streamUrl: 'http://example.com/stream/1',
);

const _trackWithoutFile = Track(
  id: 2,
  title: 'Another Track',
  trackNumber: '4',
  duration: 120000, // 2:00
  albumId: 1,
  artistId: 10,
  hasFile: false,
  streamUrl: 'http://example.com/stream/2',
);

/// Builds a TrackTile inside a ProviderScope (required since TrackTile is a
/// ConsumerWidget that accesses playlistProvider on long-press).
Widget _buildTile(
  Track track, {
  VoidCallback? onTap,
  VoidCallback? onRemoveFromPlaylist,
  PlaylistService? playlistService,
}) {
  final service = playlistService ?? _MockPlaylistService();
  if (playlistService == null) {
    when(() => (service as _MockPlaylistService).listPlaylists())
        .thenAnswer((_) async => []);
  }

  return ProviderScope(
    overrides: [
      playlistServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: TrackTile(
          track: track,
          onTap: onTap ?? () {},
          onRemoveFromPlaylist: onRemoveFromPlaylist,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('displays track number, title, and formatted duration',
      (tester) async {
    await tester.pumpWidget(_buildTile(_testTrack));
    await tester.pump();

    expect(find.text('Test Track'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('3:33'), findsOneWidget);
  });

  testWidgets('shows offline indicator when hasFile is true', (tester) async {
    await tester.pumpWidget(_buildTile(_testTrack));
    await tester.pump();

    expect(find.byIcon(Icons.download_done), findsOneWidget);
  });

  testWidgets('hides offline indicator when hasFile is false', (tester) async {
    await tester.pumpWidget(_buildTile(_trackWithoutFile));
    await tester.pump();

    expect(find.byIcon(Icons.download_done), findsNothing);
  });

  testWidgets('tap triggers onTap callback', (tester) async {
    var tapped = false;

    await tester.pumpWidget(_buildTile(_testTrack, onTap: () => tapped = true));
    await tester.pump();

    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
  });

  testWidgets('long-press shows context sheet', (tester) async {
    final service = _MockPlaylistService();
    when(() => service.listPlaylists()).thenAnswer((_) async => []);

    await tester.pumpWidget(_buildTile(_testTrack, playlistService: service));
    await tester.pump();

    await tester.longPress(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(find.text('Add to Playlist'), findsOneWidget);
  });

  testWidgets('context sheet shows Remove from Playlist when callback set',
      (tester) async {
    final service = _MockPlaylistService();
    when(() => service.listPlaylists()).thenAnswer((_) async => []);

    await tester.pumpWidget(
      _buildTile(
        _testTrack,
        onRemoveFromPlaylist: () {},
        playlistService: service,
      ),
    );
    await tester.pump();

    await tester.longPress(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(find.text('Add to Playlist'), findsOneWidget);
    expect(find.text('Remove from Playlist'), findsOneWidget);
  });

  testWidgets('Remove from Playlist callback is invoked', (tester) async {
    final service = _MockPlaylistService();
    when(() => service.listPlaylists()).thenAnswer((_) async => []);

    var removed = false;

    await tester.pumpWidget(
      _buildTile(
        _testTrack,
        onRemoveFromPlaylist: () => removed = true,
        playlistService: service,
      ),
    );
    await tester.pump();

    await tester.longPress(find.byType(ListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove from Playlist'));
    await tester.pumpAndSettle();

    expect(removed, isTrue);
  });

  testWidgets('context sheet shows playlist list for Add to Playlist',
      (tester) async {
    final service = _MockPlaylistService();
    when(() => service.listPlaylists()).thenAnswer(
      (_) async => [
        const PlaylistSummary(
          id: 'p1',
          name: 'Favourites',
          trackCount: 3,
          createdAt: '2024-01-01T00:00:00Z',
        ),
      ],
    );

    await tester.pumpWidget(_buildTile(_testTrack, playlistService: service));
    await tester.pump();

    await tester.longPress(find.byType(ListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add to Playlist'));
    await tester.pumpAndSettle();

    expect(find.text('Favourites'), findsOneWidget);
  });
}
