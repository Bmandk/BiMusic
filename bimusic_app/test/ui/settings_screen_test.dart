import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:bimusic_app/ui/screens/settings_screen.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockAudioHandler extends Mock implements BiMusicAudioHandler {}

// Notifier stubs ─────────────────────────────────────────────────────────────

class _StubAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  @override
  Future<void> get initialized async {}

  @override
  AuthState build() => const AuthStateAuthenticated(
        AuthTokens(
          accessToken: 'tok',
          refreshToken: 'rtok',
          user: User(userId: 'u1', username: 'testuser', isAdmin: false),
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

class _StubPlayerNotifier extends Notifier<PlayerState>
    implements PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> play(Track t, List<Track> q,
      {required String artistName,
      required String albumTitle,
      required String imageUrl}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seekTo(Duration p) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrev() async {}

  @override
  Future<void> setRepeat(AudioServiceRepeatMode m) async {}

  @override
  Future<void> toggleShuffle() async {}
}

class _StubBitratePreferenceNotifier extends BitratePreferenceNotifier {
  @override
  BitratePreference build() => BitratePreference.auto;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late _MockAuthService mockAuthService;
  late _MockAudioHandler mockHandler;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(AudioServiceRepeatMode.none);
  });

  setUp(() {
    mockAuthService = _MockAuthService();
    mockHandler = _MockAudioHandler();
    when(() => mockAuthService.accessToken).thenReturn('test_token');
  });

  Widget buildSubject() => ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((_) => mockAuthService),
          authNotifierProvider.overrideWith(() => _StubAuthNotifier()),
          downloadProvider.overrideWith(() => _StubDownloadNotifier()),
          audioHandlerProvider.overrideWithValue(mockHandler),
          playerNotifierProvider.overrideWith(() => _StubPlayerNotifier()),
          bitratePreferenceProvider
              .overrideWith(() => _StubBitratePreferenceNotifier()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      );

  testWidgets('renders Settings title', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('renders username', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('testuser'), findsOneWidget);
  });

  testWidgets('renders Sign Out option', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('renders Playback section', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('Playback'), findsOneWidget);
  });

  testWidgets('renders Streaming Quality tile', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    expect(find.text('Streaming Quality'), findsOneWidget);
  });
}
