import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';

// Strict IPv4 pattern — all four groups must be purely numeric digits so that
// hostnames like "10.example.com" are never mistaken for private IPs.
final _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

bool _isPrivateHost(String host) {
  if (host == 'localhost' || host == '::1') return true;
  final m = _ipv4.firstMatch(host);
  if (m == null) return false;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  if (a == 127) return true;                        // 127.0.0.0/8 loopback
  if (a == 10) return true;                         // 10.0.0.0/8
  if (a == 172 && b >= 16 && b <= 31) return true;  // 172.16.0.0/12
  if (a == 192 && b == 168) return true;             // 192.168.0.0/16
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
  if (url.startsWith('http://')) {
    final String host;
    try {
      host = Uri.parse(url).host;
    } on FormatException {
      throw 'Invalid URL format.';
    }
    if (!_isPrivateHost(host)) {
      throw 'HTTP is only allowed for local/private addresses (e.g. 192.168.x.x). Use HTTPS for public hosts.';
    }
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
