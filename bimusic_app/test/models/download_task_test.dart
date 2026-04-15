import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/download_task.dart';

DownloadTask _makeTask({
  String serverId = 'srv-1',
  int trackId = 1,
  int albumId = 10,
  int artistId = 5,
  String userId = 'u1',
  String deviceId = 'dev-1',
  DownloadStatus status = DownloadStatus.pending,
  double? progress,
  String? filePath,
  int? fileSizeBytes,
  DateTime? completedAt,
  String? errorMessage,
  String trackTitle = 'My Track',
  String trackNumber = '3',
  String albumTitle = 'My Album',
  String artistName = 'My Artist',
  int bitrate = 128,
  String requestedAt = '2026-03-28T00:00:00Z',
}) =>
    DownloadTask(
      serverId: serverId,
      trackId: trackId,
      albumId: albumId,
      artistId: artistId,
      userId: userId,
      deviceId: deviceId,
      status: status,
      progress: progress,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      completedAt: completedAt,
      errorMessage: errorMessage,
      trackTitle: trackTitle,
      trackNumber: trackNumber,
      albumTitle: albumTitle,
      artistName: artistName,
      bitrate: bitrate,
      requestedAt: requestedAt,
    );

void main() {
  group('DownloadTask constructor', () {
    test('exposes all required fields', () {
      final task = _makeTask();
      expect(task.serverId, 'srv-1');
      expect(task.trackId, 1);
      expect(task.albumId, 10);
      expect(task.artistId, 5);
      expect(task.userId, 'u1');
      expect(task.deviceId, 'dev-1');
      expect(task.status, DownloadStatus.pending);
      expect(task.trackTitle, 'My Track');
      expect(task.trackNumber, '3');
      expect(task.albumTitle, 'My Album');
      expect(task.artistName, 'My Artist');
      expect(task.bitrate, 128);
      expect(task.requestedAt, '2026-03-28T00:00:00Z');
    });

    test('optional nullable fields default to null', () {
      final task = _makeTask();
      expect(task.progress, isNull);
      expect(task.filePath, isNull);
      expect(task.fileSizeBytes, isNull);
      expect(task.completedAt, isNull);
      expect(task.errorMessage, isNull);
    });
  });

  group('DownloadTask.copyWith', () {
    test('copies status', () {
      final task = _makeTask();
      final updated = task.copyWith(status: DownloadStatus.downloading);
      expect(updated.status, DownloadStatus.downloading);
      // immutable fields unchanged
      expect(updated.trackTitle, 'My Track');
      expect(updated.serverId, 'srv-1');
    });

    test('copies progress', () {
      final task = _makeTask();
      final updated = task.copyWith(progress: 0.75);
      expect(updated.progress, 0.75);
    });

    test('copies filePath', () {
      final task = _makeTask();
      final updated = task.copyWith(filePath: '/docs/track.mp3');
      expect(updated.filePath, '/docs/track.mp3');
    });

    test('copies fileSizeBytes', () {
      final task = _makeTask();
      final updated = task.copyWith(fileSizeBytes: 5 * 1024 * 1024);
      expect(updated.fileSizeBytes, 5 * 1024 * 1024);
    });

    test('copies completedAt', () {
      final now = DateTime(2026, 3, 28, 12, 0, 0);
      final task = _makeTask();
      final updated = task.copyWith(completedAt: now);
      expect(updated.completedAt, now);
    });

    test('copies errorMessage', () {
      final task = _makeTask();
      final updated = task.copyWith(errorMessage: 'Connection refused');
      expect(updated.errorMessage, 'Connection refused');
    });

    test('preserves existing values when null passed', () {
      final task = _makeTask(
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: '/docs/1.mp3',
      );
      final updated = task.copyWith(); // no changes
      expect(updated.status, DownloadStatus.completed);
      expect(updated.progress, 1.0);
      expect(updated.filePath, '/docs/1.mp3');
    });
  });

  group('DownloadTask.fromJson', () {
    test('parses all fields', () {
      final json = {
        'serverId': 'srv-abc',
        'trackId': 99,
        'albumId': 10,
        'artistId': 5,
        'userId': 'u1',
        'deviceId': 'dev-1',
        'status': 'completed',
        'progress': 1.0,
        'filePath': '/docs/99.mp3',
        'fileSizeBytes': 1024 * 1024,
        'completedAt': '2026-03-28T10:00:00.000',
        'errorMessage': null,
        'trackTitle': 'Some Track',
        'trackNumber': '3',
        'albumTitle': 'Some Album',
        'artistName': 'Some Artist',
        'bitrate': 320,
        'requestedAt': '2026-03-28T09:00:00Z',
      };

      final task = DownloadTask.fromJson(json);

      expect(task.serverId, 'srv-abc');
      expect(task.trackId, 99);
      expect(task.status, DownloadStatus.completed);
      expect(task.progress, 1.0);
      expect(task.filePath, '/docs/99.mp3');
      expect(task.fileSizeBytes, 1024 * 1024);
      expect(task.completedAt, DateTime(2026, 3, 28, 10, 0, 0));
      expect(task.errorMessage, isNull);
      expect(task.bitrate, 320);
    });

    test('parses null completedAt as null', () {
      final json = {
        'serverId': 's1',
        'trackId': 1,
        'albumId': 1,
        'artistId': 1,
        'userId': 'u1',
        'deviceId': 'd1',
        'status': 'pending',
        'progress': null,
        'filePath': null,
        'fileSizeBytes': null,
        'completedAt': null,
        'errorMessage': null,
        'trackTitle': 'T',
        'trackNumber': '1',
        'albumTitle': 'A',
        'artistName': 'AR',
        'bitrate': 128,
        'requestedAt': '2026-03-28T00:00:00Z',
      };
      final task = DownloadTask.fromJson(json);
      expect(task.completedAt, isNull);
    });

    test('parses all DownloadStatus values', () {
      for (final status in DownloadStatus.values) {
        final json = {
          'serverId': 's1',
          'trackId': 1,
          'albumId': 1,
          'artistId': 1,
          'userId': 'u1',
          'deviceId': 'd1',
          'status': status.name,
          'trackTitle': 'T',
          'trackNumber': '1',
          'albumTitle': 'A',
          'artistName': 'AR',
          'bitrate': 128,
          'requestedAt': '2026-03-28T00:00:00Z',
        };
        final task = DownloadTask.fromJson(json);
        expect(task.status, status);
      }
    });
  });

  group('DownloadTask.toJson', () {
    test('serialises all fields', () {
      final completedAt = DateTime(2026, 3, 28, 10, 0, 0);
      final task = _makeTask(
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: '/docs/1.mp3',
        fileSizeBytes: 2 * 1024 * 1024,
        completedAt: completedAt,
        errorMessage: null,
      );

      final json = task.toJson();

      expect(json['serverId'], 'srv-1');
      expect(json['trackId'], 1);
      expect(json['status'], 'completed');
      expect(json['progress'], 1.0);
      expect(json['filePath'], '/docs/1.mp3');
      expect(json['fileSizeBytes'], 2 * 1024 * 1024);
      expect(json['completedAt'], isNotNull);
      expect(json['errorMessage'], isNull);
      expect(json['bitrate'], 128);
    });

    test('serialises null fields as null', () {
      final task = _makeTask();
      final json = task.toJson();
      expect(json['progress'], isNull);
      expect(json['filePath'], isNull);
      expect(json['completedAt'], isNull);
    });

    test('round-trips through fromJson', () {
      final original = _makeTask(
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: '/music/1.mp3',
        fileSizeBytes: 3 * 1024 * 1024,
        completedAt: DateTime(2026, 3, 28),
      );

      final decoded = DownloadTask.fromJson(original.toJson());
      expect(decoded.serverId, original.serverId);
      expect(decoded.trackId, original.trackId);
      expect(decoded.status, original.status);
      expect(decoded.fileSizeBytes, original.fileSizeBytes);
      expect(decoded.completedAt, original.completedAt);
      expect(decoded.filePath, original.filePath);
    });
  });

  group('DownloadStatus', () {
    test('has 5 values', () {
      expect(DownloadStatus.values.length, 5);
    });

    test('names match expected strings', () {
      expect(DownloadStatus.pending.name, 'pending');
      expect(DownloadStatus.downloading.name, 'downloading');
      expect(DownloadStatus.ready.name, 'ready');
      expect(DownloadStatus.completed.name, 'completed');
      expect(DownloadStatus.failed.name, 'failed');
    });
  });
}
