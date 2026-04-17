import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/track.dart';

class BiMusicAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();
  final Completer<void> _initCompleter = Completer();

  List<Track> _tracks = [];
  String? _accessToken;
  int _bitrate = 320;
  String? _artistName;
  String? _albumTitle;
  String? _imageUrl;
  Map<int, String> _localFilePaths = const {};

  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  bool _isShuffled = false;

  BiMusicAudioHandler() {
    _init();
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  List<Track> get currentTracks => List.unmodifiable(_tracks);

  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0));

  /// Called when the access token is refreshed. Rebuilds the audio source
  /// playlist with fresh stream URLs so libmpv never hits an expired token.
  Future<void> updateToken(String newToken) async {
    _accessToken = newToken;
    if (_tracks.isEmpty) return;
    final wasPlaying = _player.playing;
    final index = _player.currentIndex ?? 0;
    final position = _player.position;
    final playlist = ConcatenatingAudioSource(
      children: _tracks.map(_sourceForTrack).toList(),
    );
    await _player.setAudioSource(
      playlist,
      initialIndex: index,
      initialPosition: position,
    );
    if (wasPlaying) await _player.play();
  }

  Future<void> _init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}
    _player.playbackEventStream.listen((_) => _broadcastState());
    _player.playerStateStream.listen((_) => _broadcastState());
    _player.currentIndexStream.listen(_onCurrentIndexChanged);
    _player.durationStream.listen(_onDurationChanged);
    _initCompleter.complete();
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
    String? artistName,
    String? albumTitle,
    String? imageUrl,
    Map<int, String> localFilePaths = const {},
  }) async {
    await _initCompleter.future;

    _tracks = tracks;
    _accessToken = accessToken;
    _bitrate = bitrate;
    _artistName = artistName;
    _albumTitle = albumTitle;
    _imageUrl = imageUrl;
    _localFilePaths = localFilePaths;

    final sources = tracks.map(_sourceForTrack).toList();
    queue.add(tracks.map(_trackToMediaItem).toList());
    mediaItem.add(_trackToMediaItem(tracks[startIndex]));

    final playlist = ConcatenatingAudioSource(children: sources);
    // preload: false — returns immediately without waiting for duration probe;
    // play() drives the actual load so first bytes reach the client sooner.
    await _player.setAudioSource(playlist, initialIndex: startIndex, preload: false);
    await _player.play();
  }

  AudioSource _sourceForTrack(Track t) {
    // Use locally-stored file if available (offline playback).
    final localPath = _localFilePaths[t.id];
    if (localPath != null) {
      return AudioSource.file(localPath);
    }
    // Pass token as query param instead of header — just_audio's header proxy
    // doesn't work reliably with just_audio_media_kit (libmpv).
    final params = <String, String>{
      'bitrate': '$_bitrate',
      if (_accessToken != null) 'token': _accessToken!,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/stream/${t.id}')
        .replace(queryParameters: params);
    return AudioSource.uri(uri);
  }

  MediaItem _trackToMediaItem(Track t) => MediaItem(
    id: '${ApiConfig.baseUrl}/api/stream/${t.id}',
    title: t.title,
    artist: _artistName,
    album: _albumTitle,
    artUri: _imageUrl != null ? Uri.tryParse(_imageUrl!) : null,
    duration: Duration(milliseconds: t.duration),
  );

  void _broadcastState() {
    final isPlaying = _player.playing;
    final processingState = {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState] ??
        AudioProcessingState.idle;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
        repeatMode: _repeatMode,
        shuffleMode: _isShuffled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.group => LoopMode.all,
      AudioServiceRepeatMode.all => LoopMode.all,
      _ => LoopMode.off,
    };
    await _player.setLoopMode(loopMode);
    _broadcastState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _isShuffled = shuffleMode != AudioServiceShuffleMode.none;
    await _player.setShuffleModeEnabled(_isShuffled);
    _broadcastState();
  }
}

final audioHandlerProvider = Provider<BiMusicAudioHandler>(
  (_) => throw UnimplementedError('audioHandlerProvider must be overridden'),
);
