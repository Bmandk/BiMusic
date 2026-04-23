// coverage:ignore-file
import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import '../models/track.dart';
import 'hls_seek_utils.dart';

// ---------------------------------------------------------------------------
// Platform-agnostic player backend abstraction
// ---------------------------------------------------------------------------

enum _LoopMode { off, one, all }

abstract class _PlayerBackend {
  /// Called once during BiMusicAudioHandler._init(). Performs any async setup
  /// (e.g. libmpv property configuration) before stream subscriptions are wired.
  Future<void> init();

  // Streams
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<int?> get indexStream;
  Stream<AudioProcessingState> get processingStateStream;

  // Synchronous state (read in _broadcastState)
  bool get playing;
  AudioProcessingState get processingState;
  Duration get position;
  Duration get bufferedPosition;
  double get speed;
  int? get currentIndex;
  bool get hasNext;
  bool get hasPrevious;

  // Control
  ///
  /// [durations] carries the caller-known duration of each track. The
  /// media_kit backend uses these as the authoritative track duration
  /// because libmpv's reported duration on Windows is the current HLS
  /// segment's duration (6s), not the full track. just_audio ignores it.
  Future<void> openQueue(
    List<Uri> uris,
    int initialIndex, {
    List<Duration>? durations,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seekTo(Duration pos, {int? index});
  Future<void> seekToNext();
  Future<void> seekToPrevious();
  Future<void> jumpTo(int index);
  Future<void> setVolume(double v);
  Future<void> setLoopMode(_LoopMode mode);
  Future<void> setShuffle(bool enabled);
  void updateSegmentDuration(Duration d);
}

// ---------------------------------------------------------------------------
// just_audio backend — iOS / Android / web
// ---------------------------------------------------------------------------

class _JustAudioBackend implements _PlayerBackend {
  final AudioPlayer _p = AudioPlayer();

  static const _stateMap = {
    ProcessingState.idle: AudioProcessingState.idle,
    ProcessingState.loading: AudioProcessingState.loading,
    ProcessingState.buffering: AudioProcessingState.buffering,
    ProcessingState.ready: AudioProcessingState.ready,
    ProcessingState.completed: AudioProcessingState.completed,
  };

  @override
  Future<void> init() async {}

  @override
  Stream<bool> get playingStream =>
      _p.playerStateStream.map((s) => s.playing);

  @override
  Stream<Duration> get positionStream => _p.positionStream;

  @override
  Stream<Duration?> get durationStream => _p.durationStream;

  @override
  Stream<int?> get indexStream => _p.currentIndexStream;

  @override
  Stream<AudioProcessingState> get processingStateStream =>
      _p.playerStateStream.map(
        (s) => _stateMap[s.processingState] ?? AudioProcessingState.idle,
      );

  @override
  bool get playing => _p.playing;

  @override
  AudioProcessingState get processingState =>
      _stateMap[_p.processingState] ?? AudioProcessingState.idle;

  @override
  Duration get position => _p.position;

  @override
  Duration get bufferedPosition => _p.bufferedPosition;

  @override
  double get speed => _p.speed;

  @override
  int? get currentIndex => _p.currentIndex;

  @override
  bool get hasNext => _p.hasNext;

  @override
  bool get hasPrevious => _p.hasPrevious;

  @override
  Future<void> openQueue(
    List<Uri> uris,
    int initialIndex, {
    List<Duration>? durations,
  }) async {
    // durations ignored — just_audio's native backends (AVPlayer / ExoPlayer /
    // HTML Audio) handle HLS as a single continuous source and report correct
    // track durations on their own.
    final sources = uris.map((u) {
      if (u.scheme == 'file') return AudioSource.file(u.toFilePath());
      return AudioSource.uri(u);
    }).toList();
    await _p.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: initialIndex,
      preload: false,
    );
  }

  @override
  Future<void> play() => _p.play();

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> stop() => _p.stop();

  @override
  Future<void> seekTo(Duration pos, {int? index}) => _p.seek(pos, index: index);

  @override
  Future<void> seekToNext() => _p.seekToNext();

  @override
  Future<void> seekToPrevious() => _p.seekToPrevious();

  @override
  Future<void> jumpTo(int index) => _p.seek(Duration.zero, index: index);

  @override
  Future<void> setVolume(double v) => _p.setVolume(v);

  @override
  Future<void> setLoopMode(_LoopMode mode) => _p.setLoopMode(const {
        _LoopMode.off: LoopMode.off,
        _LoopMode.one: LoopMode.one,
        _LoopMode.all: LoopMode.all,
      }[mode]!);

  @override
  Future<void> setShuffle(bool enabled) => _p.setShuffleModeEnabled(enabled);

  @override
  void updateSegmentDuration(Duration d) {}
}

// ---------------------------------------------------------------------------
// HLS queue state value object
// ---------------------------------------------------------------------------

// Groups all per-queue mutable state into one object so updates are atomic.
// Replace `_queue` with a new `_QueueState` instance; never mutate fields in place.
class _QueueState {
  const _QueueState({
    this.uris = const [],
    this.durations = const [],
    this.startSegments = const {},
    this.segmentOffset = Duration.zero,
    this.currentIndex,
  });

