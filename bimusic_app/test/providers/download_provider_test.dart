import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/download_task.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/providers/download_provider.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/services/download_service.dart';

// ---------------------------------------------------------------------------
// Fakes / mocks
// ---------------------------------------------------------------------------

class _FakeAuthService extends Fake implements AuthService {
  @override
  String? get accessToken => 'test-token';
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
