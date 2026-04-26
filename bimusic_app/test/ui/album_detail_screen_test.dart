import 'package:audio_service/audio_service.dart';
import 'package:bimusic_app/models/album.dart';
import 'package:bimusic_app/models/download_task.dart';
import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/providers/backend_url_provider.dart';
import 'package:bimusic_app/providers/download_provider.dart';
import 'package:bimusic_app/providers/library_provider.dart';
import 'package:bimusic_app/providers/player_provider.dart';
import 'package:bimusic_app/services/audio_service.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/ui/screens/album_detail_screen.dart';
import 'package:bimusic_app/ui/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockAudioHandler extends Mock implements BiMusicAudioHandler {}

class _StubBackendUrlNotifier extends BackendUrlNotifier {
  @override
  Future<String?> build() async => 'http://test';
  @override
  Future<void> setUrl(String raw) async {}
  @override
  Future<void> clearUrl() async {}
}

class _StubDownloadNotifier extends DownloadNotifier {
  _StubDownloadNotifier([this._tasks = const []]);
  final List<DownloadTask> _tasks;

  @override
  DownloadState build() =>
      DownloadState(tasks: _tasks, isLoading: false, deviceId: 'test-dev');
}

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
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> adjustVolumeBy(double delta) async {}
  @override
  Future<void> toggleMute() async {}
}

const _testAlbum = Album(
  id: 1,
  title: 'Test Album',
  artistId: 10,
  artistName: 'Test Artist',
  imageUrl: 'http://example.com/album.jpg',
  releaseDate: '2020-06-15',
  genres: ['Rock'],
  trackCount: 2,
  duration: 300000,
);

const _albumNoDate = Album(
  id: 2,
  title: 'No Date Album',
  artistId: 10,
  artistName: 'Test Artist',
  imageUrl: 'http://example.com/album.jpg',
  genres: [],
  trackCount: 1,
  duration: 180000,
);

final _testTracks = [
  const Track(
    id: 1,
    title: 'First Track',
    trackNumber: '1',
    duration: 180000,
    albumId: 1,
    artistId: 10,
    hasFile: true,
    streamUrl: 'http://example.com/stream/1',
  ),
  const Track(
    id: 2,
    title: 'Second Track',
    trackNumber: '2',
    duration: 120000,
    albumId: 1,
    artistId: 10,
    hasFile: false,
    streamUrl: 'http://example.com/stream/2',
  ),
];

