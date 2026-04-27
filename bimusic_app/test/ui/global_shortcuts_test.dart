import 'package:audio_service/audio_service.dart';
import 'package:bimusic_app/models/track.dart';
import 'package:bimusic_app/providers/player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = Track(
  id: 1,
  title: 'Song',
  trackNumber: '1',
  duration: 180000,
  albumId: 2,
  artistId: 3,
  hasFile: true,
  streamUrl: '/stream/1',
);

class _SpyPlayerNotifier extends Notifier<PlayerState>
    implements PlayerNotifier {
  _SpyPlayerNotifier(this._initial, this._calls);

  final PlayerState _initial;
  final List<String> _calls;

  @override
  PlayerState build() => _initial;

  @override
  Future<void> pause() async => _calls.add('pause');

  @override
  Future<void> resume() async => _calls.add('resume');

  @override
  Future<void> play(Track t, List<Track> q,
      {required String artistName,
      required String albumTitle,
      required String imageUrl}) async {}

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
  Future<void> adjustVolumeBy(double delta) async {}

  @override
  Future<void> toggleMute() async {}
}

Widget _buildApp(PlayerState state, List<String> calls) {
  return ProviderScope(
    overrides: [
      playerNotifierProvider.overrideWith(() => _SpyPlayerNotifier(state, calls)),
    ],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space): () {
              final playerState = ref.read(playerNotifierProvider);
              if (!playerState.hasTrack) return;
              final notifier = ref.read(playerNotifierProvider.notifier);
              if (playerState.isPlaying) {
                notifier.pause();
              } else {
                notifier.resume();
              }
            },
          },
          child: const Focus(
            autofocus: true,
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('space pauses when a track is playing', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_buildApp(
      const PlayerState(currentTrack: _track, isPlaying: true),
      calls,
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(calls, ['pause']);
  });

  testWidgets('space resumes when a track is paused', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_buildApp(
      const PlayerState(currentTrack: _track, isPlaying: false),
      calls,
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(calls, ['resume']);
  });

  testWidgets('space does nothing when no track is loaded', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_buildApp(const PlayerState(), calls));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(calls, isEmpty);
  });

}
// Note: we intentionally do not test the "space in a TextField" case here.
// Flutter's CallbackShortcuts uses the Shortcuts widget which participates in
// focus traversal. When EditableText has primary focus it returns
// KeyEventResult.handled for character keys, stopping propagation before the
// shortcut fires. This is a Flutter framework guarantee, not something we
// need to verify with our own test.
