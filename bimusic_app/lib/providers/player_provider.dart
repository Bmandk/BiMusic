import 'dart:async';
import 'dart:developer' as dev;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/download_task.dart';
import '../models/track.dart';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import 'auth_provider.dart';
import 'backend_config_provider.dart';
import 'backend_url_provider.dart';
import 'bitrate_provider.dart';
import 'download_provider.dart';

class PlayerState {
  const PlayerState({
    this.currentTrack,
    this.queue = const [],
    this.isPlaying = false,
    this.repeatMode = AudioServiceRepeatMode.none,
    this.isShuffled = false,
    this.artistName,
    this.albumTitle,
    this.imageUrl,
    this.volume = 1.0,
  });

  final Track? currentTrack;
  final List<Track> queue;
  final bool isPlaying;
  final AudioServiceRepeatMode repeatMode;
  final bool isShuffled;
  final String? artistName;
  final String? albumTitle;
  final String? imageUrl;
  final double volume;

  bool get hasTrack => currentTrack != null;

  PlayerState copyWith({
    Track? currentTrack,
    List<Track>? queue,
    bool? isPlaying,
    AudioServiceRepeatMode? repeatMode,
    bool? isShuffled,
    String? artistName,
    String? albumTitle,
    String? imageUrl,
    double? volume,
  }) {
    return PlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      queue: queue ?? this.queue,
      isPlaying: isPlaying ?? this.isPlaying,
      repeatMode: repeatMode ?? this.repeatMode,
      isShuffled: isShuffled ?? this.isShuffled,
      artistName: artistName ?? this.artistName,
      albumTitle: albumTitle ?? this.albumTitle,
      imageUrl: imageUrl ?? this.imageUrl,
      volume: volume ?? this.volume,
    );
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  static const _kVolumeStorageKey = 'bimusic_player_volume';

  double _preMuteVolume = 1.0;
  Timer? _volumePersistDebounce;