void main() {
  late _MockAuthService mockAuthService;
  late _MockAudioHandler mockHandler;

  setUpAll(() {
    registerFallbackValue(AudioServiceRepeatMode.none);
    registerFallbackValue(AudioServiceShuffleMode.none);
    registerFallbackValue(const Duration());
    registerFallbackValue(<Track>[]);
    registerFallbackValue(const Track(
      id: 0,
      title: '',
      trackNumber: '',
      duration: 0,
      albumId: 0,
      artistId: 0,
      hasFile: false,
      streamUrl: '',
    ));
  });

  setUp(() {
    mockAuthService = _MockAuthService();
    mockHandler = _MockAudioHandler();
    when(() => mockAuthService.accessToken).thenReturn('test_token');
  });

  Widget buildSubject({
    Album album = _testAlbum,
    List<Track>? tracks,
    List<DownloadTask> downloadTasks = const [],
  }) =>
      ProviderScope(
        overrides: [
          backendUrlProvider.overrideWith(() => _StubBackendUrlNotifier()),
          authServiceProvider.overrideWith((_) => mockAuthService),
          albumProvider(album.id).overrideWith((_) async => album),
          albumTracksProvider(album.id)
              .overrideWith((_) async => tracks ?? _testTracks),
          downloadProvider
              .overrideWith(() => _StubDownloadNotifier(downloadTasks)),
          audioHandlerProvider.overrideWithValue(mockHandler),
          playerNotifierProvider.overrideWith(() => _FakePlayerNotifier()),
        ],
        child: MaterialApp(
          home: AlbumDetailScreen(id: '${album.id}'),
        ),
      );

  testWidgets('renders album title and artist name', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.text('2020'), findsOneWidget);
  });

  testWidgets('renders track list from provider state', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.byType(TrackTile), findsNWidgets(2));
    expect(find.text('First Track'), findsOneWidget);
    expect(find.text('Second Track'), findsOneWidget);
  });

  testWidgets('shows loading indicator while tracks are loading',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('shows error state when album fails to load', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendUrlProvider.overrideWith(() => _StubBackendUrlNotifier()),
          authServiceProvider.overrideWith((_) => mockAuthService),
          albumProvider(1).overrideWith((_) async => throw Exception('fail')),
          albumTracksProvider(1)
              .overrideWith((_) async => _testTracks),
          downloadProvider.overrideWith(() => _StubDownloadNotifier()),
          audioHandlerProvider.overrideWithValue(mockHandler),
          playerNotifierProvider.overrideWith(() => _FakePlayerNotifier()),
        ],
        child: const MaterialApp(home: AlbumDetailScreen(id: '1')),
      ),
    );
    await tester.pump();

    expect(find.text('Failed to load album'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows error state when tracks fail to load', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendUrlProvider.overrideWith(() => _StubBackendUrlNotifier()),
          authServiceProvider.overrideWith((_) => mockAuthService),
          albumProvider(1).overrideWith((_) async => _testAlbum),
          albumTracksProvider(1)
              .overrideWith((_) async => throw Exception('fail')),
          downloadProvider.overrideWith(() => _StubDownloadNotifier()),
          audioHandlerProvider.overrideWithValue(mockHandler),
          playerNotifierProvider.overrideWith(() => _FakePlayerNotifier()),
        ],
        child: const MaterialApp(home: AlbumDetailScreen(id: '1')),
      ),
    );
    await tester.pump();

    expect(find.text('Failed to load tracks'), findsOneWidget);
  });

  testWidgets('shows Download Album button when no downloads active',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('Download Album'), findsOneWidget);
  });

  testWidgets('does not show release year when releaseDate is null',
      (tester) async {
    await tester.pumpWidget(buildSubject(album: _albumNoDate));
    await tester.pump();

    // Should not show a year
    expect(find.text('2020'), findsNothing);
  });

  testWidgets('shows Downloaded button when all tracks are completed',
      (tester) async {
    final completedTasks = _testTracks
        .map(
          (t) => DownloadTask(
            serverId: 'srv-${t.id}',
            trackId: t.id,
            albumId: 1,
            artistId: 10,
            userId: 'u1',
            deviceId: 'dev-1',
            status: DownloadStatus.completed,
            trackTitle: t.title,
            trackNumber: t.trackNumber,
            albumTitle: 'Test Album',
            artistName: 'Test Artist',
            bitrate: 320,
            requestedAt: '2026-03-28T00:00:00Z',
            fileSizeBytes: 1024,
            filePath: '/docs/${t.id}.mp3',
          ),
        )
        .toList();

    await tester.pumpWidget(buildSubject(downloadTasks: completedTasks));
    await tester.pump();

    expect(find.text('Downloaded'), findsOneWidget);
  });

  testWidgets('shows Downloading button when tracks are in progress',
      (tester) async {
    final inProgressTasks = [
      DownloadTask(
        serverId: 'srv-1',
        trackId: 1,
        albumId: 1,
        artistId: 10,
        userId: 'u1',
        deviceId: 'dev-1',
        status: DownloadStatus.downloading,
        trackTitle: 'First Track',
        trackNumber: '1',
        albumTitle: 'Test Album',
        artistName: 'Test Artist',
        bitrate: 320,
        requestedAt: '2026-03-28T00:00:00Z',
        progress: 0.5,
      ),
    ];

    await tester.pumpWidget(buildSubject(downloadTasks: inProgressTasks));
    await tester.pump();

    expect(find.textContaining('Downloading'), findsOneWidget);
  });
}