  final List<Uri> uris;
  final List<Duration> durations;
  // Per-track segment index override (key = queue index, value = segment number).
  final Map<int, int> startSegments;
  final Duration segmentOffset;
  final int? currentIndex;

  int get length => uris.length;

  _QueueState withCurrentIndex(int? index) => _QueueState(
        uris: uris,
        durations: durations,
        startSegments: startSegments,
        segmentOffset: segmentOffset,
        currentIndex: index,
      );

  _QueueState withSegmentOffset(Duration offset) => _QueueState(
        uris: uris,
        durations: durations,
        startSegments: startSegments,
        segmentOffset: offset,
        currentIndex: currentIndex,
      );

  _QueueState withStartSegment(int trackIndex, int segment) => _QueueState(
        uris: uris,
        durations: durations,
        startSegments: {...startSegments, trackIndex: segment},
        segmentOffset: segmentOffset,
        currentIndex: currentIndex,
      );

  // Drop all seek overrides and reset offset — used when jumping to a new track.
  _QueueState resetNavigation() => _QueueState(
        uris: uris,
        durations: durations,
        startSegments: const {},
        segmentOffset: Duration.zero,
        currentIndex: currentIndex,
      );
}

// ---------------------------------------------------------------------------
// media_kit backend — Windows / Linux
// ---------------------------------------------------------------------------

class _MediaKitBackend implements _PlayerBackend {
  // warn-level mpv logs — surfaces errors and warnings without the per-frame
  // firehose of debug. Bump to MPVLogLevel.debug when diagnosing streaming
  // issues.
  final Player _p = Player(
    configuration: const PlayerConfiguration(
      logLevel: MPVLogLevel.warn,
    ),
  );

  AudioProcessingState _ps = AudioProcessingState.idle;
  final _psCtrl = StreamController<AudioProcessingState>.broadcast();

  // Queue and per-track HLS seek state, consolidated into a single value object
  // so every update is atomic — see _QueueState above.
  //
  // mpv's native playlist demuxer flattens HLS into per-segment entries and
  // advances `playlist-pos` every 6 s; we observe the current file URL via
  // `path`, match it back to our original queue by track ID, and derive a
  // track-relative position as segmentOffset + mpv's in-segment position.
  //
  // Index and duration use BehaviorSubject so late Riverpod subscribers
  // (widgets built after playback started) still receive the most recent value.
  _QueueState _queue = const _QueueState();
  final _indexCtrl = BehaviorSubject<int?>();
  final _durationCtrl = BehaviorSubject<Duration?>();

  // Authoritative value comes from GET /api/health → segmentSeconds (default 6).
  // Updated before every playQueue call via updateSegmentDuration().
  Duration _segmentDuration = const Duration(seconds: 6);

  bool _isShuffled = false;

  static final _segmentIndexPattern = RegExp(r'/segment/(\d+)');

  void _emit(AudioProcessingState s) {
    _ps = s;
    _psCtrl.add(s);
  }

