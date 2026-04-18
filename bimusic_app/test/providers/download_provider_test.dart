import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/download_task.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/providers/download_provider.dart';
import 'package:bimusic_app/services/api_client.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/services/download_service.dart';

// ---------------------------------------------------------------------------
// Fakes / mocks
// ---------------------------------------------------------------------------

class _FakeAuthService extends Fake implements AuthService {
  @override
  String? get accessToken => 'test-token';
}

// Fake Dio whose delete() returns 200 immediately (used to stub apiClientProvider).
class _FakeDio extends Fake implements Dio {
  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async =>
      Response<T>(
        data: null,
        statusCode: 200,
        requestOptions: RequestOptions(path: path),
      );
}

class _FakeAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  @override
  Future<void> get initialized async {}

  @override
  AuthState build() => const AuthStateUnauthenticated();

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // Required because connectivityProvider uses platform channels.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('DownloadState', () {
    test('initial state has empty tasks and isLoading true', () {
      const state = DownloadState();
      expect(state.tasks, isEmpty);
      expect(state.isLoading, isTrue);
      expect(state.deviceId, isNull);
    });

    test('copyWith updates only specified fields', () {
      const original = DownloadState(isLoading: true, deviceId: null);
      final updated = original.copyWith(isLoading: false, deviceId: 'dev-1');
      expect(updated.isLoading, isFalse);
      expect(updated.deviceId, 'dev-1');
      expect(updated.tasks, isEmpty);
    });
  });

  group('StorageUsage', () {
    test('formattedSize shows bytes as KB', () {
      const usage = StorageUsage(usedBytes: 2048, trackCount: 1);
      expect(usage.formattedSize, contains('KB'));
    });

    test('formattedSize shows MB for megabyte-scale values', () {
      const usage = StorageUsage(usedBytes: 5 * 1024 * 1024, trackCount: 2);
      expect(usage.formattedSize, contains('MB'));
    });

    test('formattedSize shows GB for gigabyte-scale values', () {
      const usage = StorageUsage(usedBytes: 2 * 1024 * 1024 * 1024, trackCount: 5);
      expect(usage.formattedSize, contains('GB'));
    });
  });

  group('userDownloadsProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          // Override auth to avoid real secure storage.
          authServiceProvider.overrideWith((_) => _FakeAuthService()),
          authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
          // deviceIdProvider returns a stable ID.
          deviceIdProvider.overrideWith((_) async => 'test-device'),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('returns empty list when no tasks present', () {
      final downloads = container.read(userDownloadsProvider);
      expect(downloads, isEmpty);
    });
  });

  group('storageUsageProvider', () {
    test('returns zero usage when no completed downloads', () {
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWith((_) => _FakeAuthService()),
          authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
          deviceIdProvider.overrideWith((_) async => 'test-device'),
        ],
      );
      addTearDown(container.dispose);

      final usage = container.read(storageUsageProvider);
      expect(usage.usedBytes, 0);
      expect(usage.trackCount, 0);
    });

    test('sums file sizes of completed tasks only', () {
      final task1 = DownloadTask(
        serverId: 's1',
        trackId: 1,
        albumId: 10,
        artistId: 5,
        userId: 'u1',
        deviceId: 'dev-1',
        status: DownloadStatus.completed,
        fileSizeBytes: 3 * 1024 * 1024,
        trackTitle: 'Track 1',
        trackNumber: '1',
        albumTitle: 'Album',
        artistName: 'Artist',
        bitrate: 320,
        requestedAt: '2026-03-28T00:00:00Z',
      );

      final task2 = DownloadTask(
        serverId: 's2',
        trackId: 2,
        albumId: 10,
        artistId: 5,
        userId: 'u1',
        deviceId: 'dev-1',
        status: DownloadStatus.pending,
        trackTitle: 'Track 2',
        trackNumber: '2',
        albumTitle: 'Album',
        artistName: 'Artist',
        bitrate: 320,
        requestedAt: '2026-03-28T00:00:00Z',
      );

      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWith((_) => _FakeAuthService()),
          authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
          deviceIdProvider.overrideWith((_) async => 'test-device'),
          // Seed the download state directly.
          downloadProvider.overrideWith(() => _StubDownloadNotifier([task1, task2])),
        ],
      );
      addTearDown(container.dispose);

      final usage = container.read(storageUsageProvider);
      expect(usage.usedBytes, 3 * 1024 * 1024);
      expect(usage.trackCount, 1);
    });
  });

  group('DownloadTask serialisation', () {
    test('round-trips through fromJson/toJson', () {
      final task = DownloadTask(
        serverId: 'srv-abc',
        trackId: 99,
        albumId: 10,
        artistId: 5,
        userId: 'u1',
        deviceId: 'dev-1',
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: '/docs/music/99.mp3',
        fileSizeBytes: 1024 * 1024,
        completedAt: DateTime(2026, 3, 28),
        errorMessage: null,
        trackTitle: 'Some Track',
        trackNumber: '3',
        albumTitle: 'Some Album',
        artistName: 'Some Artist',
        bitrate: 320,
        requestedAt: '2026-03-28T10:00:00.000',
      );

      final decoded = DownloadTask.fromJson(task.toJson());
      expect(decoded.serverId, task.serverId);
      expect(decoded.trackId, task.trackId);
      expect(decoded.status, task.status);
      expect(decoded.fileSizeBytes, task.fileSizeBytes);
      expect(decoded.completedAt, task.completedAt);
    });
  });

  _mutationTests();
}

