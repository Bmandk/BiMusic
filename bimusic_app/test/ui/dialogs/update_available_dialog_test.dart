import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/update_info.dart';
import 'package:bimusic_app/providers/update_provider.dart';
import 'package:bimusic_app/services/update_installer.dart' show canSelfUpdateProvider;
import 'package:bimusic_app/ui/dialogs/update_available_dialog.dart';

// ---------------------------------------------------------------------------
// Stub notifier
// ---------------------------------------------------------------------------

class _StubUpdateNotifier extends Notifier<UpdateState>
    implements UpdateNotifier {
  _StubUpdateNotifier(this._state);
  final UpdateState _state;

  int installCalls = 0;
  int dismissCalls = 0;
  int cancelCalls = 0;

  @override
  UpdateState build() => _state;

  void setState(UpdateState s) => state = s;

  @override
  Future<void> checkOnLaunch() async {}
  @override
  Future<void> checkManual() async {}

  @override
  Future<void> installNow() async {
    installCalls++;
  }

  @override
  void cancelDownload() {
    cancelCalls++;
  }

  @override
  void dismiss() {
    dismissCalls++;
  }
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

const _currentVersion = SemVer(1, 0, 0);
const _latestVersion = SemVer(1, 1, 0);

const _testInfo = UpdateInfo(
  currentVersion: _currentVersion,
  latestVersion: _latestVersion,
  tagName: 'app-v1.1.0+5',
  releaseNotes: 'Fixed bugs\nAdded features',
  releaseUrl: 'https://github.com/Bmandk/BiMusic/releases/tag/app-v1.1.0+5',
  apkAssetUrl: 'https://example.com/app-release.apk',
  windowsAssetUrl: 'https://example.com/bimusic.zip',
);

Widget _buildDialog(_StubUpdateNotifier stub, {bool canSelfUpdate = false}) =>
    ProviderScope(
      overrides: [
        updateProvider.overrideWith(() => stub),
        canSelfUpdateProvider.overrideWithValue(canSelfUpdate),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: _DialogLauncher(),
        ),
      ),
    );

class _DialogLauncher extends ConsumerWidget {
  const _DialogLauncher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const UpdateAvailableDialog(info: _testInfo),
      ),
      child: const Text('Open'),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UpdateAvailableDialog', () {
    testWidgets('shows latest and current version', (tester) async {
      final stub = _StubUpdateNotifier(const UpdateAvailable(_testInfo));
      await tester.pumpWidget(_buildDialog(stub));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1.1.0'), findsWidgets);
      expect(find.textContaining('1.0.0'), findsWidgets);
    });

    testWidgets('shows release notes', (tester) async {
      final stub = _StubUpdateNotifier(const UpdateAvailable(_testInfo));
      await tester.pumpWidget(_buildDialog(stub));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Fixed bugs'), findsOneWidget);
    });

    testWidgets('shows Later and Install buttons', (tester) async {
      final stub = _StubUpdateNotifier(const UpdateAvailable(_testInfo));
      await tester.pumpWidget(_buildDialog(stub));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Install'), findsOneWidget);
    });

    testWidgets('tapping Later closes the dialog without calling dismiss',
        (tester) async {
      final stub = _StubUpdateNotifier(const UpdateAvailable(_testInfo));
      await tester.pumpWidget(_buildDialog(stub));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      // Dialog dismissed.
      expect(find.text('Later'), findsNothing);
      // dismiss() not called — state managed by dialog pop.
      expect(stub.dismissCalls, 0);
    });

    testWidgets('tapping Install calls installNow on the notifier',
        (tester) async {
      final stub = _StubUpdateNotifier(const UpdateAvailable(_testInfo));
      await tester.pumpWidget(_buildDialog(stub, canSelfUpdate: true));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Install'));
      await tester.pumpAndSettle();

      expect(stub.installCalls, 1);
    });

    testWidgets('shows progress bar and Cancel button while downloading',
        (tester) async {
      final stub = _StubUpdateNotifier(
        const UpdateDownloading(_testInfo, 0.42),
      );
      await tester.pumpWidget(_buildDialog(stub));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Install'), findsNothing);
    });

    testWidgets('tapping Cancel calls cancelDownload on the notifier',
        (tester) async {
      final stub = _StubUpdateNotifier(
        const UpdateDownloading(_testInfo, 0.5),
      );
      await tester.pumpWidget(_buildDialog(stub));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(stub.cancelCalls, 1);
    });

    testWidgets('shows error message and Dismiss button on UpdateError',
        (tester) async {
      final stub = _StubUpdateNotifier(
        const UpdateError('Download failed: timeout'),
      );
      await tester.pumpWidget(_buildDialog(stub));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Download failed'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.text('Install'), findsNothing);
    });

    testWidgets('auto-dismisses dialog when state transitions to UpdateInstalled',
        (tester) async {
      final stub = _StubUpdateNotifier(const UpdateAvailable(_testInfo));
      await tester.pumpWidget(_buildDialog(stub));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Later'), findsOneWidget);

      // Simulate the notifier transitioning to installed.
      stub.setState(const UpdateInstalled());
      await tester.pumpAndSettle();

      // Dialog should be dismissed automatically.
      expect(find.text('Later'), findsNothing);
    });
  });
}
