import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/providers/player_provider.dart';
import 'package:bimusic_app/services/audio_service.dart';
import 'package:bimusic_app/ui/layouts/desktop_layout.dart';
import 'package:bimusic_app/ui/layouts/mobile_layout.dart';
import 'package:bimusic_app/ui/widgets/adaptive_scaffold.dart';
import 'package:bimusic_app/ui/widgets/player_bar.dart';

// ---------------------------------------------------------------------------
// Fakes / mocks
// ---------------------------------------------------------------------------

/// A simple fake StatefulNavigationShell that records the last branch tapped.
// ignore: must_be_immutable
class _FakeNavigationShell extends Fake implements StatefulNavigationShell {
  int lastBranchTapped = -1;

  @override
  int get currentIndex => 0;

  @override
  void goBranch(int index, {bool initialLocation = false}) {
    lastBranchTapped = index;
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_FakeNavigationShell';
}

class _MockAudioHandler extends Mock implements BiMusicAudioHandler {}

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

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

List<Override> _overrides(_MockAudioHandler handler) => [
      audioHandlerProvider.overrideWithValue(handler),
      playerNotifierProvider.overrideWith(() => _StubPlayerNotifier()),
    ];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(AudioServiceRepeatMode.none);
  });

  late _FakeNavigationShell shell;
  late _MockAudioHandler handler;

  setUp(() {
    shell = _FakeNavigationShell();
    handler = _MockAudioHandler();
  });

  group('MobileLayout', () {
    testWidgets('renders NavigationBar with 6 destinations', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(handler),
          child: MaterialApp(
            home: MobileLayout(
              navigationShell: shell,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('tapping a tab calls goBranch with the correct index',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(handler),
          child: MaterialApp(
            home: MobileLayout(
              navigationShell: shell,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Library'));
      await tester.pump();

      expect(shell.lastBranchTapped, 1);
    });

    testWidgets('does not show PlayerBar when no track is loaded',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(handler),
          child: MaterialApp(
            home: MobileLayout(
              navigationShell: shell,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(PlayerBar), findsNothing);
    });
  });

  group('DesktopLayout', () {
    testWidgets('renders sidebar with 6 navigation items', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(handler),
          child: MaterialApp(
            home: DesktopLayout(
              navigationShell: shell,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('tapping a sidebar item calls goBranch with the correct index',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(handler),
          child: MaterialApp(
            home: DesktopLayout(
              navigationShell: shell,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Search'));
      await tester.pump();

      expect(shell.lastBranchTapped, 2);
    });
  });

  group('AdaptiveScaffold', () {
    Widget buildWithSize(Size size, _FakeNavigationShell fakeShell,
        _MockAudioHandler audioHandler) {
      return ProviderScope(
        overrides: _overrides(audioHandler),
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: size),
              child: AdaptiveScaffold(
                navigationShell: fakeShell,
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows MobileLayout on narrow screen', (tester) async {
      await tester.pumpWidget(
          buildWithSize(const Size(800, 600), shell, handler));
      await tester.pump();

      expect(find.byType(MobileLayout), findsOneWidget);
      expect(find.byType(DesktopLayout), findsNothing);
    });

    testWidgets('shows DesktopLayout on wide screen', (tester) async {
      await tester.pumpWidget(
          buildWithSize(const Size(1400, 900), shell, handler));
      await tester.pump();

      expect(find.byType(DesktopLayout), findsOneWidget);
      expect(find.byType(MobileLayout), findsNothing);
    });

    testWidgets('shows DesktopLayout at exactly 1024px breakpoint',
        (tester) async {
      await tester.pumpWidget(
          buildWithSize(const Size(1024, 768), shell, handler));
      await tester.pump();

      expect(find.byType(DesktopLayout), findsOneWidget);
      expect(find.byType(MobileLayout), findsNothing);
    });
  });
}
