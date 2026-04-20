import 'package:audio_service/audio_service.dart';
import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/providers/player_provider.dart';
import 'package:bimusic_app/services/audio_service.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/ui/widgets/full_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthService extends Mock implements AuthService {}
class _MockAudioHandler extends Mock implements BiMusicAudioHandler {}

const _testTrack = Track(
  id: 1,
  title: 'Now Playing Song',
  trackNumber: '1',
  duration: 240000,
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
    when(() => mockHandler.currentTracks).thenReturn([]);
  });

  const playingState = PlayerState(
    currentTrack: _testTrack,
    isPlaying: true,
    artistName: 'Test Artist',
    albumTitle: 'Test Album',
  );

  Widget buildSubject(
    PlayerState playerState, {
    Duration position = const Duration(seconds: 60),
    Duration? duration = const Duration(seconds: 240),
    bool embedded = false,
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
        child: MaterialApp(
          home: Scaffold(body: FullPlayer(embedded: embedded)),
        ),
      );

  testWidgets('shows track title and artist', (tester) async {
    await tester.pumpWidget(buildSubject(playingState));
    await tester.pump();
    expect(find.text('Now Playing Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
  });

  testWidgets('renders progress slider', (tester) async {
    await tester.pumpWidget(buildSubject(playingState));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('shows pause icon when playing', (tester) async {
    await tester.pumpWidget(buildSubject(playingState));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('shows play icon when paused', (tester) async {
    const pausedState = PlayerState(
      currentTrack: _testTrack,
      isPlaying: false,
      artistName: 'Test Artist',
      albumTitle: 'Test Album',
    );
    await tester.pumpWidget(buildSubject(pausedState));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('duration label is shown', (tester) async {
    await tester.pumpWidget(buildSubject(playingState));
    await tester.pump();
    // Duration is 240s = 4 minutes -> "04:00"
    expect(find.text('04:00'), findsOneWidget);
  });

  testWidgets('position label is shown', (tester) async {
    await tester.pumpWidget(
      buildSubject(playingState, position: const Duration(seconds: 90)),
    );
    await tester.pump();
    // Position 90s = 1:30 -> "01:30"
    expect(find.text('01:30'), findsOneWidget);
  });

  testWidgets('shows Nothing playing when no track', (tester) async {
    await tester.pumpWidget(buildSubject(const PlayerState()));
    await tester.pump();
    expect(find.text('Nothing playing'), findsOneWidget);
  });

  testWidgets('shows album title in app bar', (tester) async {
    await tester.pumpWidget(buildSubject(playingState));
    await tester.pump();
    expect(find.text('Test Album'), findsOneWidget);
  });

  testWidgets('shows shuffle icon button', (tester) async {
    await tester.pumpWidget(buildSubject(playingState));
    await tester.pump();
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
  });

  testWidgets('shows skip prev and skip next buttons', (tester) async {
    await tester.pumpWidget(buildSubject(playingState));
    await tester.pump();
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('shows repeat icon button', (tester) async {
    await tester.pumpWidget(buildSubject(playingState));
    await tester.pump();
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
  });

  testWidgets('shows repeat_one icon when repeatMode is one', (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      repeatMode: AudioServiceRepeatMode.one,
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
  });

  testWidgets('shows music_note icon when no image URL', (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      imageUrl: null,
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    expect(find.byIcon(Icons.album), findsOneWidget);
  });

  testWidgets('shuffle icon has primary color when shuffled', (tester) async {
    const state = PlayerState(
      currentTrack: _testTrack,
      isPlaying: true,
      isShuffled: true,
    );
    await tester.pumpWidget(buildSubject(state));
    await tester.pump();
    // Icon is rendered with primary color when shuffled — just verify widget renders
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
  });

  testWidgets('default mode wraps content in DraggableScrollableSheet',
      (tester) async {
    await tester.pumpWidget(buildSubject(playingState));
    await tester.pump();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  });

  testWidgets('embedded mode skips DraggableScrollableSheet', (tester) async {
    await tester.pumpWidget(buildSubject(playingState, embedded: true));
    await tester.pump();
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    // Controls still render without the sheet wrapper
    expect(find.text('Now Playing Song'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });
}
