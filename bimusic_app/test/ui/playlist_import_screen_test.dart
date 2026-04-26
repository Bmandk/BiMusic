import 'package:bimusic_app/models/playlist.dart';
import 'package:bimusic_app/providers/playlist_provider.dart';
import 'package:bimusic_app/services/search_service.dart';
import 'package:bimusic_app/ui/screens/playlist_import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Stubs and mocks
// ---------------------------------------------------------------------------

class _MockSearchService extends Mock implements SearchService {}

class _StubPlaylistNotifier extends PlaylistNotifier {
  @override
  Future<List<PlaylistSummary>> build() async => [];

  @override
  Future<PlaylistSummary> createPlaylist(String name) async {
    return PlaylistSummary(
      id: 'new-id',
      name: name,
      trackCount: 0,
      createdAt: '2026-01-01T00:00:00Z',
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildSubject(_MockSearchService mockSearch) => ProviderScope(
      overrides: [
        searchServiceProvider.overrideWithValue(mockSearch),
        playlistProvider.overrideWith(() => _StubPlaylistNotifier()),
      ],
      child: const MaterialApp(home: PlaylistImportScreen()),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockSearchService mockSearch;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    mockSearch = _MockSearchService();
  });

  testWidgets('renders pick phase with Choose CSV button', (tester) async {
    await tester.pumpWidget(_buildSubject(mockSearch));

    expect(find.text('Import Playlist'), findsOneWidget);
    expect(find.text('Import from CSV'), findsOneWidget);
    expect(find.text('Choose CSV file'), findsOneWidget);
    expect(find.byIcon(Icons.upload_file), findsOneWidget);
  });

  testWidgets('shows supported format hint', (tester) async {
    await tester.pumpWidget(_buildSubject(mockSearch));

    expect(
      find.textContaining('Spotify/Exportify'),
      findsOneWidget,
    );
  });
}
