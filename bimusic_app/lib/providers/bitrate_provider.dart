import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connectivity_provider.dart';

/// Returns 320 on WiFi, 128 on mobile/none (selected once at play time).
final bitrateProvider = Provider<int>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.when(
    data: (result) => result == ConnectivityResult.wifi ? 320 : 128,
    loading: () => 128,
    error: (_, __) => 128,
  );
});
