import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/models/user.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/providers/download_provider.dart';
import 'package:bimusic_app/providers/player_provider.dart';
import 'package:bimusic_app/router.dart';
import 'package:bimusic_app/services/audio_service.dart';
import 'package:bimusic_app/services/auth_service.dart';

// ---------------------------------------------------------------------------
// Stubs / mocks
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  _StubAuthNotifier(this._state);
  final AuthState _state;

  @override
  Future<void> get initialized async {}

  @override
  AuthState build() => _state;

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}
}

class _MockAudioHandler extends Mock implements BiMusicAudioHandler {}

class _StubPlayerNotifier extends Notifier<PlayerState>
    implements PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> play(
    Track t,
    List<Track> q, {
    required String artistName,
    required String albumTitle,
    required String imageUrl,
  }) async {}

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

class _StubDownloadNotifier extends DownloadNotifier {
  @override
  DownloadState build() =>
      const DownloadState(tasks: [], isLoading: false, deviceId: 'test-dev');
}

class _MockAuthService extends Mock implements AuthService {}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _testUser = User(userId: 'u1', username: 'testuser', isAdmin: false);

const _testTokens = AuthTokens(
  accessToken: 'access',
  refreshToken: 'refresh',
  user: _testUser,
);

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

List<Override> _baseOverrides(
  AuthState authState,
  _MockAudioHandler handler,
  _MockAuthService authService,
) =>
    [
      authNotifierProvider.overrideWith(() => _StubAuthNotifier(authState)),
      authServiceProvider.overrideWith((_) => authService),
      audioHandlerProvider.overrideWithValue(handler),
      playerNotifierProvider.overrideWith(() => _StubPlayerNotifier()),
      playerPositionProvider.overrideWith((_) => Stream.value(Duration.zero)),
      playerDurationProvider.overrideWith((_) => Stream.value(null)),
      downloadProvider.overrideWith(() => _StubDownloadNotifier()),
    ];

Widget _buildRouter(
  AuthState authState,
  _MockAudioHandler handler,
  _MockAuthService authService,
) {
  return ProviderScope(
    overrides: _baseOverrides(authState, handler, authService),
    child: Consumer(
      builder: (context, ref, _) {
        final router = ref.watch(routerProvider);
        return MaterialApp.router(
          routerConfig: router,
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockAudioHandler handler;
  late _MockAuthService authService;

  setUpAll(() {
    registerFallbackValue(AudioServiceRepeatMode.none);
  });

  setUp(() {
    handler = _MockAudioHandler();
    authService = _MockAuthService();
    when(() => authService.accessToken).thenReturn('test-token');
  });

  group('routerProvider redirect — unauthenticated', () {
    testWidgets('redirects to /login when not authenticated', (tester) async {
      await tester.pumpWidget(
        _buildRouter(const AuthStateUnauthenticated(), handler, authService),
      );
      await tester.pumpAndSettle();

      // The router starts at /login; LoginScreen shows "BiMusic".
      expect(find.text('BiMusic'), findsOneWidget);
    });

    testWidgets('stays on /login when already on login route', (tester) async {
      await tester.pumpWidget(
        _buildRouter(const AuthStateUnauthenticated(), handler, authService),
      );
      await tester.pumpAndSettle();

      // No redirect loop — still showing login.
      expect(find.text('BiMusic'), findsOneWidget);
    });
  });

  group('routerProvider redirect — loading', () {
    testWidgets('does not crash while auth is loading', (tester) async {
      await tester.pumpWidget(
        _buildRouter(const AuthStateLoading(), handler, authService),
      );
      await tester.pump();

      // With loading state no redirect fires — just verify no crash.
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('routerProvider redirect — authenticated', () {
    testWidgets('redirects away from /login when authenticated',
        (tester) async {
      await tester.pumpWidget(
        _buildRouter(
          const AuthStateAuthenticated(_testTokens),
          handler,
          authService,
        ),
      );
      await tester.pumpAndSettle();

      // Authenticated users at /login redirect to /home.
      expect(find.text('Home'), findsAtLeastNWidgets(1));
    });
  });

  group('routerProvider — provider is stable', () {
    testWidgets('routerProvider returns a GoRouter instance', (tester) async {
      late GoRouter router;
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            const AuthStateUnauthenticated(),
            handler,
            authService,
          ),
          child: Consumer(
            builder: (context, ref, _) {
              router = ref.watch(routerProvider);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(router, isA<GoRouter>());
    });
  });
}