  Future<void> _tryProperty(NativePlayer np, String key, String value) async {
    try {
      await np.setProperty(key, value);
    } catch (e, st) {
      dev.log('[BiMusicAudio][mpv-set] $key = $value FAILED: $e\n$st');
    }
  }

  /// Reverse-lookup the current mpv file URL into our original queue index.
  int? _matchUriToQueueIndex(String path) =>
      matchHlsUriToQueueIndex(path, _queue.uris);

  Future<void> _updateFromPath(String path) async {
    final matched = _matchUriToQueueIndex(path);
    final segMatch = _segmentIndexPattern.firstMatch(path);
    final trackChanged = matched != null && matched != _queue.currentIndex;

    if (trackChanged) {
      _queue = _queue.withCurrentIndex(matched).withSegmentOffset(Duration.zero);
      final logUri = Uri.tryParse(path);
      final safePath = logUri != null
          ? logUri.replace(
              queryParameters: {
                for (final e in logUri.queryParameters.entries)
                  e.key: e.key == 'token' ? '[REDACTED]' : e.value,
              },
            ).toString()
          : path;
      dev.log('[BiMusicAudio] track change: index=$matched path=$safePath');
      _indexCtrl.add(matched);
      if (matched < _queue.durations.length &&
          _queue.durations[matched] > Duration.zero) {
        _durationCtrl.add(_queue.durations[matched]);
      }
    } else if (segMatch != null) {
      _queue = _queue.withSegmentOffset(
        _segmentDuration * int.parse(segMatch.group(1)!),
      );
    }
  }

