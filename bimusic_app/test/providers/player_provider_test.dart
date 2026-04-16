import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart' show BehaviorSubject;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/download_task.dart';
import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/models/user.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/providers/bitrate_preference_provider.dart';
import 'package:bimusic_app/providers/download_provider.dart';
import 'package:bimusic_app/providers/player_provider.dart';
import 'package:bimusic_app/services/audio_service.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/services/download_service.dart';

// ---------------------------------------------------------------------------
// Mock audio handler — stubbing BehaviorSubject streams
// ---------------------------------------------------------------------------

class _MockAudioHandler extends Mock implements BiMusicAudioHandler {
  final _playbackSubject = BehaviorSubject<PlaybackState>.seeded(
    PlaybackState(),
  );
  final _mediaSubject = BehaviorSubject<MediaItem?>.seeded(null);

  @override
  BehaviorSubject<PlaybackState> get playbackState => _playbackSubject;

  @override
  BehaviorSubject<MediaItem?> get mediaItem => _mediaSubject;

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  List<Track> get currentTracks => [];
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeAuthService extends Fake implements AuthService {
  @override
  String? get accessToken => 'test-token';
}

class _FakeAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  @override
  Future<void> get initialized async {}

  @override
  AuthState build() => const AuthStateAuthenticated(
        AuthTokens(
          accessToken: 'tok',
          refreshToken: 'rtok',
          user: User(userId: 'u1', username: 'tester', isAdmin: false),
        ),
      );

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}
}

class _StubDownloadNotifier extends DownloadNotifier {
  @override
  DownloadState build() =>
      const DownloadState(tasks: [], isLoading: false, deviceId: 'test-dev');
}

class _StubDownloadNotifierWithTask extends DownloadNotifier {
  @override
  DownloadState build() => DownloadState(
        tasks: [
          DownloadTask(
            serverId: 'srv-1',
            trackId: 1,
            albumId: 10,
            artistId: 5,
            userId: 'u1',
            deviceId: 'test-dev',
            albumTitle: 'Test Album',
            artistName: 'Test Artist',
            trackTitle: 'Track One',
            trackNumber: '1',
            bitrate: 128,
            requestedAt: '2026-03-28T00:00:00Z',
            status: DownloadStatus.completed,
            filePath: '/local/track1.mp3',
          ),
        ],
        isLoading: false,
        deviceId: 'test-dev',
      );
}