  @override
  PlayerState build() {
    final handler = ref.read(audioHandlerProvider);

    // When the access token is silently refreshed, update the audio sources so
    // libmpv never replays a request with an expired token.
    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (next is! AuthStateAuthenticated) return;
      final prevToken = prev is AuthStateAuthenticated
          ? prev.tokens.accessToken
          : null;
      if (prevToken == next.tokens.accessToken) return;
      handler.updateToken(next.tokens.accessToken).catchError((_) {});
    });

    // skip(1) avoids the synchronous BehaviorSubject emission during build
    final playbackSub = handler.playbackState.skip(1).listen((ps) {
      state = state.copyWith(
        isPlaying: ps.playing,
        repeatMode: ps.repeatMode,
        isShuffled: ps.shuffleMode != AudioServiceShuffleMode.none,
      );
    });

    final indexSub = handler.mediaItem.skip(1).listen((item) {
      if (item == null) return;
      final tracks = handler.currentTracks;
      final match = tracks.cast<Track?>().firstWhere(
        (t) => item.id.contains('/${t!.id}?') || item.id.endsWith('/${t.id}'),
        orElse: () => null,
      );
      if (match != null && match != state.currentTrack) {
        state = state.copyWith(currentTrack: match);
      }
    });

    ref.onDispose(() {
      playbackSub.cancel();
      indexSub.cancel();
      _volumePersistDebounce?.cancel();
    });

    _loadPersistedVolume();
    return const PlayerState();
  }

  Future<void> _loadPersistedVolume() async {
    // Yield so build() returns and Riverpod initializes state before we read it.
    // Without this, accessing state.volume here throws "uninitialized provider"
    // because build() hasn't returned yet.
    await Future<void>.value();
    dev.log('[Volume] _loadPersistedVolume: start, current state.volume=${state.volume}');
    try {
      // Capture the default volume before the async read so we can detect
      // whether the user already changed it while we were waiting.
      final volumeBeforeLoad = state.volume;
      const storage = FlutterSecureStorage();
      dev.log('[Volume] _loadPersistedVolume: reading from storage...');
      final value = await storage.read(key: _kVolumeStorageKey);
      dev.log('[Volume] _loadPersistedVolume: storage read returned: $value');
      if (value == null) {
        dev.log('[Volume] _loadPersistedVolume: no stored value, using default');
        return;
      }
      final v = double.tryParse(value);
      if (v == null) {
        dev.log('[Volume] _loadPersistedVolume: could not parse "$value" as double');
        return;
      }
      final clamped = v.clamp(0.0, 1.0);
      // Only apply if the user hasn't already changed the volume.
      if (state.volume != volumeBeforeLoad) {
        dev.log('[Volume] _loadPersistedVolume: user changed volume during load (${state.volume} != $volumeBeforeLoad), skipping');
        return;
      }
      dev.log('[Volume] _loadPersistedVolume: applying volume=$clamped');
      state = state.copyWith(volume: clamped);
      if (clamped > 0) _preMuteVolume = clamped;
      await ref.read(audioHandlerProvider).setVolume(clamped);
      dev.log('[Volume] _loadPersistedVolume: backend setVolume($clamped) done');
    } catch (e, st) {
      dev.log('[Volume] _loadPersistedVolume: ERROR: $e\n$st');
    }
  }

  Future<void> play(
    Track track,
    List<Track> queue, {
    required String artistName,
    required String albumTitle,
    required String imageUrl,
  }) async {
    final handler = ref.read(audioHandlerProvider);
    final token = ref.read(authServiceProvider).accessToken;
    final bitrate = ref.read(bitrateProvider);
    final baseUrl = ref.read(backendUrlProvider).valueOrNull ?? '';
    final segmentSeconds = ref.read(backendConfigProvider).valueOrNull ?? 6;
    final startIndex = queue.indexOf(track);

    state = state.copyWith(
      currentTrack: track,
      queue: queue,
      isPlaying: true,
      artistName: artistName,
      albumTitle: albumTitle,
      imageUrl: imageUrl,
    );

    // Resolve any locally-stored files for offline-capable tracks.
    final localFilePaths = <int, String>{};
    if (!kIsWeb) {
      final downloads = ref.read(downloadProvider).tasks;
      for (final t in queue) {
        final local = downloads.where(
          (d) =>
              d.trackId == t.id &&
              d.status == DownloadStatus.completed &&
              d.filePath != null,
        );
        if (local.isNotEmpty) localFilePaths[t.id] = local.first.filePath!;
      }
    }

    await handler.playQueue(
      queue,
      startIndex < 0 ? 0 : startIndex,
      token,
      bitrate,
      baseUrl: baseUrl,
      artistName: artistName,
      albumTitle: albumTitle,
      imageUrl: imageUrl,
      localFilePaths: localFilePaths,
      segmentSeconds: segmentSeconds,
    );
  }

  Future<void> pause() => ref.read(audioHandlerProvider).pause();
  Future<void> resume() => ref.read(audioHandlerProvider).play();
  Future<void> seekTo(Duration position) =>
      ref.read(audioHandlerProvider).seek(position);
  Future<void> skipNext() => ref.read(audioHandlerProvider).skipToNext();
  Future<void> skipPrev() => ref.read(audioHandlerProvider).skipToPrevious();

  Future<void> setRepeat(AudioServiceRepeatMode mode) =>
      ref.read(audioHandlerProvider).setRepeatMode(mode);

  Future<void> toggleShuffle() {
    final newMode = state.isShuffled
        ? AudioServiceShuffleMode.none
        : AudioServiceShuffleMode.all;
    return ref.read(audioHandlerProvider).setShuffleMode(newMode);
  }

  Future<void> adjustVolumeBy(double delta) =>
      setVolume(state.volume + delta);

  Future<void> setVolume(double v) async {
    final clamped = v.clamp(0.0, 1.0);
    dev.log('[Volume] setVolume: requested=$v clamped=$clamped');
    state = state.copyWith(volume: clamped);
    await ref.read(audioHandlerProvider).setVolume(clamped);
    // Skip persistence if a newer call has already moved state forward.
    if (state.volume != clamped) {
      dev.log('[Volume] setVolume: stale call (state.volume=${state.volume} != $clamped), skipping persistence');
      return;
    }
    _volumePersistDebounce?.cancel();
    _volumePersistDebounce = Timer(const Duration(milliseconds: 250), () {
      dev.log('[Volume] setVolume: debounce fired, writing $clamped to storage');
      const FlutterSecureStorage()
          .write(key: _kVolumeStorageKey, value: clamped.toString())
          .then((_) => dev.log('[Volume] setVolume: storage write succeeded'))
          .catchError((Object e) {
        dev.log('[Volume] setVolume: storage write FAILED: $e');
      });
    });
    dev.log('[Volume] setVolume: debounce timer armed for $clamped');
  }

  Future<void> toggleMute() async {
    if (state.volume > 0) {
      _preMuteVolume = state.volume;
      await setVolume(0);
    } else {
      await setVolume(_preMuteVolume == 0 ? 1.0 : _preMuteVolume);
    }
  }
}

final playerNotifierProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);

/// Position stream for the progress bar — kept separate to avoid
/// rebuilding the full player state on every tick.
final playerPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(audioHandlerProvider).positionStream;
});

/// Duration of the current track.
final playerDurationProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(audioHandlerProvider).durationStream;
});
