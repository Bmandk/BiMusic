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

  @override
  Future<void> clearAllDownloads() async {
    state = state.copyWith(tasks: []);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DownloadTask _makeTask({
  required String serverId,
  required int trackId,
  required DownloadStatus status,
  String trackTitle = 'Track',
  String trackNumber = '1',
  String albumTitle = 'Great Album',
  String artistName = 'Great Artist',
  double? progress,
  int? fileSizeBytes,
  String? filePath,
  String? errorMessage,
}) =>
    DownloadTask(
      serverId: serverId,
      trackId: trackId,
      albumId: 10,
      artistId: 5,
      userId: 'u1',
      deviceId: 'dev-1',
      status: status,
      trackTitle: trackTitle,
      trackNumber: trackNumber,
      albumTitle: albumTitle,
      artistName: artistName,
      bitrate: 320,
      requestedAt: '2026-03-28T10:00:00Z',
      progress: progress,
      fileSizeBytes: fileSizeBytes,
      filePath: filePath,
      errorMessage: errorMessage,
    );

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
    final tasks = [
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.completed,
          trackTitle: 'First Track'),
      _makeTask(
          serverId: 's2',
          trackId: 2,
          status: DownloadStatus.downloading,
          trackTitle: 'Second Track',
          progress: 0.5),
    ];
    final container = _container(tasks);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.text('First Track'), findsOneWidget);
    expect(find.text('Second Track'), findsOneWidget);
  });

  testWidgets('shows album group header', (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.completed,
          albumTitle: 'Great Album',
          artistName: 'Great Artist'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.text('Great Album'), findsOneWidget);
    expect(find.text('Great Artist'), findsOneWidget);
  });

  testWidgets('storage usage banner shows used size', (tester) async {
    final container = _container([
      _makeTask(
        serverId: 's1',
        trackId: 1,
        status: DownloadStatus.completed,
        fileSizeBytes: 4 * 1024 * 1024,
        filePath: '/docs/1.mp3',
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.textContaining('MB'), findsOneWidget);
  });

  testWidgets('shows loading indicator while loading', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWith((_) => _FakeAuthService()),
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier()),
        deviceIdProvider.overrideWith((_) async => 'test-dev'),
        downloadProvider.overrideWith(() => _LoadingDownloadNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('remove all button appears when downloads exist', (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.completed),
    ]);
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

  testWidgets('shows pending task with schedule icon', (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1', trackId: 1, status: DownloadStatus.pending),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('shows downloading progress indicator for downloading task',
      (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.downloading,
          progress: 0.4),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    // LinearProgressIndicator for subtitle, CircularProgressIndicator for icon.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows completed icon for completed task', (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.completed,
          fileSizeBytes: 1024,
          filePath: '/docs/1.mp3'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.byIcon(Icons.download_done), findsWidgets);
  });

  testWidgets('shows failed task error message', (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.failed,
          errorMessage: 'Connection timed out'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.text('Connection timed out'), findsOneWidget);
  });

  testWidgets('shows refresh icon button for failed task', (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.failed,
          errorMessage: 'Error'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('remove all dialog appears when tapping delete sweep icon',
      (tester) async {
    final container = _container([
      _makeTask(serverId: 's1', trackId: 1, status: DownloadStatus.completed),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Remove all downloads?'), findsOneWidget);
    expect(find.text('Remove all'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('cancelling remove all dialog leaves downloads intact',
      (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.completed,
          trackTitle: 'My Track'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('My Track'), findsOneWidget);
  });

  testWidgets('confirming remove all clears the download list', (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.completed,
          trackTitle: 'My Track'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove all'));
    await tester.pumpAndSettle();

    expect(find.text('No downloads yet'), findsOneWidget);
  });

  testWidgets('shows album delete button per group', (tester) async {
    final container = _container([
      _makeTask(serverId: 's1', trackId: 1, status: DownloadStatus.completed),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.byIcon(Icons.delete_outline), findsWidgets);
  });

  testWidgets('album delete dialog appears when tapping album delete button',
      (tester) async {
    final container = _container([
      _makeTask(serverId: 's1', trackId: 1, status: DownloadStatus.completed,
          albumTitle: 'My Album'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    // The album delete icon button (smaller size 20).
    final deleteIcons = find.byIcon(Icons.delete_outline);
    await tester.tap(deleteIcons.first);
    await tester.pumpAndSettle();

    expect(find.text('Remove album?'), findsOneWidget);
  });

  testWidgets('shows correct track count in empty storage banner',
      (tester) async {
    final container = _container([]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    // 0 tracks shown
    expect(find.textContaining('0 tracks'), findsOneWidget);
  });

  testWidgets('shows singular "track" in storage banner for 1 track',
      (tester) async {
    final container = _container([
      _makeTask(
          serverId: 's1',
          trackId: 1,
          status: DownloadStatus.completed,
          fileSizeBytes: 1024 * 1024,
          filePath: '/docs/1.mp3'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildSubject(container));
    await tester.pump();

    expect(find.textContaining('1 track'), findsOneWidget);
  });
}

// Returns state with isLoading = true to test the loading indicator.
class _LoadingDownloadNotifier extends DownloadNotifier {
  @override
  DownloadState build() => const DownloadState(isLoading: true);
}
