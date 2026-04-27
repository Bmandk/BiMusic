import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/backend_url_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/url_resolver.dart';

class FullPlayer extends ConsumerStatefulWidget {
  const FullPlayer({super.key, this.embedded = false});

  /// When true (desktop Dialog), skips the DraggableScrollableSheet wrapper
  /// and renders the Scaffold directly so the Dialog can size it naturally.
  final bool embedded;

  @override
  ConsumerState<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends ConsumerState<FullPlayer> {
  double? _dragValue;
  double? _seekTargetMs;
  Timer? _seekFallbackTimer;
  bool _showQueue = false;

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _seekFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerNotifierProvider);
    final positionAsync = ref.watch(playerPositionProvider);
    final durationAsync = ref.watch(playerDurationProvider);
    final token = ref.watch(authServiceProvider).accessToken;
    final base = ref.watch(backendUrlProvider).valueOrNull;
    final colorScheme = Theme.of(context).colorScheme;

    ref.listen<AsyncValue<Duration>>(playerPositionProvider, (_, next) {
      if (_seekTargetMs == null || !mounted) return;
      final ms = next.valueOrNull?.inMilliseconds.toDouble();
      if (ms != null && (ms - _seekTargetMs!).abs() < 500) {
        _seekFallbackTimer?.cancel();
        _seekTargetMs = null;
        setState(() => _dragValue = null);
      }
    });

    final position = positionAsync.valueOrNull ?? Duration.zero;
    final duration = durationAsync.valueOrNull ?? Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final sliderValue = maxMs > 0 ? (_dragValue ?? posMs / maxMs) : 0.0;

    if (!playerState.hasTrack) {
      return const SizedBox(height: 200, child: Center(child: Text('Nothing playing')));
    }

    final track = playerState.currentTrack!;

    final headers = token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : <String, String>{};

    if (widget.embedded) {
      return _buildEmbeddedContent(
        context, colorScheme, playerState, track,
        headers, base, position, duration, maxMs, sliderValue,
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (context, scrollController) => _buildScaffold(
        context, colorScheme, playerState, track,
        token, base, position, duration, maxMs, sliderValue, scrollController,
      ),
    );
  }

