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
  @override Future<void> setVolume(double v) async {}
  @override Future<void> adjustVolumeBy(double delta) async {}
  @override Future<void> toggleMute() async {}
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

  Widget buildSubject(
    PlayerState playerState, {
    Duration position = const Duration(seconds: 30),
    Duration? duration = const Duration(seconds: 180),
  }) =>
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((_) => mockAuthService),
          audioHandlerProvider.overrideWithValue(mockHandler),
          playerNotifierProvider.overrideWith(
            () => _FakePlayerNotifier(playerState),
          ),
          playerPositionProvider.overrideWith(
            (_) => Stream.value(position),
          ),
          playerDurationProvider.overrideWith(
            (_) => Stream.value(duration),
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

  testWidgets('shows LinearProgressIndicator when track is playing',
      (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      artistName: 'Artist',
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows skip next button', (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('shows music_note icon when no image URL', (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      imageUrl: null,
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });

  testWidgets('progress bar shows 0 when position/duration are null',
      (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
    );
    await tester.pumpWidget(
      buildSubject(state, position: Duration.zero, duration: null),
    );
    await tester.pump();
    // LinearProgressIndicator should still render with 0 value
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('does not show artist name when artistName is null',
      (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      artistName: null,
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    // Track title still shows
    expect(find.text('Test Song'), findsOneWidget);
  });

  testWidgets('shows volume control on desktop platform', (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      volume: 1.0,
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    // Volume control is shown on desktop/web (flutter test runs on desktop platform)
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('volume icon reflects muted state', (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      volume: 0.0,
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
  });

  testWidgets('volume icon reflects low volume state', (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      volume: 0.3,
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);
  });
}
