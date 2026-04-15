import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/download_task.dart';
import '../models/track.dart';
import '../providers/auth_provider.dart';
import '../providers/bitrate_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/api_client.dart';
import '../services/download_service.dart';

// ---------------------------------------------------------------------------
// State types
// ---------------------------------------------------------------------------

class DownloadState {
  const DownloadState({
    this.tasks = const [],
    this.deviceId,
    this.isLoading = true,
  });

  final List<DownloadTask> tasks;
  final String? deviceId;
  final bool isLoading;

  DownloadState copyWith({
    List<DownloadTask>? tasks,
    String? deviceId,
    bool? isLoading,
  }) =>
      DownloadState(
        tasks: tasks ?? this.tasks,
        deviceId: deviceId ?? this.deviceId,
        isLoading: isLoading ?? this.isLoading,
      );
}

class StorageUsage {
  const StorageUsage({required this.usedBytes, required this.trackCount});

  final int usedBytes;
  final int trackCount;

  String get formattedSize {
    if (usedBytes < 1024 * 1024) {
      return '${(usedBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (usedBytes < 1024 * 1024 * 1024) {
      return '${(usedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(usedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// ---------------------------------------------------------------------------
// DownloadNotifier
// ---------------------------------------------------------------------------

class DownloadNotifier extends Notifier<DownloadState> {
  static const int _maxConcurrent = 2;

  final _cancelTokens = <String, CancelToken>{};
  int _activeCount = 0;
  bool _isConnected = true;

  @override
  DownloadState build() {
    if (!kIsWeb) {
      // Pause/resume downloads on connectivity changes.
      ref.listen(connectivityProvider, (_, next) {
        final connected = next.valueOrNull != ConnectivityResult.none;
        if (connected && !_isConnected) {
          _isConnected = true;
          _processQueue();
        } else if (!connected) {
          _isConnected = false;
        }
      });
    }

    _init();
    return const DownloadState();
  }

  Future<void> _init() async {
    if (kIsWeb) {
      state = state.copyWith(isLoading: false);
      return;
    }

    final authState = ref.read(authNotifierProvider);
    if (authState is AuthStateAuthenticated) {
      await _loadPersistedTasks(authState.tokens.user.userId);
    }

    final deviceId = await ref.read(deviceIdProvider.future);
    state = state.copyWith(deviceId: deviceId, isLoading: false);

    // Resume any pending tasks left over from a previous session.
    _processQueue();
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<File> _storageFile(String userId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}bimusic_downloads_$userId.json');
  }

  Future<void> _loadPersistedTasks(String userId) async {
    try {
      final file = await _storageFile(userId);
      if (!await file.exists()) return;

      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      final tasks = raw
          .cast<Map<String, dynamic>>()
          .map(DownloadTask.fromJson)
          .toList();

      // Any task that was mid-download (or waiting for server transcode) when
      // the app died is reset to pending so the queue can retry it.
      final reset = tasks.map((t) {
        if (t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.ready) {
          return t.copyWith(status: DownloadStatus.pending);
        }
        return t;
      }).toList();

      state = state.copyWith(tasks: reset);
    } catch (_) {
      state = state.copyWith(tasks: []);
    }
  }

  Future<void> _persist() async {
    if (kIsWeb) return;
    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthStateAuthenticated) return;
    try {
      final file = await _storageFile(authState.tokens.user.userId);
      await file.writeAsString(
        jsonEncode(state.tasks.map((t) => t.toJson()).toList()),
      );
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // State helpers
  // -------------------------------------------------------------------------

  void _updateTask(String serverId, DownloadTask Function(DownloadTask t) fn) {
    final tasks = List<DownloadTask>.from(state.tasks);
    final idx = tasks.indexWhere((t) => t.serverId == serverId);
    if (idx < 0) return;
    tasks[idx] = fn(tasks[idx]);
    state = state.copyWith(tasks: tasks);
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Enqueue a single track for offline download.  Silently skips if the
  /// track is already queued, downloading, or completed for this device.
  Future<void> requestDownload(
    Track track, {
    required int albumId,
    required int artistId,
    required String albumTitle,
    required String artistName,
  }) async {
    if (kIsWeb) return;

    final deviceId = state.deviceId;
    if (deviceId == null) return;

    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthStateAuthenticated) return;
    final userId = authState.tokens.user.userId;

    // Deduplicate: skip if already active or completed.
    final isDuplicate = state.tasks.any(
      (t) =>
          t.trackId == track.id &&
          t.userId == userId &&
          t.deviceId == deviceId &&
          t.status != DownloadStatus.failed,
    );
    if (isDuplicate) return;

    final bitrate = ref.read(bitrateProvider);

    // Tell the backend to prepare the offline record.
    final Map<String, dynamic> responseData;
    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.post<Map<String, dynamic>>(
        '/api/downloads',
        data: {'trackId': track.id, 'deviceId': deviceId, 'bitrate': bitrate},
      );
      responseData = resp.data!;
    } catch (_) {
      return;
    }

    final serverId = responseData['id'] as String;

    final task = DownloadTask(
      serverId: serverId,
      trackId: track.id,
      albumId: albumId,
      artistId: artistId,
      userId: userId,
      deviceId: deviceId,
      status: DownloadStatus.pending,
      trackTitle: track.title,
      trackNumber: track.trackNumber,
      albumTitle: albumTitle,
      artistName: artistName,
      bitrate: bitrate,
      requestedAt: DateTime.now().toIso8601String(),
    );

    state = state.copyWith(tasks: [...state.tasks, task]);
    await _persist();
    _processQueue();
  }

  /// Enqueue all tracks in an album for offline download.
  Future<void> requestAlbumDownload(
    List<Track> tracks, {
    required int albumId,
    required int artistId,
    required String albumTitle,
    required String artistName,
  }) async {
    for (final track in tracks) {
      await requestDownload(
        track,
        albumId: albumId,
        artistId: artistId,
        albumTitle: albumTitle,
        artistName: artistName,
      );
    }
  }

  /// Cancel an active download and reset its status to [DownloadStatus.pending]
  /// so it can be retried later.
  Future<void> cancelDownload(String serverId) async {
    _cancelTokens.remove(serverId)?.cancel('Cancelled by user');
    _updateTask(serverId, (t) => t.copyWith(status: DownloadStatus.pending));
    await _persist();
  }

  /// Reset a failed download back to [DownloadStatus.pending] and re-queue it.
  Future<void> retryDownload(String serverId) async {
    _updateTask(
      serverId,
      (t) => t.copyWith(status: DownloadStatus.pending),
    );
    await _persist();
    _processQueue();
  }

  /// Cancel all active downloads, delete all local files, remove all backend
  /// records, and clear the task list.
  Future<void> clearAllDownloads() async {
    // Cancel all in-flight transfers.
    for (final token in _cancelTokens.values) {
      token.cancel('Cleared by user');
    }
    _cancelTokens.clear();

    final tasks = List<DownloadTask>.from(state.tasks);

    // Delete local files (best-effort).
    for (final task in tasks) {
      if (task.filePath != null) {
        try {
          final f = File(task.filePath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }

    // Remove backend records (best-effort, fire and forget).
    final dio = ref.read(apiClientProvider);
    for (final task in tasks) {
      try {
        await dio.delete('/api/downloads/${task.serverId}');
      } catch (_) {}
    }

    _activeCount = 0;
    state = state.copyWith(tasks: []);
    await _persist();
  }

  /// Permanently remove a download: cancels any active transfer, deletes the
  /// local file, and removes the server-side record.
  Future<void> removeDownload(String serverId) async {
    _cancelTokens.remove(serverId)?.cancel('Removed by user');

    final task = state.tasks.firstWhere(
      (t) => t.serverId == serverId,
      orElse: () => throw StateError('Task $serverId not found'),
    );

    // Delete local file (best-effort).
    if (task.filePath != null) {
      try {
        final f = File(task.filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    // Remove backend record (best-effort).
    try {
      await ref.read(apiClientProvider).delete('/api/downloads/$serverId');
    } catch (_) {}

    state = state.copyWith(
      tasks: state.tasks.where((t) => t.serverId != serverId).toList(),
    );
    await _persist();
  }

  // -------------------------------------------------------------------------
  // Queue processing
  // -------------------------------------------------------------------------

  void _processQueue() {
    if (!_isConnected || kIsWeb) return;

    final pending = state.tasks
        .where((t) => t.status == DownloadStatus.pending)
        .toList();

    for (final task in pending) {
      if (_activeCount >= _maxConcurrent) break;
      _startDownload(task.serverId);
    }
  }

  Future<void> _startDownload(String serverId) async {
    _activeCount++;
    final cancelToken = CancelToken();
    _cancelTokens[serverId] = cancelToken;

    _updateTask(
      serverId,
      (t) => t.copyWith(status: DownloadStatus.downloading),
    );

    try {
      final task = state.tasks.firstWhere((t) => t.serverId == serverId);
      final filePath = await _buildFilePath(task);

      // Ensure the target directory exists.
      await File(filePath).parent.create(recursive: true);

      await ref.read(downloadServiceProvider).downloadFile(
        serverId: serverId,
        savePath: filePath,
        onProgress: (p) =>
            _updateTask(serverId, (t) => t.copyWith(progress: p)),
        cancelToken: cancelToken,
      );

      int? fileSize;
      try {
        fileSize = await File(filePath).length();
      } catch (_) {}

      _updateTask(
        serverId,
        (t) => t.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          filePath: filePath,
          fileSizeBytes: fileSize,
          completedAt: DateTime.now(),
        ),
      );
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        _updateTask(
          serverId,
          (t) => t.copyWith(
            status: DownloadStatus.failed,
            errorMessage: e.message ?? 'Download failed',
          ),
        );
      }
    } catch (e) {
      _updateTask(
        serverId,
        (t) => t.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      _cancelTokens.remove(serverId);
      _activeCount--;
      await _persist();
      _processQueue(); // kick off the next queued item
    }
  }

  /// Builds the local file path:
  /// `<documents>/<userId>/music/<artistId>/<albumId>/<trackId>.mp3`
  Future<String> _buildFilePath(DownloadTask task) async {
    final dir = await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    return '${dir.path}$sep${task.userId}${sep}music'
        '$sep${task.artistId}$sep${task.albumId}$sep${task.trackId}.mp3';
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final downloadProvider = NotifierProvider<DownloadNotifier, DownloadState>(
  DownloadNotifier.new,
);

/// Convenience: all download tasks for the current user (empty on web).
final userDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  if (kIsWeb) return const [];
  return ref.watch(downloadProvider).tasks;
});

/// Storage used by completed offline downloads.
final storageUsageProvider = Provider<StorageUsage>((ref) {
  final completed = ref
      .watch(userDownloadsProvider)
      .where((d) => d.status == DownloadStatus.completed);
  final totalBytes =
      completed.fold<int>(0, (sum, d) => sum + (d.fileSizeBytes ?? 0));
  return StorageUsage(usedBytes: totalBytes, trackCount: completed.length);
});
