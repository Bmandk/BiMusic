import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';

bool _isPrivateHost(String host) {
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
  if (RegExp(r'^10\.').hasMatch(host)) return true;
  if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host)) return true;
  if (RegExp(r'^192\.168\.').hasMatch(host)) return true;
  return false;
}

/// Normalises a raw URL string: trims whitespace, strips trailing slashes,
/// and enforces http/https scheme. HTTP is only permitted for loopback and
/// RFC-1918 private addresses to prevent JWT leakage over plain HTTP.
/// Throws a [String] error message on failure.
@visibleForTesting
String normalizeBackendUrl(String raw) {
  var url = raw.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    throw 'URL must start with http:// or https://';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.startsWith('http://') && !_isPrivateHost(Uri.parse(url).host)) {
    throw 'HTTP is only allowed for local/private addresses (e.g. 192.168.x.x). Use HTTPS for public hosts.';
  }
  return url;
}

class BackendUrlNotifier extends AsyncNotifier<String?> {
  static const _kStorageKey = 'bimusic_backend_url';

  @visibleForTesting
  FlutterSecureStorage buildStorage() => const FlutterSecureStorage();

  @visibleForTesting
  Dio Function() dioFactory = () => Dio(
        BaseOptions(
          connectTimeout: ApiConfig.connectTimeout,
          receiveTimeout: ApiConfig.receiveTimeout,
        ),
      );

  @override
  Future<String?> build() async {
    return buildStorage().read(key: _kStorageKey);
  }

  /// Validates [raw] by pinging its /api/health endpoint, then persists it.
  /// Throws a [String] error message on validation failure.
  Future<void> setUrl(String raw) async {
    final normalized = normalizeBackendUrl(raw);

    final dio = dioFactory();
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

    await buildStorage().write(key: _kStorageKey, value: normalized);
    state = AsyncData(normalized);
  }

  Future<void> clearUrl() async {
    await buildStorage().delete(key: _kStorageKey);
    state = const AsyncData(null);
  }
}

final backendUrlProvider =
    AsyncNotifierProvider<BackendUrlNotifier, String?>(BackendUrlNotifier.new);