  /// Build the Media URL for queue index [i], applying any `startSegment`
  /// override. File URIs are returned unchanged.
  Uri _resolveUri(int i) {
    final uri = _queue.uris[i];
    final start = _queue.startSegments[i];
    if (start == null || start == 0) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'startSegment': '$start',
    });
  }

  /// Reopen the full queue at [index], applying any `startSegment` overrides
  /// and preserving the playing state. [withinSegment] is passed to mpv as
  /// the target Media's `start` property — mpv sets this via
  /// `mpv_set_property_string("start", ...)` before the file loads, so the
  /// demuxer positions itself atomically on load. A follow-up `_p.seek()` at
  /// this point would race the demuxer and be rejected with
  /// "error running command _command(seek, X, absolute)".
  Future<void> _reopenQueueAt(int index, Duration withinSegment) async {
    final wasPlaying = _p.state.playing;
    _queue = _queue.withCurrentIndex(index);
    _indexCtrl.add(index);
    if (index < _queue.durations.length &&
        _queue.durations[index] > Duration.zero) {
      _durationCtrl.add(_queue.durations[index]);
    }

    final medias = List<Media>.generate(
      _queue.uris.length,
      (i) {
        final uri = _resolveUri(i).toString();
        final start = (i == index && withinSegment > Duration.zero)
            ? withinSegment
            : null;
        return Media(uri, start: start);
      },
      growable: false,
    );
    _emit(AudioProcessingState.loading);
    await _p.open(Playlist(medias, index: index), play: wasPlaying);
  }

  @override
  Future<void> init() async {
    if (_p.platform is NativePlayer) {
      final np = _p.platform as NativePlayer;
      // Allows HLS segment URLs fetched through a playlist.
      await _tryProperty(np, 'load-unsafe-playlists', 'yes');
      // Redirect the mpv stream cache to the OS temp dir.
      // The native HLS demuxer creates temp files for segment caching; on
      // Windows the default /tmp/ path doesn't exist, causing "Failed to
      // create file cache". A valid cache-dir fixes this.
      await _tryProperty(np, 'cache-dir', Directory.systemTemp.path);

      // `path` is the currently-open file URL inside mpv. When mpv's native
      // playlist demuxer expands an HLS playlist, `path` changes to each
      // segment URL in turn — all still carry our track ID, so we can
      // reverse-lookup them. Initial observe-fire (before any file is open)
      // arrives with an empty string which we harmlessly ignore.
      await np.observeProperty('path', _updateFromPath);
    }

    _p.stream.log.listen((log) => dev.log(
          '[BiMusicAudio][mpv][${log.level}][${log.prefix}] ${log.text}',
        ));

    _p.stream.buffering.listen(
      (buffering) => _emit(
        buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      ),
    );
    _p.stream.completed.listen((done) {
      if (done) _emit(AudioProcessingState.completed);
    });
    _p.stream.error.listen((err) {
      if (err.isNotEmpty) dev.log('[BiMusicAudio] media_kit error: $err');
    });
  }

  @override
  Future<void> openQueue(
    List<Uri> uris,
    int initialIndex, {
    List<Duration>? durations,
  }) async {
    _queue = _QueueState(
      uris: uris,
      durations: durations ?? const [],
      currentIndex: initialIndex,
    );
    _indexCtrl.add(initialIndex);
    if (initialIndex < _queue.durations.length &&
        _queue.durations[initialIndex] > Duration.zero) {
      _durationCtrl.add(_queue.durations[initialIndex]);
    }

    dev.log(
      '[BiMusicAudio] openQueue: initialIndex=$initialIndex count=${uris.length}',
    );
    _emit(AudioProcessingState.loading);
    final medias = uris.map((u) => Media(u.toString())).toList();
    try {
      await _p.open(Playlist(medias, index: initialIndex), play: false);
    } catch (e, st) {
      dev.log('[BiMusicAudio] openQueue: _p.open threw: $e\n$st');
      rethrow;
    }
  }

  @override
  Stream<AudioProcessingState> get processingStateStream => _psCtrl.stream;

  @override
  AudioProcessingState get processingState => _ps;

  @override
  Stream<bool> get playingStream => _p.stream.playing;

  @override
  Stream<Duration> get positionStream =>
      _p.stream.position.map((p) => _queue.segmentOffset + p);

  @override
  Stream<Duration?> get durationStream => _durationCtrl.stream;

  @override
  Stream<int?> get indexStream => _indexCtrl.stream;

  @override
  bool get playing => _p.state.playing;

  @override
  Duration get position => _queue.segmentOffset + _p.state.position;

  @override
  Duration get bufferedPosition => _p.state.buffer;

  @override
  double get speed => _p.state.rate;

  @override
  int? get currentIndex => _queue.currentIndex;

  @override
  bool get hasNext {
    if (_queue.currentIndex == null) return false;
    if (_isShuffled) return _queue.length > 1;
    return _queue.currentIndex! + 1 < _queue.length;
  }

  @override
  bool get hasPrevious {
    if (_queue.currentIndex == null) return false;
    if (_isShuffled) return _queue.length > 1;
    return _queue.currentIndex! > 0;
  }

  @override
  Future<void> play() => _p.play();

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> stop() => _p.stop();

  @override
  Future<void> seekTo(Duration pos, {int? index}) async {
    if (index != null && index != _queue.currentIndex) {
      await jumpTo(index);
    }
    final targetIndex = _queue.currentIndex;
    if (targetIndex == null || targetIndex >= _queue.length) return;

    // Local files: mpv seeks natively within a single file.
    if (_queue.uris[targetIndex].scheme == 'file') {
      await _p.seek(pos);
      return;
    }

    // HLS streaming: compute which segment contains `pos`. If it's the
    // currently-loaded segment, mpv can seek within it directly. Otherwise
    // we must reload the playlist starting from that segment — mpv's native
    // playlist demuxer can't cross segment boundaries on its own.
    final target = computeHlsSeekTarget(
      seekTo: pos,
      currentSegmentOffset: _queue.segmentOffset,
      segmentDuration: _segmentDuration,
    );

    if (target.sameSegment) {
      await _p.seek(target.withinSegment);
      return;
    }

    _queue = _queue
        .resetNavigation()
        .withStartSegment(targetIndex, target.targetSegment)
        .withSegmentOffset(_segmentDuration * target.targetSegment);
    await _reopenQueueAt(targetIndex, target.withinSegment);
  }

  @override
  Future<void> seekToNext() async {
    if (_isShuffled) {
      _queue = _queue.resetNavigation();
      await _p.next();
      return;
    }
    if (hasNext) await jumpTo(_queue.currentIndex! + 1);
  }

  @override
  Future<void> seekToPrevious() async {
    if (_isShuffled) {
      _queue = _queue.resetNavigation();
      await _p.previous();
      return;
    }
    if (hasPrevious) await jumpTo(_queue.currentIndex! - 1);
  }

  @override
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    // Explicit navigation: drop any startSegment overrides so every track
    // plays from its beginning regardless of prior seeks.
    _queue = _queue.resetNavigation();
    await _reopenQueueAt(index, Duration.zero);
  }

  @override
  // media_kit volume is 0–100; our API is 0.0–1.0.
  Future<void> setVolume(double v) => _p.setVolume(v * 100);

  @override
  Future<void> setLoopMode(_LoopMode mode) => _p.setPlaylistMode(const {
        _LoopMode.off: PlaylistMode.none,
        _LoopMode.one: PlaylistMode.single,
        _LoopMode.all: PlaylistMode.loop,
      }[mode]!);

  @override
  Future<void> setShuffle(bool enabled) {
    _isShuffled = enabled;
    return _p.setShuffle(enabled);
  }

  @override
  void updateSegmentDuration(Duration d) => _segmentDuration = d;
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

