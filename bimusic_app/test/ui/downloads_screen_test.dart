import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/download_task.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/providers/download_provider.dart';
import 'package:bimusic_app/services/auth_service.dart';
import 'package:bimusic_app/services/download_service.dart';
import 'package:bimusic_app/ui/screens/downloads_screen.dart';

// ---------------------------------------------------------------------------
// Fakes
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

class _StubDownloadNotifier extends DownloadNotifier {
  _StubDownloadNotifier(this._tasks);

  final List<DownloadTask> _tasks;

  @override
  DownloadState build() =>
      DownloadState(tasks: _tasks, isLoading: false, deviceId: 'test-dev');

  @override
  Future<void> removeDownload(String serverId) async {
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.serverId != serverId).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<DownloadTask> _tasks({bool withItems = true}) {
  if (!withItems) return [];
  return [
    DownloadTask(
      serverId: 's1',
      trackId: 1,
      albumId: 10,
      artistId: 5,
      userId: 'u1',
      deviceId: 'dev-1',
      status: DownloadStatus.completed,
      fileSizeBytes: 4 * 1024 * 1024,
      filePath: '/docs/1.mp3',
      completedAt: DateTime(2026, 3, 28),
      trackTitle: 'First Track',
      trackNumber: '1',
      albumTitle: 'Great Album',
      artistName: 'Great Artist',
      bitrate: 320,
      requestedAt: '2026-03-28T10:00:00Z',
    ),
    DownloadTask(
      serverId: 's2',
      trackId: 2,
      albumId: 10,
      artistId: 5,
      userId: 'u1',
      deviceId: 'dev-1',
      status: DownloadStatus.downloading,
      progress: 0.5,
      trackTitle: 'Second Track',
      trackNumber: '2',
      albumTitle: 'Great Album',
      artistName: 'Great Artist',
      bitrate: 320,
      requestedAt: '2026-03-28T10:00:00Z',
    ),
  ];
}

ProviderContainer _container(List<DownloadTask> tasks) => ProviderContainer(
      overrides: [
        authServiceProvider.overrideWith((_) => _FakeAuthService()),
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
        deviceIdProvider.overrideWith((_) async => 'test-dev'),
        downloadProvider.overrideWith(() => _StubDownloadNotifier(tasks)),
      ],
    );

Widget _buildSubject(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DownloadsScreen()),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('shows empty state when no downloads', (tester) async {
    final container = _container([]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.text('No downloads yet'), findsOneWidget);
  });

  testWidgets('renders track titles when downloads are present', (tester) async {
    final container = _container(_tasks());
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.text('First Track'), findsOneWidget);
    expect(find.text('Second Track'), findsOneWidget);
  });

  testWidgets('shows album group header', (tester) async {
    final container = _container(_tasks());
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.text('Great Album'), findsOneWidget);
    expect(find.text('Great Artist'), findsOneWidget);
  });

  testWidgets('storage usage banner shows used size', (tester) async {
    final container = _container(_tasks());
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    // 4 MB completed track → should see "MB" in the banner
    expect(find.textContaining('MB'), findsOneWidget);
  });

  testWidgets('shows loading indicator while loading', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWith((_) => _FakeAuthService()),
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
        deviceIdProvider.overrideWith((_) async => 'test-dev'),
        downloadProvider.overrideWith(
          () => _LoadingDownloadNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    // Don't pump — state still loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('remove all button appears when downloads exist', (tester) async {
    final container = _container(_tasks());
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);
  });

  testWidgets('remove all button absent when no downloads', (tester) async {
    final container = _container([]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.byIcon(Icons.delete_sweep_outlined), findsNothing);
  });
}

// Returns state with isLoading = true to test the loading indicator.
class _LoadingDownloadNotifier extends DownloadNotifier {
  @override
  DownloadState build() => const DownloadState(isLoading: true);
}
