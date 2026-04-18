import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/update_info.dart';
import 'package:bimusic_app/providers/update_provider.dart';
import 'package:bimusic_app/services/github_release_client.dart';
import 'package:bimusic_app/services/update_installer.dart';

const _kCurrentVersion = SemVer(1, 0, 0);

// ---------------------------------------------------------------------------
// Fakes / stubs
// ---------------------------------------------------------------------------

class _FakeGitHubReleaseClient extends Fake implements GitHubReleaseClient {
  _FakeGitHubReleaseClient(this._payload);
  final Map<String, dynamic> _payload;

  @override
  Future<Map<String, dynamic>> fetchLatest() async => _payload;
}

class _ThrowingGitHubReleaseClient extends Fake
    implements GitHubReleaseClient {
  @override
  Future<Map<String, dynamic>> fetchLatest() async =>
      throw DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionTimeout,
      );
}

class _FakeUpdateInstaller extends Fake implements UpdateInstaller {
  int callCount = 0;
  double? lastProgress;

  @override
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    onProgress(0.5);
    lastProgress = 0.5;
    onProgress(1.0);
    lastProgress = 1.0;
  }
}

class _CancellingFakeInstaller extends Fake implements UpdateInstaller {
  @override
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.cancel,
    );
  }
}

Map<String, dynamic> _releasePayload({String tag = 'app-v9.9.9+1'}) => {
      'tag_name': tag,
      'body': 'Test release notes',
      'html_url': 'https://github.com/Bmandk/BiMusic/releases/tag/$tag',
      'assets': <dynamic>[],
    };

ProviderContainer _makeContainer({
  required GitHubReleaseClient client,
  required UpdateInstaller installer,
  SemVer currentVersion = _kCurrentVersion,
}) =>
    ProviderContainer(overrides: [
      currentVersionProvider.overrideWith((_) async => currentVersion),
      githubReleaseClientProvider.overrideWithValue(client),
      updateInstallerProvider.overrideWithValue(installer),
    ]);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // ConnectivityProvider uses platform channels.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('UpdateNotifier initial state', () {
    test('starts as UpdateIdle', () {
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(_releasePayload()),
        installer: _FakeUpdateInstaller(),
      );
      addTearDown(container.dispose);
      expect(container.read(updateProvider), isA<UpdateIdle>());
    });
  });

  group('checkManual', () {
    test('transitions idle → checking → available when newer version exists',
        () async {
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(_releasePayload(tag: 'app-v9.9.9+1')),
        installer: _FakeUpdateInstaller(),
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkManual();

      final state = container.read(updateProvider);
      expect(state, isA<UpdateAvailable>());
      final available = state as UpdateAvailable;
      expect(available.info.latestVersion, const SemVer(9, 9, 9));
    });

    test('transitions to UpdateUpToDate when version matches current',
        () async {
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(
            _releasePayload(tag: 'app-v$_kCurrentVersion+1')),
        installer: _FakeUpdateInstaller(),
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkManual();

      expect(container.read(updateProvider), isA<UpdateUpToDate>());
    });

    test('transitions to UpdateError on network failure', () async {
      final container = _makeContainer(
        client: _ThrowingGitHubReleaseClient(),
        installer: _FakeUpdateInstaller(),
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkManual();

      expect(container.read(updateProvider), isA<UpdateError>());
    });

    test('always re-runs even after a previous check', () async {
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(_releasePayload()),
        installer: _FakeUpdateInstaller(),
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkManual();
      await container.read(updateProvider.notifier).checkManual();

      // Still ends in a terminal state (no deadlock / crash).
      expect(container.read(updateProvider),
          anyOf(isA<UpdateAvailable>(), isA<UpdateUpToDate>(), isA<UpdateError>()));
    });
  });

  group('checkOnLaunch', () {
    test('runs the first time', () async {
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(_releasePayload()),
        installer: _FakeUpdateInstaller(),
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkOnLaunch();

      expect(container.read(updateProvider),
          anyOf(isA<UpdateAvailable>(), isA<UpdateUpToDate>()));
    });

    test('is a no-op on subsequent calls', () async {
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(_releasePayload()),
        installer: _FakeUpdateInstaller(),
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkOnLaunch();
      final afterFirst = container.read(updateProvider);

      // Simulate transitioning back to idle between calls.
      container.read(updateProvider.notifier).dismiss();

      await container.read(updateProvider.notifier).checkOnLaunch();
      // Still idle — second call was ignored.
      expect(container.read(updateProvider), isA<UpdateIdle>());

      // Verify first call produced a result.
      expect(afterFirst,
          anyOf(isA<UpdateAvailable>(), isA<UpdateUpToDate>()));
    });

    test('silences errors (state stays UpdateIdle)', () async {
      final container = _makeContainer(
        client: _ThrowingGitHubReleaseClient(),
        installer: _FakeUpdateInstaller(),
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkOnLaunch();

      expect(container.read(updateProvider), isA<UpdateIdle>());
    });
  });

  group('installNow', () {
    test('progresses through UpdateDownloading states and ends as UpdateInstalled',
        () async {
      final installer = _FakeUpdateInstaller();
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(_releasePayload()),
        installer: installer,
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkManual();
      expect(container.read(updateProvider), isA<UpdateAvailable>());

      final states = <UpdateState>[];
      container.listen(updateProvider, (_, s) => states.add(s));

      await container.read(updateProvider.notifier).installNow();

      expect(states.any((s) => s is UpdateDownloading), isTrue);
      expect(container.read(updateProvider), isA<UpdateInstalled>());
      expect(installer.callCount, 1);
    });

    test('is a no-op when state is not UpdateAvailable', () async {
      final installer = _FakeUpdateInstaller();
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(_releasePayload()),
        installer: installer,
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).installNow();

      expect(installer.callCount, 0);
      expect(container.read(updateProvider), isA<UpdateIdle>());
    });

    test('returns to UpdateAvailable when download is cancelled', () async {
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(_releasePayload()),
        installer: _CancellingFakeInstaller(),
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkManual();
      await container.read(updateProvider.notifier).installNow();

      expect(container.read(updateProvider), isA<UpdateAvailable>());
    });
  });

  group('dismiss', () {
    test('resets state to UpdateIdle', () async {
      final container = _makeContainer(
        client: _FakeGitHubReleaseClient(_releasePayload()),
        installer: _FakeUpdateInstaller(),
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkManual();
      expect(container.read(updateProvider), isA<UpdateAvailable>());

      container.read(updateProvider.notifier).dismiss();
      expect(container.read(updateProvider), isA<UpdateIdle>());
    });
  });
}
