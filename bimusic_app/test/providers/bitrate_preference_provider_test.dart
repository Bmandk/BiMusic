import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/providers/bitrate_preference_provider.dart';

// ---------------------------------------------------------------------------
// Stub: overrides build() only, leaving setPreference() inherited so the real
// implementation is exercised (and counted for coverage).
// ---------------------------------------------------------------------------

class _StubBitratePreferenceNotifier extends BitratePreferenceNotifier {
  _StubBitratePreferenceNotifier(this._initial);
  final BitratePreference _initial;

  @override
  BitratePreference build() => _initial;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Register a no-op mock for the flutter_secure_storage channel so reads
    // return null and writes succeed silently in the test environment.
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

  group('BitratePreferenceNotifier.build() — real notifier', () {
    // Instantiate the real notifier (no override) so that build(), _load(),
    // and the early-return branch in _load() are all instrumented.
    // With TestWidgetsFlutterBinding, FlutterSecureStorage.read() returns null,
    // so _load() exits early and state stays at BitratePreference.auto.

    test('returns auto when no preference is stored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Synchronous read: build() returned auto immediately.
      expect(container.read(bitratePreferenceProvider), BitratePreference.auto);
      // Allow the fire-and-forget _load() to complete.
      await Future<void>.delayed(Duration.zero);
      // Storage returned null → state stays auto.
      expect(container.read(bitratePreferenceProvider), BitratePreference.auto);
    });
  });

  group('BitratePreferenceNotifier.setPreference() — via stub', () {
    // _StubBitratePreferenceNotifier only overrides build().
    // setPreference() is inherited from BitratePreferenceNotifier, so calling
    // it covers the real implementation lines.

    test('updates state to alwaysLow', () async {
      final container = ProviderContainer(
        overrides: [
          bitratePreferenceProvider.overrideWith(
            () => _StubBitratePreferenceNotifier(BitratePreference.auto),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(bitratePreferenceProvider.notifier)
          .setPreference(BitratePreference.alwaysLow);

      expect(container.read(bitratePreferenceProvider), BitratePreference.alwaysLow);
    });

    test('updates state to alwaysHigh', () async {
      final container = ProviderContainer(
        overrides: [
          bitratePreferenceProvider.overrideWith(
            () => _StubBitratePreferenceNotifier(BitratePreference.auto),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(bitratePreferenceProvider.notifier)
          .setPreference(BitratePreference.alwaysHigh);

      expect(container.read(bitratePreferenceProvider), BitratePreference.alwaysHigh);
    });

    test('can toggle between preferences', () async {
      final container = ProviderContainer(
        overrides: [
          bitratePreferenceProvider.overrideWith(
            () => _StubBitratePreferenceNotifier(BitratePreference.alwaysHigh),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(bitratePreferenceProvider.notifier)
          .setPreference(BitratePreference.alwaysLow);
      expect(container.read(bitratePreferenceProvider), BitratePreference.alwaysLow);

      await container
          .read(bitratePreferenceProvider.notifier)
          .setPreference(BitratePreference.auto);
      expect(container.read(bitratePreferenceProvider), BitratePreference.auto);
    });
  });

  group('BitratePreference enum', () {
    test('has exactly 3 values', () {
      expect(BitratePreference.values.length, 3);
    });

    test('names match storage keys', () {
      expect(BitratePreference.auto.name, 'auto');
      expect(BitratePreference.alwaysLow.name, 'alwaysLow');
      expect(BitratePreference.alwaysHigh.name, 'alwaysHigh');
    });
  });
}