  Widget _buildEmbeddedContent(
    BuildContext context,
    ColorScheme colorScheme,
    PlayerState playerState,
    Track track,
    Map<String, String> headers,
    String? base,
    Duration position,
    Duration duration,
    double maxMs,
    double sliderValue,
  ) {
    // Size image to fit within the dialog without scrolling.
    // Dialog insets: 24 top + 24 bottom = 48 px consumed from screen height.
    // Fixed chrome height (header row + spacings + title/artist/slider/controls): ~320 px.
    final screenHeight = MediaQuery.sizeOf(context).height;
    const controlsFixedHeight = 320.0;
    const horizontalPadding = 64.0;
    const maxDialogContentWidth = 480.0 - horizontalPadding;
    final imageSize = ((screenHeight - 48) - controlsFixedHeight)
        .clamp(80.0, maxDialogContentWidth);

    final Widget albumArtWidget = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: imageSize,
        height: imageSize,
        child: playerState.imageUrl != null && base != null
            ? CachedNetworkImage(
                imageUrl: resolveBackendUrl(base, playerState.imageUrl!),
                httpHeaders: headers,
                fit: BoxFit.cover,
                placeholder: (_, __) => ColoredBox(
                  color: colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (_, __, ___) => ColoredBox(
                  color: colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.album, size: 64),
                ),
              )
            : ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.album, size: 64),
              ),
      ),
    );

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row — replaces AppBar so the Scaffold isn't needed
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Collapse player',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    playerState.albumTitle ?? '',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Up Next',
                  icon: Icon(
                    Icons.queue_music_rounded,
                    color: _showQueue ? colorScheme.primary : null,
                  ),
                  onPressed: () => setState(() => _showQueue = !_showQueue),
                ),
              ],
            ),
          ),
          if (_showQueue)
            SizedBox(
              height: 320,
              child: _QueuePanel(scrollController: null, playerState: playerState),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  albumArtWidget,
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 16),
                  Slider(
                    value: sliderValue.clamp(0.0, 1.0),
                    onChanged: (v) => setState(() => _dragValue = v),
                    onChangeEnd: (v) {
                      final targetMs = (v * maxMs).roundToDouble();
                      ref.read(playerNotifierProvider.notifier).seekTo(
                        Duration(milliseconds: targetMs.round()),
                      );
                      _seekFallbackTimer?.cancel();
                      _seekFallbackTimer = Timer(const Duration(milliseconds: 3000), () {
                        if (!mounted) return;
                        setState(() {
                          _seekTargetMs = null;
                          _dragValue = null;
                        });
                      });
                      setState(() {
                        _dragValue = v;
                        _seekTargetMs = targetMs;
                      });
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
                                ? Duration(milliseconds: (_dragValue! * maxMs).round())
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
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: playerState.isShuffled ? 'Shuffle on' : 'Shuffle off',
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: playerState.isShuffled ? colorScheme.primary : null,
                        ),
                        onPressed: () =>
                            ref.read(playerNotifierProvider.notifier).toggleShuffle(),
                      ),
                      IconButton(
                        tooltip: 'Skip previous',
                        iconSize: 40,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () =>
                            ref.read(playerNotifierProvider.notifier).skipPrev(),
                      ),
                      Semantics(
                        button: true,
                        label: playerState.isPlaying ? 'Pause' : 'Play',
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(16),
                          ),
                          onPressed: () {
                            final notifier = ref.read(playerNotifierProvider.notifier);
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
                      ),
                      IconButton(
                        tooltip: 'Skip next',
                        iconSize: 40,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () =>
                            ref.read(playerNotifierProvider.notifier).skipNext(),
                      ),
                      IconButton(
                        tooltip: switch (playerState.repeatMode) {
                          AudioServiceRepeatMode.none => 'Repeat off',
                          AudioServiceRepeatMode.group => 'Repeat all',
                          _ => 'Repeat one',
                        },
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
                            AudioServiceRepeatMode.none => AudioServiceRepeatMode.group,
                            AudioServiceRepeatMode.group => AudioServiceRepeatMode.one,
                            _ => AudioServiceRepeatMode.none,
                          };
                          ref.read(playerNotifierProvider.notifier).setRepeat(next);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    ColorScheme colorScheme,
    PlayerState playerState,
    Track track,
    String? token,
    String? base,
    Duration position,
    Duration duration,
    double maxMs,
    double sliderValue,
    ScrollController? scrollController,
  ) {
    final headers = token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : <String, String>{};

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Collapse player',
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
        actions: [
          IconButton(
            tooltip: 'Up Next',
            icon: Icon(
              Icons.queue_music_rounded,
              color: _showQueue ? colorScheme.primary : null,
            ),
            onPressed: () => setState(() => _showQueue = !_showQueue),
          ),
        ],
      ),
      body: _showQueue
          ? _QueuePanel(
              scrollController: scrollController,
              playerState: playerState,
            )
          : SingleChildScrollView(
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
                      child: playerState.imageUrl != null && base != null
                          ? CachedNetworkImage(
                              imageUrl: resolveBackendUrl(base, playerState.imageUrl!),
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
                      final targetMs = (v * maxMs).roundToDouble();
                      ref.read(playerNotifierProvider.notifier).seekTo(
                        Duration(milliseconds: targetMs.round()),
                      );
                      _seekFallbackTimer?.cancel();
                      _seekFallbackTimer = Timer(const Duration(milliseconds: 3000), () {
                        if (!mounted) return;
                        setState(() {
                          _seekTargetMs = null;
                          _dragValue = null;
                        });
                      });
                      setState(() {
                        _dragValue = v;
                        _seekTargetMs = targetMs;
                      });
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
                                ? Duration(milliseconds: (_dragValue! * maxMs).round())
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
                        tooltip: playerState.isShuffled ? 'Shuffle on' : 'Shuffle off',
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: playerState.isShuffled ? colorScheme.primary : null,
                        ),
                        onPressed: () =>
                            ref.read(playerNotifierProvider.notifier).toggleShuffle(),
                      ),
                      // Skip previous
                      IconButton(
                        tooltip: 'Skip previous',
                        iconSize: 40,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () =>
                            ref.read(playerNotifierProvider.notifier).skipPrev(),
                      ),
                      // Play / pause
                      Semantics(
                        button: true,
                        label: playerState.isPlaying ? 'Pause' : 'Play',
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(16),
                          ),
                          onPressed: () {
                            final notifier = ref.read(playerNotifierProvider.notifier);
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
                      ),
                      // Skip next
                      IconButton(
                        tooltip: 'Skip next',
                        iconSize: 40,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () =>
                            ref.read(playerNotifierProvider.notifier).skipNext(),
                      ),
                      // Repeat
                      IconButton(
                        tooltip: switch (playerState.repeatMode) {
                          AudioServiceRepeatMode.none => 'Repeat off',
                          AudioServiceRepeatMode.group => 'Repeat all',
                          _ => 'Repeat one',
                        },
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
                            AudioServiceRepeatMode.none => AudioServiceRepeatMode.group,
                            AudioServiceRepeatMode.group => AudioServiceRepeatMode.one,
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
    );
  }
}

/// Shows the current play queue with the active track highlighted.
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.scrollController,
    required this.playerState,
  });

  final ScrollController? scrollController;
  final PlayerState playerState;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final queue = playerState.queue;

    if (queue.isEmpty) {
      return Center(
        child: Text(
          'Queue is empty',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: queue.length,
      itemBuilder: (context, index) {
        final t = queue[index];
        final isCurrent = playerState.currentTrack?.id == t.id;
        return ListTile(
          leading: isCurrent
              ? Icon(Icons.equalizer_rounded, color: colorScheme.primary)
              : const Icon(Icons.music_note_outlined),
          title: Text(
            t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isCurrent ? FontWeight.bold : null,
              color: isCurrent ? colorScheme.primary : null,
            ),
          ),
          subtitle: Text(
            playerState.artistName ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }
}
