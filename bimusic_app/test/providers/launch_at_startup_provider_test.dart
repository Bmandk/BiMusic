import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/providers/launch_at_startup_provider.dart';

// Stub overrides build() only — setEnabled() and syncWithOs() use the real
// implementations (and count for coverage).
class _StubLaunchAtStartupNotifier extends LaunchAtStartupNotifier {
  _StubLaunchAtStartupNotifier(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Mock flutter_secure_storage channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
    // Mock launch_at_startup channel — isEnabled() returns false.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('launch_at_startup'),
      (MethodCall call) async {
        if (call.method == 'isEnabled') return false;
        return null;
      },
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('launch_at_startup'),
      null,
    );
  });

  group('LaunchAtStartupNotifier.build() — real notifier', () {
    test('returns false when no preference is stored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(launchAtStartupProvider), false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(launchAtStartupProvider), false);
    });
  });

  group('LaunchAtStartupNotifier.setEnabled() — via stub', () {
    test('sets state to true', () async {
      final container = ProviderContainer(
        overrides: [
          launchAtStartupProvider.overrideWith(
            () => _StubLaunchAtStartupNotifier(false),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(launchAtStartupProvider.notifier)
          .setEnabled(true);

      expect(container.read(launchAtStartupProvider), true);
    });

    test('sets state to false', () async {
      final container = ProviderContainer(
        overrides: [
          launchAtStartupProvider.overrideWith(
            () => _StubLaunchAtStartupNotifier(true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(launchAtStartupProvider.notifier)
          .setEnabled(false);

      expect(container.read(launchAtStartupProvider), false);
    });

    test('can toggle between enabled and disabled', () async {
      final container = ProviderContainer(
        overrides: [
          launchAtStartupProvider.overrideWith(
            () => _StubLaunchAtStartupNotifier(false),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(launchAtStartupProvider.notifier)
          .setEnabled(true);
      expect(container.read(launchAtStartupProvider), true);

      await container
          .read(launchAtStartupProvider.notifier)
          .setEnabled(false);
      expect(container.read(launchAtStartupProvider), false);
    });
  });
}
