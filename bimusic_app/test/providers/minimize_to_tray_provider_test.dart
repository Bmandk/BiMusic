import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/providers/minimize_to_tray_provider.dart';

class _StubMinimizeToTrayNotifier extends MinimizeToTrayNotifier {
  _StubMinimizeToTrayNotifier(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  group('MinimizeToTrayNotifier.build() — real notifier', () {
    test('returns true (default ON) when no preference is stored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(minimizeToTrayProvider), true);
      await Future<void>.delayed(Duration.zero);
      // Storage returned null → state stays at default true.
      expect(container.read(minimizeToTrayProvider), true);
    });
  });

  group('MinimizeToTrayNotifier.setEnabled() — via stub', () {
    test('sets state to false', () async {
      final container = ProviderContainer(
        overrides: [
          minimizeToTrayProvider.overrideWith(
            () => _StubMinimizeToTrayNotifier(true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(minimizeToTrayProvider.notifier)
          .setEnabled(false);

      expect(container.read(minimizeToTrayProvider), false);
    });

    test('sets state to true', () async {
      final container = ProviderContainer(
        overrides: [
          minimizeToTrayProvider.overrideWith(
            () => _StubMinimizeToTrayNotifier(false),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(minimizeToTrayProvider.notifier)
          .setEnabled(true);

      expect(container.read(minimizeToTrayProvider), true);
    });

    test('can toggle between enabled and disabled', () async {
      final container = ProviderContainer(
        overrides: [
          minimizeToTrayProvider.overrideWith(
            () => _StubMinimizeToTrayNotifier(true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(minimizeToTrayProvider.notifier)
          .setEnabled(false);
      expect(container.read(minimizeToTrayProvider), false);

      await container
          .read(minimizeToTrayProvider.notifier)
          .setEnabled(true);
      expect(container.read(minimizeToTrayProvider), true);
    });
  });
}