// ---------------------------------------------------------------------------
// Mutation method tests — use _StubDownloadNotifier so build() seeds state
// without hitting path_provider or connectivity platform channels.
// authNotifierProvider is overridden to AuthStateUnauthenticated so _persist()
// returns early (no file IO needed to verify state changes).
// ---------------------------------------------------------------------------

/// Builds a minimal task for use in tests.
DownloadTask _makeTask({
  required String serverId,
  DownloadStatus status = DownloadStatus.pending,
  String? filePath,
}) =>
    DownloadTask(
      serverId: serverId,
      trackId: 1,
      albumId: 10,
      artistId: 5,
      userId: 'u1',
      deviceId: 'dev-1',
      status: status,
      trackTitle: 'Track',
      trackNumber: '1',
      albumTitle: 'Album',
      artistName: 'Artist',
      bitrate: 320,
      requestedAt: '2026-01-01T00:00:00Z',
      filePath: filePath,
    );

ProviderContainer _makeContainer(
  List<DownloadTask> initialTasks, {
  Dio? dio,
}) {
  return ProviderContainer(
    overrides: [
      authServiceProvider.overrideWith((_) => _FakeAuthService()),
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
      deviceIdProvider.overrideWith((_) async => 'test-device'),
      downloadProvider.overrideWith(() => _StubDownloadNotifier(initialTasks)),
      if (dio != null) apiClientProvider.overrideWithValue(dio),
    ],
  );
}

void _mutationTests() {
  group('cancelDownload', () {
    test('flips a downloading task back to pending', () async {
      final container = _makeContainer([
        _makeTask(serverId: 's1', status: DownloadStatus.downloading),
      ]);
      addTearDown(container.dispose);

      await container.read(downloadProvider.notifier).cancelDownload('s1');

      final task = container.read(downloadProvider).tasks.first;
      expect(task.status, DownloadStatus.pending);
    });

    test('is a no-op for unknown serverId', () async {
      final container = _makeContainer([
        _makeTask(serverId: 's1', status: DownloadStatus.downloading),
      ]);
      addTearDown(container.dispose);

      // Should not throw even when the id is unknown.
      await container.read(downloadProvider.notifier).cancelDownload('unknown');

      expect(container.read(downloadProvider).tasks.first.status, DownloadStatus.downloading);
    });
  });

  group('removeDownload', () {
    test('removes the task from state', () async {
      final container = _makeContainer(
        [
          _makeTask(serverId: 's1', status: DownloadStatus.completed),
          _makeTask(serverId: 's2', status: DownloadStatus.pending),
        ],
        dio: _FakeDio(),
      );
      addTearDown(container.dispose);

      await container.read(downloadProvider.notifier).removeDownload('s1');

      final tasks = container.read(downloadProvider).tasks;
      expect(tasks.length, 1);
      expect(tasks.first.serverId, 's2');
    });

    test('removes a task with no local file (no file IO)', () async {
      final container = _makeContainer(
        [_makeTask(serverId: 's1', status: DownloadStatus.failed)],
        dio: _FakeDio(),
      );
      addTearDown(container.dispose);

      await container.read(downloadProvider.notifier).removeDownload('s1');

      expect(container.read(downloadProvider).tasks, isEmpty);
    });

    test('throws when serverId not found', () async {
      final container = _makeContainer([], dio: _FakeDio());
      addTearDown(container.dispose);

      await expectLater(
        container.read(downloadProvider.notifier).removeDownload('missing'),
        throwsStateError,
      );
    });
  });

  group('clearAllDownloads', () {
    test('empties the task list', () async {
      final container = _makeContainer(
        [
          _makeTask(serverId: 's1', status: DownloadStatus.completed),
          _makeTask(serverId: 's2', status: DownloadStatus.pending),
          _makeTask(serverId: 's3', status: DownloadStatus.failed),
        ],
        dio: _FakeDio(),
      );
      addTearDown(container.dispose);

      await container.read(downloadProvider.notifier).clearAllDownloads();

      expect(container.read(downloadProvider).tasks, isEmpty);
    });

    test('is a no-op when there are no tasks', () async {
      final container = _makeContainer([], dio: _FakeDio());
      addTearDown(container.dispose);

      await container.read(downloadProvider.notifier).clearAllDownloads();

      expect(container.read(downloadProvider).tasks, isEmpty);
    });
  });

}

// ---------------------------------------------------------------------------
// Stub notifier for seeding state in tests
// ---------------------------------------------------------------------------

class _StubDownloadNotifier extends DownloadNotifier {
  _StubDownloadNotifier(this._initialTasks);

  final List<DownloadTask> _initialTasks;

  @override
  DownloadState build() {
    return DownloadState(tasks: _initialTasks, isLoading: false, deviceId: 'test-device');
  }
}
