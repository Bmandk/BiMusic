import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_provider.dart';

class GlobalShortcutsWrapper extends ConsumerWidget {
  const GlobalShortcutsWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false): () {
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
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}
