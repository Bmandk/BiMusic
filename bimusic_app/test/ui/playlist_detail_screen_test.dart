import 'package:bimusic_app/models/playlist.dart';
import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/providers/download_provider.dart';
import 'package:bimusic_app/providers/player_provider.dart';
import 'package:bimusic_app/providers/playlist_provider.dart';
import 'package:bimusic_app/services/audio_service.dart';
import 'package:bimusic_app/services/playlist_service.dart';
import 'package:bimusic_app/ui/screens/playlist_detail_screen.dart';
import 'package:bimusic_app/ui/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlaylistService extends Mock implements PlaylistService {}

class _MockAudioHandler extends Mock implements BiMusicAudioHandler {}

class _FakePlayerNotifier extends Notifier<PlayerState>
    implements PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> play(Track track, List<Track> queue,
      {required String artistName,
      required String albumTitle,
      required String imageUrl}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrev() async {}

  @override
  Future<void> setRepeat(dynamic mode) async {}

  @override
  Future<void> toggleShuffle() async {}
}

class _StubDownloadNotifier extends DownloadNotifier {
  @override
  DownloadState build() =>
      const DownloadState(tasks: [], isLoading: false, deviceId: 'test-dev');
}

const _testPlaylist = PlaylistDetail(
  id: 'pl-1',
  name: 'My Playlist',
  tracks: [
    Track(
      id: 1,
      title: 'First Track',
      trackNumber: '1',
      duration: 180000,
      albumId: 1,
      artistId: 10,
      hasFile: true,
      streamUrl: 'http://example.com/stream/1',
    ),
    Track(
      id: 2,
      title: 'Second Track',
      trackNumber: '2',
      duration: 120000,
      albumId: 1,
      artistId: 10,
      hasFile: false,
      streamUrl: 'http://example.com/stream/2',
    ),
  ],
);

const _emptyPlaylist = PlaylistDetail(
  id: 'pl-2',
  name: 'Empty Playlist',
  tracks: [],
);

const _singleTrackPlaylist = PlaylistDetail(
  id: 'pl-3',
  name: 'Single',
  tracks: [
    Track(
      id: 3,
      title: 'Only Track',
      trackNumber: '1',
      duration: 200000,
      albumId: 1,
      artistId: 10,
      hasFile: true,
      streamUrl: 'http://example.com/stream/3',
    ),
  ],
);

Widget _buildSubject(
  String playlistId,
  PlaylistDetail playlist, {
  required _MockPlaylistService service,
}) {
  return ProviderScope(
    overrides: [
      playlistServiceProvider.overrideWithValue(service),
      playlistDetailProvider(playlistId).overrideWith((_) async => playlist),
      playlistProvider.overrideWith(() => _PlaylistListNotifierStub()),
      audioHandlerProvider.overrideWithValue(_MockAudioHandler()),
      playerNotifierProvider.overrideWith(() => _FakePlayerNotifier()),
      downloadProvider.overrideWith(() => _StubDownloadNotifier()),
    ],
    child: MaterialApp(
      home: PlaylistDetailScreen(id: playlistId),
    ),
  );
}

/// Stub for the list notifier — overrides build to avoid network calls.
/// Must extend [PlaylistNotifier] so the provider's type constraint is met.
class _PlaylistListNotifierStub extends PlaylistNotifier {
  @override
  Future<List<PlaylistSummary>> build() async => [];
}

void main() {
  late _MockPlaylistService mockService;

  setUp(() {
    mockService = _MockPlaylistService();
    when(() => mockService.listPlaylists()).thenAnswer((_) async => []);
    when(() => mockService.removeTrack(any(), any())).thenAnswer((_) async {});
    when(() => mockService.reorderTracks(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockService.updatePlaylist(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockService.deletePlaylist(any())).thenAnswer((_) async {});
  });

  setUpAll(() {
    registerFallbackValue(<int>[]);
  });

  testWidgets('renders playlist name in app bar', (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    expect(find.text('My Playlist'), findsWidgets);
  });

  testWidgets('renders all tracks', (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    expect(find.byType(TrackTile), findsNWidgets(2));
    expect(find.text('First Track'), findsOneWidget);
    expect(find.text('Second Track'), findsOneWidget);
  });

  testWidgets('shows empty state when playlist has no tracks', (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-2', _emptyPlaylist, service: mockService),
    );
    await tester.pump();

    expect(find.byType(TrackTile), findsNothing);
    expect(find.text('No tracks yet — long-press a track to add it.'),
        findsOneWidget);
  });

  testWidgets('shows loading indicator before data resolves', (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    // Before pump — future not yet resolved
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Play All button is visible when tracks exist', (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    expect(find.text('Play All'), findsOneWidget);
  });

  testWidgets('track list is displayed inside a ReorderableListView',
      (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    expect(find.byType(ReorderableListView), findsOneWidget);
  });

  testWidgets('remove from playlist triggers removeTrack on notifier',
      (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    // Long-press first track to open context sheet
    await tester.longPress(find.text('First Track'));
    await tester.pumpAndSettle();

    // Tap Remove from Playlist
    await tester.tap(find.text('Remove from Playlist'));
    await tester.pumpAndSettle();

    verify(() => mockService.removeTrack('pl-1', 1)).called(1);
  });

  testWidgets('rename button triggers rename dialog', (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Rename Playlist'), findsOneWidget);
    // Pre-filled with current name
    expect(find.text('My Playlist'), findsWidgets);
  });

  testWidgets('rename dialog cancel does not call updatePlaylist',
      (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockService.updatePlaylist(any(), any()));
  });

  testWidgets('delete button triggers confirmation dialog', (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete Playlist'), findsWidgets);
    expect(find.text(
        'Are you sure you want to delete this playlist? This cannot be undone.'),
        findsOneWidget);
  });

  testWidgets('cancelling delete dialog does not call deletePlaylist',
      (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockService.deletePlaylist(any()));
  });

  testWidgets('shows error state when playlist fails to load', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playlistServiceProvider.overrideWithValue(mockService),
          playlistDetailProvider('pl-err').overrideWith(
            (_) async => throw Exception('load failed'),
          ),
          playlistProvider.overrideWith(() => _PlaylistListNotifierStub()),
          audioHandlerProvider.overrideWithValue(_MockAudioHandler()),
          playerNotifierProvider.overrideWith(() => _FakePlayerNotifier()),
          downloadProvider.overrideWith(() => _StubDownloadNotifier()),
        ],
        child: const MaterialApp(
          home: PlaylistDetailScreen(id: 'pl-err'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Failed to load playlist'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows singular "track" for single track playlist',
      (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-3', _singleTrackPlaylist, service: mockService),
    );
    await tester.pump();

    expect(find.text('1 track'), findsOneWidget);
  });

  testWidgets('shows plural "tracks" for multi-track playlist', (tester) async {
    await tester.pumpWidget(
      _buildSubject('pl-1', _testPlaylist, service: mockService),
    );
    await tester.pump();

    expect(find.text('2 tracks'), findsOneWidget);
  });
}
