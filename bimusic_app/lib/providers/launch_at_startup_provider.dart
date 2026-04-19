import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

class LaunchAtStartupNotifier extends Notifier<bool> {
  static const _kStorageKey = 'bimusic_launch_at_startup';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    const storage = FlutterSecureStorage();
    final value = await storage.read(key: _kStorageKey);
    if (value == 'true') state = true;
  }

  /// Reads the current OS autostart state and syncs stored preference to match.
  /// Must be called after [LaunchAtStartup.instance.setup()] has been invoked.
  Future<void> syncWithOs() async {
    // Silently skipped on platforms where autostart is not supported.
    try {
      final enabled = await LaunchAtStartup.instance.isEnabled();
      const storage = FlutterSecureStorage();
      state = enabled;
      await storage.write(key: _kStorageKey, value: enabled.toString());
    } on UnsupportedError {
      return;
    }
  }

  Future<void> setEnabled(bool value) async {
    // Attempt OS call first so state/storage only update on success.
    try {
      if (value) {
        await LaunchAtStartup.instance.enable();
      } else {
        await LaunchAtStartup.instance.disable();
      }
    } on UnsupportedError {
      // Platform does not support launch at startup — persist preference anyway.
    } catch (_) {
      // OS call failed — leave state and storage unchanged.
      return;
    }
    state = value;
    const storage = FlutterSecureStorage();
    await storage.write(key: _kStorageKey, value: value.toString());
  }
}

final launchAtStartupProvider =
    NotifierProvider<LaunchAtStartupNotifier, bool>(
  LaunchAtStartupNotifier.new,
);
