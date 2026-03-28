import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// Bitrate preference
// ---------------------------------------------------------------------------

enum BitratePreference {
  /// Automatic: 320 kbps on WiFi, 128 kbps on cellular/none.
  auto,

  /// Always stream at 128 kbps regardless of connection.
  alwaysLow,

  /// Always stream at 320 kbps regardless of connection.
  alwaysHigh,
}

class BitratePreferenceNotifier extends Notifier<BitratePreference> {
  static const _kStorageKey = 'bimusic_bitrate_preference';

  @override
  BitratePreference build() {
    _load();
    return BitratePreference.auto;
  }

  Future<void> _load() async {
    const storage = FlutterSecureStorage();
    final value = await storage.read(key: _kStorageKey);
    if (value == null) return;
    final pref = BitratePreference.values.where((e) => e.name == value).firstOrNull;
    if (pref != null) state = pref;
  }

  Future<void> setPreference(BitratePreference pref) async {
    state = pref;
    const storage = FlutterSecureStorage();
    await storage.write(key: _kStorageKey, value: pref.name);
  }
}

final bitratePreferenceProvider =
    NotifierProvider<BitratePreferenceNotifier, BitratePreference>(
  BitratePreferenceNotifier.new,
);
