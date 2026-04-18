import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/backend_url_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/url_resolver.dart';
import '../layouts/breakpoints.dart';
import 'full_player.dart';

bool get _isDesktopOrWeb =>
    kIsWeb || (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));

class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  void _openFullPlayer(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= Breakpoints.desktop) {
      // On desktop, show as a dialog panel (centered, constrained width)
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 80,
            vertical: 24,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const SizedBox(
            width: 480,
            height: 700,
            child: FullPlayer(),
          ),
        ),
      );
    } else {
      // On mobile/tablet, keep the bottom sheet approach
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const FullPlayer(),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerNotifierProvider);
    final position = ref.watch(playerPositionProvider).valueOrNull;
    final duration = ref.watch(playerDurationProvider).valueOrNull;

    if (!playerState.hasTrack) return const SizedBox.shrink();

    final track = playerState.currentTrack!;
    final token = ref.watch(authServiceProvider).accessToken;
    final base = ref.watch(backendUrlProvider).valueOrNull;
    final headers = token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : <String, String>{};

    final progress = (position != null &&
            duration != null &&
            duration.inMilliseconds > 0)
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap: () => _openFullPlayer(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 2,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                // Album art thumbnail
                if (playerState.imageUrl != null && base != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: resolveBackendUrl(base, playerState.imageUrl!),
                      httpHeaders: headers,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 40,
                        height: 40,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 40,
                        height: 40,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Icon(Icons.music_note, size: 20),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.music_note, size: 20),
                  ),
                const SizedBox(width: 8),
                // Track info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (playerState.artistName != null)
                        Text(
                          playerState.artistName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // Play/pause button
                IconButton(
                  tooltip: playerState.isPlaying ? 'Pause' : 'Play',
                  icon: Icon(
                    playerState.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  onPressed: () {
                    final notifier =
                        ref.read(playerNotifierProvider.notifier);
                    if (playerState.isPlaying) {
                      notifier.pause();
                    } else {
                      notifier.resume();
                    }
                  },
                ),
                // Skip next
                IconButton(
                  tooltip: 'Skip next',
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: () =>
                      ref.read(playerNotifierProvider.notifier).skipNext(),
                ),
                if (_isDesktopOrWeb) const _VolumeControl(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeControl extends ConsumerWidget {
  const _VolumeControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(playerNotifierProvider.select((s) => s.volume));
    final notifier = ref.read(playerNotifierProvider.notifier);

    final icon = switch (volume) {
      0.0 => Icons.volume_off_rounded,
      < 0.5 => Icons.volume_down_rounded,
      _ => Icons.volume_up_rounded,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: volume > 0 ? 'Mute' : 'Unmute',
          icon: Icon(icon),
          onPressed: () => notifier.toggleMute(),
        ),
        SizedBox(
          width: 100,
          child: Slider(
            value: volume,
            onChanged: (v) => notifier.setVolume(v),
          ),
        ),
      ],
    );
  }
}
