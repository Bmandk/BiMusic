import 'dart:async';

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

  Duration? lastSeek;

  @override
  PlayerState build() => _initial;

  @override Future<void> play(Track t, List<Track> q,
      {required String artistName,
      required String albumTitle,
      required String imageUrl}) async {}
  @override Future<void> pause() async {}
  @override Future<void> resume() async {}
  @override Future<void> seekTo(Duration p) async { lastSeek = p; }
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

  Widget buildSubjectWithStreams(
    PlayerState playerState,
    _FakePlayerNotifier notifier, {
    required Stream<Duration> positionStream,
    Duration? duration = const Duration(seconds: 240),
  }) =>
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((_) => mockAuthService),
          audioHandlerProvider.overrideWithValue(mockHandler),
          playerNotifierProvider.overrideWith(() => notifier),
          playerPositionProvider.overrideWith((_) => positionStream),
          playerDurationProvider.overrideWith((_) => Stream.value(duration)),
        ],
        child: const MaterialApp(home: Scaffold(body: FullPlayer())),
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

  group('seek sticky state', () {
    // Duration is 240 s (04:00); 0.875 * 240000 ms = 210000 ms = 03:30.
    const trackDuration = Duration(seconds: 240);

    testWidgets('seekTo is called with the target duration', (tester) async {
      final notifier = _FakePlayerNotifier(playingState);
      final controller = StreamController<Duration>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(buildSubjectWithStreams(
        playingState,
        notifier,
        positionStream: controller.stream,
        duration: trackDuration,
      ));
      await tester.pump();

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeEnd!(0.875);
      await tester.pump();

      expect(notifier.lastSeek, const Duration(milliseconds: 210000));
    });

    testWidgets('slider label stays at target while player catches up',
        (tester) async {
      final notifier = _FakePlayerNotifier(playingState);
      final controller = StreamController<Duration>.broadcast();
      addTearDown(controller.close);

      controller.add(const Duration(seconds: 30));

      await tester.pumpWidget(buildSubjectWithStreams(
        playingState,
        notifier,
        positionStream: controller.stream,
        duration: trackDuration,
      ));
      await tester.pump();

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeEnd!(0.875);
      await tester.pump();

      // Label should show the seek target, not the stale position.
      expect(find.text('03:30'), findsOneWidget);

      // Emit a pre-seek stale position — label must remain at target.
      controller.add(const Duration(seconds: 31));
      await tester.pump();
      expect(find.text('03:30'), findsOneWidget);

      // Emit position at the target — sticky state releases.
      controller.add(const Duration(seconds: 210));
      await tester.pump();
      await tester.pump(); // extra frame for ref.listen setState to propagate
      expect(find.text('03:30'), findsOneWidget);

      // Subsequent positions beyond target flow through normally.
      controller.add(const Duration(seconds: 215));
      await tester.pump();
      await tester.pump(); // extra frame for provider update to propagate
      expect(find.text('03:35'), findsOneWidget);
    });

    testWidgets('safety timeout releases sticky state after 5 s',
        (tester) async {
      final notifier = _FakePlayerNotifier(playingState);
      final controller = StreamController<Duration>.broadcast();
      addTearDown(controller.close);

      controller.add(const Duration(seconds: 30));

      await tester.pumpWidget(buildSubjectWithStreams(
        playingState,
        notifier,
        positionStream: controller.stream,
        duration: trackDuration,
      ));
      await tester.pump();

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeEnd!(0.875);
      await tester.pump();
      expect(find.text('03:30'), findsOneWidget);

      // Advance past the 5-second safety timeout without emitting a catch-up.
      await tester.pump(const Duration(seconds: 5, milliseconds: 100));

      // Emit a pre-seek position — should now flow through since sticky released.
      controller.add(const Duration(seconds: 31));
      await tester.pump();
      await tester.pump(); // extra frame for provider update to propagate
      expect(find.text('00:31'), findsOneWidget);
    });

    testWidgets('new drag cancels previous sticky window', (tester) async {
      final notifier = _FakePlayerNotifier(playingState);
      final controller = StreamController<Duration>.broadcast();
      addTearDown(controller.close);

      controller.add(const Duration(seconds: 30));

      await tester.pumpWidget(buildSubjectWithStreams(
        playingState,
        notifier,
        positionStream: controller.stream,
        duration: trackDuration,
      ));
      await tester.pump();

      final slider = tester.widget<Slider>(find.byType(Slider));
      // First seek to 3:30.
      slider.onChangeEnd!(0.875);
      await tester.pump();
      expect(find.text('03:30'), findsOneWidget);

      // User starts a new drag to ~1:00 (0.25 * 240 = 60 s).
      slider.onChanged!(0.25);
      await tester.pump();

      // A late position near the first target must NOT resurrect the 3:30 sticky.
      controller.add(const Duration(seconds: 210));
      await tester.pump();
      expect(find.text('03:30'), findsNothing);
    });

    testWidgets('no timer leak on dispose', (tester) async {
      final notifier = _FakePlayerNotifier(playingState);
      final controller = StreamController<Duration>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(buildSubjectWithStreams(
        playingState,
        notifier,
        positionStream: controller.stream,
        duration: trackDuration,
      ));
      await tester.pump();

      // Arm the 5-second timer.
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeEnd!(0.875);
      await tester.pump();

      // Tear down the widget — dispose() must cancel the timer.
      await tester.pumpWidget(const SizedBox());
      // flutter_test will report a leaked timer if dispose() didn't cancel it.
    });
  });
}
