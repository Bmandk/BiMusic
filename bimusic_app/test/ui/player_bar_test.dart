import 'package:audio_service/audio_service.dart';
import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/providers/player_provider.dart';
import 'package:bimusic_app/services/audio_service.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/ui/widgets/player_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthService extends Mock implements AuthService {}
class _MockAudioHandler extends Mock implements BiMusicAudioHandler {}

const _testTrack = Track(
  id: 1,
  title: 'Test Song',
  trackNumber: '1',
  duration: 180000,
  albumId: 10,
  artistId: 5,
  hasFile: false,
  streamUrl: 'http://example.com/stream/1',
);

class _FakePlayerNotifier extends Notifier<PlayerState>
    implements PlayerNotifier {
  final PlayerState _initial;
  _FakePlayerNotifier(this._initial);

  @override
  PlayerState build() => _initial;

  @override Future<void> play(Track t, List<Track> q,
      {required String artistName,
      required String albumTitle,
      required String imageUrl}) async {}
  @override Future<void> pause() async {}
  @override Future<void> resume() async {}
  @override Future<void> seekTo(Duration p) async {}
  @override Future<void> skipNext() async {}
  @override Future<void> skipPrev() async {}
  @override Future<void> setRepeat(AudioServiceRepeatMode m) async {}
  @override Future<void> toggleShuffle() async {}
}

void main() {
  late _MockAuthService mockAuthService;
  late _MockAudioHandler mockHandler;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(AudioServiceRepeatMode.none);
    registerFallbackValue(AudioServiceShuffleMode.none);
  });

  setUp(() {
    mockAuthService = _MockAuthService();
    mockHandler = _MockAudioHandler();
    when(() => mockAuthService.accessToken).thenReturn('tok');
    when(() => mockHandler.positionStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockHandler.durationStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockHandler.playbackState)
        .thenAnswer((_) => throw UnimplementedError());
    when(() => mockHandler.mediaItem)
        .thenAnswer((_) => throw UnimplementedError());
    when(() => mockHandler.currentTracks).thenReturn([]);
  });

  Widget buildSubject(PlayerState playerState) => ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((_) => mockAuthService),
          audioHandlerProvider.overrideWithValue(mockHandler),
          playerNotifierProvider.overrideWith(
            () => _FakePlayerNotifier(playerState),
          ),
          playerPositionProvider.overrideWith(
            (_) => Stream.value(const Duration(seconds: 30)),
          ),
          playerDurationProvider.overrideWith(
            (_) => Stream.value(const Duration(seconds: 180)),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: PlayerBar())),
      );

  testWidgets('shows nothing when no track is playing', (tester) async {
    await tester.pumpWidget(buildSubject(const PlayerState()));
    await tester.pump();
    expect(find.byType(PlayerBar), findsOneWidget);
    // SizedBox.shrink when no track
    expect(find.text('Test Song'), findsNothing);
  });

  testWidgets('shows track title and artist when track is loaded',
      (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      artistName: 'Test Artist',
      albumTitle: 'Test Album',
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
  });

  testWidgets('play/pause button shows pause icon when playing',
      (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      artistName: 'Artist',
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('play/pause button shows play icon when paused', (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: false,
      artistName: 'Artist',
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
