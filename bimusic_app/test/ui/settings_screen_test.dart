import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
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

// ---------------------------------------------------------------------------
// Notifier stubs
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  _StubAuthNotifier({this.isAdmin = false});
  final bool isAdmin;

  @override
  Future<void> get initialized async {}

  @override
  AuthState build() => AuthStateAuthenticated(
        AuthTokens(
          accessToken: 'tok',
          refreshToken: 'rtok',
          user: User(
            userId: 'u1',
            username: 'testuser',
            isAdmin: isAdmin,
          ),
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
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> toggleMute() async {}
}

class _StubBitratePreferenceNotifier extends BitratePreferenceNotifier {
  _StubBitratePreferenceNotifier([this._pref = BitratePreference.auto]);
  final BitratePreference _pref;

  @override
  BitratePreference build() => _pref;

  @override
  Future<void> setPreference(BitratePreference pref) async {
    state = pref;
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildSubject({
  bool isAdmin = false,
  BitratePreference bitratePref = BitratePreference.auto,
  _MockAuthService? authService,
  _MockAudioHandler? handler,
}) {
  final mockAuth = authService ?? _MockAuthService();
  final mockHandler = handler ?? _MockAudioHandler();
  when(() => mockAuth.accessToken).thenReturn('test_token');

  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWith((_) => mockAuth),
      authNotifierProvider
          .overrideWith(() => _StubAuthNotifier(isAdmin: isAdmin)),
      downloadProvider.overrideWith(() => _StubDownloadNotifier()),
      audioHandlerProvider.overrideWithValue(mockHandler),
      playerNotifierProvider.overrideWith(() => _StubPlayerNotifier()),
      bitratePreferenceProvider
          .overrideWith(() => _StubBitratePreferenceNotifier(bitratePref)),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(AudioServiceRepeatMode.none);
  });

  testWidgets('renders Settings title', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('renders username', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('testuser'), findsOneWidget);
  });

  testWidgets('renders Sign Out option', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('renders Playback section', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('Playback'), findsOneWidget);
  });

  testWidgets('renders Streaming Quality tile', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('Streaming Quality'), findsOneWidget);
  });

  testWidgets('renders Account section header', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('Account'), findsOneWidget);
  });

  testWidgets('renders About section', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    // About section is at the bottom of the ListView — scroll to reveal it.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('renders App Version tile', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('App Version'), findsOneWidget);
  });

  testWidgets('renders Backend URL tile', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('Backend URL'), findsOneWidget);
  });

  testWidgets('renders Open Source Licenses tile', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('Open Source Licenses'), findsOneWidget);
  });

  testWidgets('renders Offline Downloads section on non-web', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('Offline Downloads'), findsOneWidget);
  });

  testWidgets('renders Offline Music storage tile', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('Offline Music'), findsOneWidget);
  });

  testWidgets('renders Clear All Downloads tile', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('Clear All Downloads'), findsOneWidget);
  });

  testWidgets('does NOT render Debug section for non-admin user', (tester) async {
    await tester.pumpWidget(_buildSubject(isAdmin: false));
    await tester.pump();
    expect(find.text('Debug'), findsNothing);
    expect(find.text('Backend'), findsNothing);
    expect(find.text('View Logs'), findsNothing);
  });

  testWidgets('shows auto bitrate label when preference is auto', (tester) async {
    await tester.pumpWidget(
      _buildSubject(bitratePref: BitratePreference.auto),
    );
    await tester.pump();
    expect(
      find.textContaining('Automatic'),
      findsOneWidget,
    );
  });

  testWidgets('shows always low label when preference is alwaysLow',
      (tester) async {
    await tester.pumpWidget(
      _buildSubject(bitratePref: BitratePreference.alwaysLow),
    );
    await tester.pump();
    expect(find.textContaining('Always Low'), findsOneWidget);
  });

  testWidgets('shows always high label when preference is alwaysHigh',
      (tester) async {
    await tester.pumpWidget(
      _buildSubject(bitratePref: BitratePreference.alwaysHigh),
    );
    await tester.pump();
    expect(find.textContaining('Always High'), findsOneWidget);
  });

  testWidgets('tapping Sign Out shows confirmation dialog', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    expect(find.text('Are you sure? Offline downloads on this device will be kept.'),
        findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('cancelling logout dialog closes it without action',
      (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Dialog is gone, still on settings screen.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Are you sure?'), findsNothing);
  });

  testWidgets('tapping Streaming Quality opens picker dialog', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();

    await tester.tap(find.text('Streaming Quality'));
    await tester.pumpAndSettle();

    // SimpleDialog with title "Streaming Quality" should appear.
    expect(find.text('Streaming Quality'), findsWidgets);
    // All three options should be listed.
    expect(find.textContaining('Automatic'), findsWidgets);
    expect(find.textContaining('Always Low'), findsWidgets);
    expect(find.textContaining('Always High'), findsWidgets);
  });

  testWidgets('tapping Clear All Downloads shows confirmation dialog',
      (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();

    await tester.tap(find.text('Clear All Downloads'));
    await tester.pumpAndSettle();

    expect(find.text('Clear All Downloads'), findsWidgets);
    expect(find.text('Remove all offline downloads from this device? This cannot be undone.'),
        findsOneWidget);
  });

  testWidgets('Crossfade tile is visible but disabled', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pump();
    expect(find.text('Crossfade'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });
}
