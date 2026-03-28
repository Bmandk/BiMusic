import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/playlist.dart';
import 'package:bimusic_app/providers/playlist_provider.dart';
import 'package:bimusic_app/ui/screens/playlists_screen.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _StubPlaylistNotifier extends PlaylistNotifier {
  _StubPlaylistNotifier(this._playlists, {this.failOnBuild = false});

  final List<PlaylistSummary> _playlists;
  final bool failOnBuild;

  @override
  Future<List<PlaylistSummary>> build() async {
    if (failOnBuild) throw Exception('Failed to load');
    return _playlists;
  }

  @override
  Future<PlaylistSummary> createPlaylist(String name) async {
    final newPlaylist = PlaylistSummary(
      id: 'new-id',
      name: name,
      trackCount: 0,
      createdAt: '2026-03-28T00:00:00Z',
    );
    state = AsyncData([...state.valueOrNull ?? [], newPlaylist]);
    return newPlaylist;
  }
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _testPlaylists = [
  PlaylistSummary(
    id: 'pl-1',
    name: 'Road Trip',
    trackCount: 12,
    createdAt: '2026-01-15T10:00:00Z',
  ),
  PlaylistSummary(
    id: 'pl-2',
    name: 'Chill Vibes',
    trackCount: 5,
    createdAt: '2026-02-20T08:00:00Z',
  ),
  PlaylistSummary(
    id: 'pl-3',
    name: 'Single Track',
    trackCount: 1,
    createdAt: '2026-03-01T12:00:00Z',
  ),
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget buildSubject(
  List<PlaylistSummary> playlists, {
  bool fail = false,
}) =>
    ProviderScope(
      overrides: [
        playlistProvider.overrideWith(
          () => _StubPlaylistNotifier(playlists, failOnBuild: fail),
        ),
      ],
      child: const MaterialApp(home: PlaylistsScreen()),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('renders Playlists title', (tester) async {
    await tester.pumpWidget(buildSubject(_testPlaylists));
    await tester.pump();
    expect(find.text('Playlists'), findsOneWidget);
  });

  testWidgets('renders playlist names', (tester) async {
    await tester.pumpWidget(buildSubject(_testPlaylists));
    await tester.pump();
    expect(find.text('Road Trip'), findsOneWidget);
    expect(find.text('Chill Vibes'), findsOneWidget);
  });

  testWidgets('shows "No playlists yet" when list is empty', (tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();
    expect(find.text('No playlists yet'), findsOneWidget);
  });

  testWidgets('shows FloatingActionButton to create a playlist', (tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('shows loading indicator while fetching', (tester) async {
    await tester.pumpWidget(buildSubject(_testPlaylists));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders track count in subtitle', (tester) async {
    await tester.pumpWidget(buildSubject(_testPlaylists));
    await tester.pump();
    // Road Trip has 12 tracks
    expect(find.textContaining('12 tracks'), findsOneWidget);
    // Single Track has 1 track (singular)
    expect(find.textContaining('1 track'), findsOneWidget);
  });

  testWidgets('renders formatted date in subtitle', (tester) async {
    await tester.pumpWidget(buildSubject(_testPlaylists));
    await tester.pump();
    // Road Trip created 2026-01-15
    expect(find.textContaining('2026-01-15'), findsOneWidget);
  });

  testWidgets('shows error state with retry button on load failure',
      (tester) async {
    await tester.pumpWidget(buildSubject([], fail: true));
    await tester.pump();

    expect(find.text('Failed to load playlists'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows FAB with add icon', (tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();
    expect(find.byIcon(Icons.add), findsWidgets);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets(
      'shows "Create a playlist" button in empty state', (tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();
    expect(find.text('Create a playlist'), findsOneWidget);
  });

  testWidgets('tapping FAB shows create playlist dialog', (tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('New Playlist'), findsOneWidget);
    expect(find.text('Playlist name'), findsOneWidget);
  });

  testWidgets('cancel button in create dialog closes without creating',
      (tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('No playlists yet'), findsOneWidget);
  });

  testWidgets('entering name and tapping Create creates new playlist',
      (tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'My New Playlist');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('My New Playlist'), findsOneWidget);
  });

  testWidgets('"Create a playlist" button also opens create dialog',
      (tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();

    await tester.tap(find.text('Create a playlist'));
    await tester.pumpAndSettle();

    expect(find.text('New Playlist'), findsOneWidget);
  });

  testWidgets('playlist list has CircleAvatar with queue icon', (tester) async {
    await tester.pumpWidget(buildSubject(_testPlaylists));
    await tester.pump();
    expect(find.byIcon(Icons.queue_music), findsWidgets);
  });
}
