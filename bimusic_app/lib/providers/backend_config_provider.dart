import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';

/// Returns the backend's `HLS_SEGMENT_SECONDS` value by calling GET /api/health.
/// Falls back to 6 on any error (network failure, backend not yet configured,
/// old backend that doesn't expose the field) so callers always get a valid value.
final backendConfigProvider = FutureProvider<int>((ref) async {
  try {
    final dio = ref.watch(apiClientProvider);
    final resp = await dio.get<Map<String, dynamic>>('/api/health');
    final seconds = resp.data?['segmentSeconds'];
    if (seconds is int && seconds > 0) return seconds;
  } catch (_) {}
  return 6;
});
