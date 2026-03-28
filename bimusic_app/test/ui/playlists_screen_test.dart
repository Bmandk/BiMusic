import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/playlist.dart';
import 'package:bimusic_app/providers/playlist_provider.dart';
import 'package:bimusic_app/ui/screens/playlists_screen.dart';

class _StubPlaylistNotifier extends PlaylistNotifier {
  final List<PlaylistSummary> _playlists;
  _StubPlaylistNotifier(this._playlists);

  @override
  Future<List<PlaylistSummary>> build() async => _playlists;
}

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
];

void main() {
  Widget buildSubject(List<PlaylistSummary> playlists) => ProviderScope(
        overrides: [
          playlistProvider
              .overrideWith(() => _StubPlaylistNotifier(playlists)),
        ],
        child: const MaterialApp(home: PlaylistsScreen()),
      );

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
    // Before resolving async, loading indicator is shown
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
