import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';

/// Normalises a raw URL string: trims whitespace, strips trailing slashes,
/// and enforces http/https scheme. Throws a [String] error message on failure.
@visibleForTesting
String normalizeBackendUrl(String raw) {
  var url = raw.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    throw 'URL must start with http:// or https://';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

class BackendUrlNotifier extends AsyncNotifier<String?> {
  static const _kStorageKey = 'bimusic_backend_url';

  @override
  Future<String?> build() async {
    const storage = FlutterSecureStorage();
    return storage.read(key: _kStorageKey);
  }

  /// Validates [raw] by pinging its /api/health endpoint, then persists it.
  /// Throws a [String] error message on validation failure.
  Future<void> setUrl(String raw) async {
    final normalized = normalizeBackendUrl(raw);

    final dio = Dio(
      BaseOptions(
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
      ),
    );
    try {
      final response = await dio.get<dynamic>('$normalized/api/health');
      if (response.statusCode == null || response.statusCode! >= 400) {
        throw 'Server returned ${response.statusCode}';
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw 'Connection timed out. Check the URL and try again.';
      }
      throw 'Could not reach server: ${e.message}';
    } finally {
      dio.close();
    }

    const storage = FlutterSecureStorage();
    await storage.write(key: _kStorageKey, value: normalized);
    state = AsyncData(normalized);
  }

  Future<void> clearUrl() async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: _kStorageKey);
    state = const AsyncData(null);
  }

}

final backendUrlProvider =
    AsyncNotifierProvider<BackendUrlNotifier, String?>(BackendUrlNotifier.new);
