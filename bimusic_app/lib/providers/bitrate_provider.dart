import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bitrate_preference_provider.dart';
import 'connectivity_provider.dart';

/// Returns the effective bitrate (128 or 320) based on user preference and
/// current connectivity. Read once at play time — do not watch.
final bitrateProvider = Provider<int>((ref) {
  final pref = ref.watch(bitratePreferenceProvider);

  switch (pref) {
    case BitratePreference.alwaysLow:
      return 128;
    case BitratePreference.alwaysHigh:
      return 320;
    case BitratePreference.auto:
      final connectivity = ref.watch(connectivityProvider);
      return connectivity.when(
        data: (result) => result == ConnectivityResult.wifi ? 320 : 128,
        loading: () => 128,
        error: (_, __) => 128,
      );
  }
});
