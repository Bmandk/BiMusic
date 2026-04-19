import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MinimizeToTrayNotifier extends Notifier<bool> {
  static const _kStorageKey = 'bimusic_minimize_to_tray';

  @override
  bool build() {
    _load();
    return true; // default ON
  }

  Future<void> _load() async {
    const storage = FlutterSecureStorage();
    final value = await storage.read(key: _kStorageKey);
    if (value != null) state = value == 'true';
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    const storage = FlutterSecureStorage();
    await storage.write(key: _kStorageKey, value: value.toString());
  }
}

final minimizeToTrayProvider =
    NotifierProvider<MinimizeToTrayNotifier, bool>(
  MinimizeToTrayNotifier.new,
);