_PlayerBackend _createBackend() {
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    return _MediaKitBackend();
  }
  return _JustAudioBackend();
}

// ---------------------------------------------------------------------------
// BiMusicAudioHandler
// ---------------------------------------------------------------------------

class BiMusicAudioHandler extends BaseAudioHandler {
  final _PlayerBackend _backend = _createBackend();
  final Completer<void> _initCompleter = Completer();

  List<Track> _tracks = [];
  String? _accessToken;
  int _bitrate = 320;
  String _baseUrl = '';
  String? _artistName;
  String? _albumTitle;
  String? _imageUrl;
  Map<int, String> _localFilePaths = const {};

  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  bool _isShuffled = false;

  BiMusicAudioHandler() {
    _init();
  }

  Stream<Duration> get positionStream => _backend.positionStream;
  Stream<Duration?> get durationStream => _backend.durationStream;
  List<Track> get currentTracks => List.unmodifiable(_tracks);

  Future<void> setVolume(double v) => _backend.setVolume(v.clamp(0.0, 1.0));

  void updateSegmentDuration(Duration d) => _backend.updateSegmentDuration(d);

  /// Rebuilds the audio source playlist with fresh stream URLs after token refresh.
  Future<void> updateToken(String newToken) async {
    _accessToken = newToken;
    if (_tracks.isEmpty) return;
    final wasPlaying = _backend.playing;
    final index = _backend.currentIndex ?? 0;
    final position = _backend.position;
    await _backend.openQueue(
      _tracks.map(_uriForTrack).toList(),
      index,
      durations: _tracks
          .map((t) => Duration(milliseconds: t.duration))
          .toList(),
    );
    await _backend.seekTo(position);
    if (wasPlaying) await _backend.play();
  }

