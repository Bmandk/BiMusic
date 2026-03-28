import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

// ---------------------------------------------------------------------------
// UUID helper (no external package needed)
// ---------------------------------------------------------------------------

/// Generates a random UUID v4 string using [Random.secure].
String generateUuid() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

// ---------------------------------------------------------------------------
// Device ID provider
// ---------------------------------------------------------------------------

/// Returns a stable per-device identifier.  Created once on first launch and
/// persisted in [FlutterSecureStorage] under the key `bimusic_device_id`.
final deviceIdProvider = FutureProvider<String>((ref) async {
  const storage = FlutterSecureStorage();
  var id = await storage.read(key: 'bimusic_device_id');
  if (id == null) {
    id = generateUuid();
    await storage.write(key: 'bimusic_device_id', value: id);
  }
  return id;
});

// ---------------------------------------------------------------------------
// DownloadService
// ---------------------------------------------------------------------------

/// Handles the actual file transfer from the BiMusic backend to local storage.
///
/// The backend transcodes tracks asynchronously.  `GET /api/downloads/:id/file`
/// returns **409** while the transcode is still in progress.  This service
/// retries up to [_maxRetries] times (at 10-second intervals, ~10 min total)
/// before giving up.
class DownloadService {
  DownloadService(this._dio);

  final Dio _dio;
  static const int _maxRetries = 60;

  /// Downloads the transcoded file for [serverId] and saves it to [savePath].
  ///
  /// [onProgress] is called with values in `[0.0, 1.0]` as bytes arrive.
  /// Pass a [CancelToken] to support cancellation.
  Future<void> downloadFile({
    required String serverId,
    required String savePath,
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.cancel,
        );
      }

      try {
        await _dio.download(
          '/api/downloads/$serverId/file',
          savePath,
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress(received / total);
          },
          cancelToken: cancelToken,
        );
        return; // success
      } on DioException catch (e) {
        if (e.response?.statusCode == 409) {
          // Transcoding not yet complete — wait and retry.
          if (cancelToken?.isCancelled ?? false) rethrow;
          await Future<void>.delayed(const Duration(seconds: 10));
          continue;
        }
        // Any other error: clean up any partial file and propagate.
        try {
          final partial = File(savePath);
          if (await partial.exists()) await partial.delete();
        } catch (_) {}
        rethrow;
      }
    }
    throw Exception(
      'Download timed out: server transcoding took longer than expected',
    );
  }
}

final downloadServiceProvider = Provider<DownloadService>((ref) {
  return DownloadService(ref.watch(apiClientProvider));
});