class _StubBitratePreferenceNotifier extends BitratePreferenceNotifier {
  @override
  BitratePreference build() => BitratePreference.alwaysLow;
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _track1 = Track(
  id: 1,
  title: 'Track One',
  trackNumber: '1',
  duration: 180000,
  albumId: 10,
  artistId: 5,
  hasFile: true,
  streamUrl: 'http://example.com/stream/1',
);

const _track2 = Track(
  id: 2,
  title: 'Track Two',
  trackNumber: '2',
  duration: 240000,
  albumId: 10,
  artistId: 5,
  hasFile: true,
  streamUrl: 'http://example.com/stream/2',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockAudioHandler mockHandler;
  late ProviderContainer container;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
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
    mockHandler = _MockAudioHandler();

    // Stub all methods on the mock that PlayerNotifier calls.
    when(() => mockHandler.pause()).thenAnswer((_) async {});
    when(() => mockHandler.play()).thenAnswer((_) async {});
    when(() => mockHandler.seek(any())).thenAnswer((_) async {});
    when(() => mockHandler.skipToNext()).thenAnswer((_) async {});
    when(() => mockHandler.skipToPrevious()).thenAnswer((_) async {});
    when(() => mockHandler.setRepeatMode(any())).thenAnswer((_) async {});
    when(() => mockHandler.setShuffleMode(any())).thenAnswer((_) async {});
    when(() => mockHandler.playQueue(
          any(),
          any(),
          any(),
          any(),
          artistName: any(named: 'artistName'),
          albumTitle: any(named: 'albumTitle'),
          imageUrl: any(named: 'imageUrl'),
          localFilePaths: any(named: 'localFilePaths'),
        )).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        audioHandlerProvider.overrideWithValue(mockHandler),
        authServiceProvider.overrideWith((_) => _FakeAuthService()),
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
        downloadProvider.overrideWith(() => _StubDownloadNotifier()),
        bitratePreferenceProvider.overrideWith(
          () => _StubBitratePreferenceNotifier(),
        ),
        deviceIdProvider.overrideWith((_) async => 'test-dev'),
      ],
    );
  });

  tearDown(() => container.dispose());

  PlayerNotifier notifier() => container.read(playerNotifierProvider.notifier);
  PlayerState state() => container.read(playerNotifierProvider);

  // ---------------------------------------------------------------------------
  // PlayerState unit tests — no audio handler needed
  // ---------------------------------------------------------------------------

  group('PlayerState', () {
    test('initial state has no track and isPlaying false', () {
      const s = PlayerState();
      expect(s.hasTrack, isFalse);
      expect(s.isPlaying, isFalse);
      expect(s.queue, isEmpty);
      expect(s.repeatMode, AudioServiceRepeatMode.none);
      expect(s.isShuffled, isFalse);
    });

    test('hasTrack returns true when currentTrack is set', () {
      const s = PlayerState(currentTrack: _track1);
      expect(s.hasTrack, isTrue);
    });

    test('hasTrack returns false when currentTrack is null', () {
      const s = PlayerState();
      expect(s.hasTrack, isFalse);
    });

    group('copyWith', () {
      test('copies all specified fields', () {
        const original = PlayerState();
        final updated = original.copyWith(
          currentTrack: _track1,
          queue: [_track1, _track2],
          isPlaying: true,
          repeatMode: AudioServiceRepeatMode.all,
          isShuffled: true,
          artistName: 'Test Artist',
          albumTitle: 'Test Album',
          imageUrl: 'http://example.com/img.jpg',
        );

        expect(updated.currentTrack, _track1);
        expect(updated.queue, hasLength(2));
        expect(updated.isPlaying, isTrue);
        expect(updated.repeatMode, AudioServiceRepeatMode.all);
        expect(updated.isShuffled, isTrue);
        expect(updated.artistName, 'Test Artist');
        expect(updated.albumTitle, 'Test Album');
        expect(updated.imageUrl, 'http://example.com/img.jpg');
      });

      test('preserves unspecified fields', () {
        const original = PlayerState(
          currentTrack: _track1,
          isPlaying: true,
          artistName: 'Artist',
        );

        final updated = original.copyWith(isPlaying: false);

        expect(updated.currentTrack, _track1);
        expect(updated.isPlaying, isFalse);
        expect(updated.artistName, 'Artist');
      });
    });
  });

  // ---------------------------------------------------------------------------
  // PlayerNotifier action tests — require audio handler
  // ---------------------------------------------------------------------------

  group('PlayerNotifier.pause', () {
    test('calls handler.pause()', () async {
      await notifier().pause();
      verify(() => mockHandler.pause()).called(1);
    });
  });

  group('PlayerNotifier.resume', () {
    test('calls handler.play()', () async {
      await notifier().resume();
      verify(() => mockHandler.play()).called(1);
    });
  });

  group('PlayerNotifier.seekTo', () {
    test('calls handler.seek() with given duration', () async {
      const position = Duration(seconds: 42);
      await notifier().seekTo(position);
      verify(() => mockHandler.seek(position)).called(1);
    });
  });

  group('PlayerNotifier.skipNext', () {
    test('calls handler.skipToNext()', () async {
      await notifier().skipNext();
      verify(() => mockHandler.skipToNext()).called(1);
    });
  });

  group('PlayerNotifier.skipPrev', () {
    test('calls handler.skipToPrevious()', () async {
      await notifier().skipPrev();
      verify(() => mockHandler.skipToPrevious()).called(1);
    });
  });

  group('PlayerNotifier.setRepeat', () {
    test('calls handler.setRepeatMode() with all mode', () async {
      await notifier().setRepeat(AudioServiceRepeatMode.all);
      verify(() => mockHandler.setRepeatMode(AudioServiceRepeatMode.all))
          .called(1);
    });

    test('calls handler.setRepeatMode() with one mode', () async {
      await notifier().setRepeat(AudioServiceRepeatMode.one);
      verify(() => mockHandler.setRepeatMode(AudioServiceRepeatMode.one))
          .called(1);
    });
  });

  group('PlayerNotifier.toggleShuffle', () {
    test('calls setShuffleMode(all) when isShuffled is false', () async {
      // Initial state: not shuffled
      expect(state().isShuffled, isFalse);
      await notifier().toggleShuffle();
      verify(() => mockHandler.setShuffleMode(AudioServiceShuffleMode.all))
          .called(1);
    });
  });

  group('PlayerNotifier.play', () {
    test('updates state with track, queue, and metadata', () async {
      await notifier().play(
        _track1,
        [_track1, _track2],
        artistName: 'Test Artist',
        albumTitle: 'Test Album',
        imageUrl: 'http://example.com/img.jpg',
      );

      expect(state().currentTrack, _track1);
      expect(state().queue, hasLength(2));
      expect(state().isPlaying, isTrue);
      expect(state().artistName, 'Test Artist');
      expect(state().albumTitle, 'Test Album');
      expect(state().imageUrl, 'http://example.com/img.jpg');
    });

    test('calls handler.playQueue with correct start index', () async {
      await notifier().play(
        _track1,
        [_track1, _track2],
        artistName: 'Test Artist',
        albumTitle: 'Test Album',
        imageUrl: 'http://img.jpg',
      );

      verify(() => mockHandler.playQueue(
            [_track1, _track2],
            0, // startIndex = 0 (track1 is first)
            'test-token',
            any(), // bitrate
            artistName: 'Test Artist',
            albumTitle: 'Test Album',
            imageUrl: 'http://img.jpg',
            localFilePaths: any(named: 'localFilePaths'),
          )).called(1);
    });

    test('uses startIndex 0 when track is not in queue', () async {
      await notifier().play(
        _track2,
        [_track1], // track2 not in queue → indexOf returns -1 → clamp to 0
        artistName: 'Artist',
        albumTitle: 'Album',
        imageUrl: 'http://img.jpg',
      );

      verify(() => mockHandler.playQueue(
            [_track1],
            0, // -1 → clamped to 0
            any(),
            any(),
            artistName: any(named: 'artistName'),
            albumTitle: any(named: 'albumTitle'),
            imageUrl: any(named: 'imageUrl'),
            localFilePaths: any(named: 'localFilePaths'),
          )).called(1);
    });

    test('uses correct startIndex when track is in middle of queue', () async {
      await notifier().play(
        _track2,
        [_track1, _track2],
        artistName: 'Artist',
        albumTitle: 'Album',
        imageUrl: 'http://img.jpg',
      );

      verify(() => mockHandler.playQueue(
            [_track1, _track2],
            1, // track2 is at index 1
            any(),
            any(),
            artistName: any(named: 'artistName'),
            albumTitle: any(named: 'albumTitle'),
            imageUrl: any(named: 'imageUrl'),
            localFilePaths: any(named: 'localFilePaths'),
          )).called(1);
    });

    test('resolves local file paths for completed downloads', () async {
      // Override downloadProvider with a task that has a completed download
      final localContainer = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(mockHandler),
          authServiceProvider.overrideWith((_) => _FakeAuthService()),
          authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
          downloadProvider.overrideWith(() => _StubDownloadNotifierWithTask()),
          bitratePreferenceProvider.overrideWith(
            () => _StubBitratePreferenceNotifier(),
          ),
          deviceIdProvider.overrideWith((_) async => 'test-dev'),
        ],
      );
      addTearDown(localContainer.dispose);

      await localContainer.read(playerNotifierProvider.notifier).play(
        _track1,
        [_track1],
        artistName: 'Artist',
        albumTitle: 'Album',
        imageUrl: 'http://img.jpg',
      );

      // localFilePaths should have been populated with the completed download
      verify(() => mockHandler.playQueue(
            any(),
            any(),
            any(),
            any(),
            artistName: any(named: 'artistName'),
            albumTitle: any(named: 'albumTitle'),
            imageUrl: any(named: 'imageUrl'),
            localFilePaths: any(named: 'localFilePaths'),
          )).called(1);
    });
  });

  group('playbackState stream', () {
    test('updates isPlaying when playbackState emits', () async {
      // Initialize the notifier (subscribes to stream in build())
      container.read(playerNotifierProvider);
      // Allow any async setup to complete
      await Future<void>.value();

      // Emit a new playback state with playing=true
      mockHandler.playbackState.add(
        PlaybackState(
          playing: true,
          repeatMode: AudioServiceRepeatMode.all,
          shuffleMode: AudioServiceShuffleMode.all,
        ),
      );
      await Future<void>.value();

      final s = container.read(playerNotifierProvider);
      expect(s.isPlaying, isTrue);
      expect(s.repeatMode, AudioServiceRepeatMode.all);
      expect(s.isShuffled, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Offline localFilePaths assertion
  // ---------------------------------------------------------------------------

  group('play() with offline tracks', () {
    test('passes localFilePaths for completed downloads', () async {
      // Build a container whose downloadProvider is seeded with a completed
      // DownloadTask for _track1 (id=1, filePath='/local/track1.mp3').
      final localContainer = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(mockHandler),
          authServiceProvider.overrideWith((_) => _FakeAuthService()),
          authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
          downloadProvider.overrideWith(() => _StubDownloadNotifierWithTask()),
          bitratePreferenceProvider.overrideWith(
            () => _StubBitratePreferenceNotifier(),
          ),
          deviceIdProvider.overrideWith((_) async => 'test-dev'),
        ],
      );
      addTearDown(localContainer.dispose);

      await localContainer.read(playerNotifierProvider.notifier).play(
            _track1,
            [_track1],
            artistName: 'Test Artist',
            albumTitle: 'Test Album',
            imageUrl: 'http://img.jpg',
          );

      // Verify playQueue was called with localFilePaths containing the
      // expected trackId → filePath mapping for the completed download.
      verify(
        () => mockHandler.playQueue(
          any(),
          any(),
          any(),
          any(),
          artistName: any(named: 'artistName'),
          albumTitle: any(named: 'albumTitle'),
          imageUrl: any(named: 'imageUrl'),
          localFilePaths: {1: '/local/track1.mp3'},
        ),
      ).called(1);
    });
  });

  group('playerPositionProvider', () {
    test('returns an AsyncValue backed by positionStream', () async {
      final c = ProviderContainer(overrides: [
        audioHandlerProvider.overrideWithValue(mockHandler),
        authServiceProvider.overrideWith((_) => _FakeAuthService()),
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
        downloadProvider.overrideWith(() => _StubDownloadNotifier()),
        bitratePreferenceProvider.overrideWith(
          () => _StubBitratePreferenceNotifier(),
        ),
        deviceIdProvider.overrideWith((_) async => 'test-dev'),
      ]);
      addTearDown(c.dispose);

      // Simply reading the provider exercises lines 163-165.
      final value = c.read(playerPositionProvider);
      expect(value, isA<AsyncValue<Duration>>());
    });
  });

  group('playerDurationProvider', () {
    test('returns an AsyncValue backed by durationStream', () async {
      final c = ProviderContainer(overrides: [
        audioHandlerProvider.overrideWithValue(mockHandler),
        authServiceProvider.overrideWith((_) => _FakeAuthService()),
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
        downloadProvider.overrideWith(() => _StubDownloadNotifier()),
        bitratePreferenceProvider.overrideWith(
          () => _StubBitratePreferenceNotifier(),
        ),
        deviceIdProvider.overrideWith((_) async => 'test-dev'),
      ]);
      addTearDown(c.dispose);

      // Simply reading the provider exercises lines 168-170.
      final value = c.read(playerDurationProvider);
      expect(value, isA<AsyncValue<Duration?>>());
    });
  });
}
