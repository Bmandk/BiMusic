import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/player_provider.dart';
import '../../services/auth_service.dart';

class FullPlayer extends ConsumerStatefulWidget {
  const FullPlayer({super.key});

  @override
  ConsumerState<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends ConsumerState<FullPlayer> {
  double? _dragValue;

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerNotifierProvider);
    final positionAsync = ref.watch(playerPositionProvider);
    final durationAsync = ref.watch(playerDurationProvider);
    final token = ref.watch(authServiceProvider).accessToken;
    final headers = token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : <String, String>{};
    final colorScheme = Theme.of(context).colorScheme;

    final position =
        positionAsync.valueOrNull ?? Duration.zero;
    final duration =
        durationAsync.valueOrNull ?? Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final sliderValue =
        maxMs > 0 ? (_dragValue ?? posMs / maxMs) : 0.0;

    if (!playerState.hasTrack) {
      return const SizedBox(height: 200, child: Center(child: Text('Nothing playing')));
    }

    final track = playerState.currentTrack!;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (context, scrollController) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            playerState.albumTitle ?? '',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Album art
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: playerState.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: playerState.imageUrl!,
                          httpHeaders: headers,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (_, __, ___) => ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.album, size: 80),
                          ),
                        )
                      : ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.album, size: 80),
                        ),
                ),
              ),
              const SizedBox(height: 32),
              // Track title and artist
              Text(
                track.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                playerState.artistName ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              // Progress bar
              Slider(
                value: sliderValue.clamp(0.0, 1.0),
                onChanged: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  ref.read(playerNotifierProvider.notifier).seekTo(
                    Duration(
                      milliseconds: (v * maxMs).round(),
                    ),
                  );
                  setState(() => _dragValue = null);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(
                        _dragValue != null
                            ? Duration(
                                milliseconds:
                                    (_dragValue! * maxMs).round(),
                              )
                            : position,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      _formatDuration(duration),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Transport controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Shuffle
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: playerState.isShuffled
                          ? colorScheme.primary
                          : null,
                    ),
                    onPressed: () => ref
                        .read(playerNotifierProvider.notifier)
                        .toggleShuffle(),
                  ),
                  // Skip previous
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: () =>
                        ref.read(playerNotifierProvider.notifier).skipPrev(),
                  ),
                  // Play / pause
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(16),
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
                    child: Icon(
                      playerState.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 36,
                    ),
                  ),
                  // Skip next
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: () =>
                        ref.read(playerNotifierProvider.notifier).skipNext(),
                  ),
                  // Repeat
                  IconButton(
                    icon: Icon(
                      playerState.repeatMode == AudioServiceRepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: playerState.repeatMode != AudioServiceRepeatMode.none
                          ? colorScheme.primary
                          : null,
                    ),
                    onPressed: () {
                      final next = switch (playerState.repeatMode) {
                        AudioServiceRepeatMode.none =>
                          AudioServiceRepeatMode.group,
                        AudioServiceRepeatMode.group =>
                          AudioServiceRepeatMode.one,
                        _ => AudioServiceRepeatMode.none,
                      };
                      ref.read(playerNotifierProvider.notifier).setRepeat(next);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