  Future<void> _init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    try {
      await _backend.init();

      _backend.processingStateStream.listen(
        (_) {
          dev.log(
            '[BiMusicAudio] processingState: ${_backend.processingState} playing=${_backend.playing}',
          );
          _broadcastState();
        },
        onError: (Object e, StackTrace st) =>
            dev.log('[BiMusicAudio] processingStateStream error: $e\n$st'),
      );
      _backend.playingStream.listen(
        (_) => _broadcastState(),
        onError: (Object e, StackTrace st) =>
            dev.log('[BiMusicAudio] playingStream error: $e\n$st'),
      );
      _backend.indexStream.listen(_onCurrentIndexChanged);
      _backend.durationStream.listen(_onDurationChanged);

      _initCompleter.complete();
    } catch (e, st) {
      if (!_initCompleter.isCompleted) {
        _initCompleter.completeError(e, st);
      }
      rethrow;
    }
  }

  void _onCurrentIndexChanged(int? index) {
    if (index != null && index < _tracks.length) {
      mediaItem.add(_trackToMediaItem(_tracks[index]));
    }
  }

  void _onDurationChanged(Duration? d) {
    if (d == null) return;
    final current = mediaItem.valueOrNull;
    if (current != null) {
      mediaItem.add(current.copyWith(duration: d));
    }
  }

  Future<void> playQueue(
    List<Track> tracks,
    int startIndex,
    String? accessToken,
    int bitrate, {
    required String baseUrl,
    String? artistName,
    String? albumTitle,
    String? imageUrl,
    Map<int, String> localFilePaths = const {},
    int segmentSeconds = 6,
  }) async {
    await _initCompleter.future;

    _tracks = tracks;
    _accessToken = accessToken;
    _bitrate = bitrate;
    _baseUrl = baseUrl;
    _artistName = artistName;
    _albumTitle = albumTitle;
    _imageUrl = imageUrl;
    _localFilePaths = localFilePaths;
    _backend.updateSegmentDuration(Duration(seconds: segmentSeconds));

    queue.add(tracks.map(_trackToMediaItem).toList());
    mediaItem.add(_trackToMediaItem(tracks[startIndex]));

    try {
      await _backend.openQueue(
        tracks.map(_uriForTrack).toList(),
        startIndex,
        durations: tracks
            .map((t) => Duration(milliseconds: t.duration))
            .toList(),
      );
    } catch (e, st) {
      dev.log('[BiMusicAudio] openQueue error: $e\n$st');
      rethrow;
    }
    try {
      await _backend.play();
    } catch (e, st) {
      dev.log('[BiMusicAudio] play error: $e\n$st');
      rethrow;
    }
  }

  Uri _uriForTrack(Track t) {
    final localPath = _localFilePaths[t.id];
    if (localPath != null) {
      dev.log('[BiMusicAudio] Track ${t.id}: using local file');
      return Uri.file(localPath);
    }
    final params = <String, String>{
      'bitrate': '$_bitrate',
      if (_accessToken != null) 'token': _accessToken!,
    };
    final uri = Uri.parse('$_baseUrl/api/stream/${t.id}/playlist.m3u8')
        .replace(queryParameters: params);
    dev.log('[BiMusicAudio] Track ${t.id}: stream URL prepared');
    return uri;
  }

  MediaItem _trackToMediaItem(Track t) => MediaItem(
        id: '$_baseUrl/api/stream/${t.id}',
        title: t.title,
        artist: _artistName,
        album: _albumTitle,
        artUri: _imageUrl != null ? Uri.tryParse(_imageUrl!) : null,
        duration: Duration(milliseconds: t.duration),
      );

  void _broadcastState() {
    final processingState = _backend.processingState;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (_backend.playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: _backend.playing,
        updatePosition: _backend.position,
        bufferedPosition: _backend.bufferedPosition,
        speed: _backend.speed,
        queueIndex: _backend.currentIndex,
        repeatMode: _repeatMode,
        shuffleMode: _isShuffled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  @override
  Future<void> play() => _backend.play();

  @override
  Future<void> pause() => _backend.pause();

  @override
  Future<void> stop() async {
    await _backend.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _backend.seekTo(position);

  @override
  Future<void> skipToNext() async {
    if (_backend.hasNext) await _backend.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_backend.position > const Duration(seconds: 3)) {
      await _backend.seekTo(Duration.zero);
    } else if (_backend.hasPrevious) {
      await _backend.seekToPrevious();
    } else {
      await _backend.seekTo(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) => _backend.jumpTo(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    await _backend.setLoopMode(const {
      AudioServiceRepeatMode.none: _LoopMode.off,
      AudioServiceRepeatMode.one: _LoopMode.one,
      AudioServiceRepeatMode.group: _LoopMode.all,
      AudioServiceRepeatMode.all: _LoopMode.all,
    }[repeatMode]!);
    _broadcastState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _isShuffled = shuffleMode != AudioServiceShuffleMode.none;
    await _backend.setShuffle(_isShuffled);
    _broadcastState();
  }
}

final audioHandlerProvider = Provider<BiMusicAudioHandler>(
  (_) => throw UnimplementedError('audioHandlerProvider must be overridden'),
);
