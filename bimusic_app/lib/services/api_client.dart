import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import 'auth_service.dart';

// ---------------------------------------------------------------------------
// Auth interceptor
// ---------------------------------------------------------------------------

/// Dio interceptor that:
/// 1. Attaches `Authorization: Bearer <jwt>` to every outgoing request.
/// 2. On 401: attempts token refresh once, retries the original request.
/// 3. On refresh failure: calls [onLogout] to force the user back to login.
/// 4. Uses a [Completer] to serialise concurrent refresh attempts.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.authService,
    required this.dio,
    required this.onLogout,
  });

  final AuthService authService;
  final Dio dio;
  final void Function() onLogout;

  Completer<bool>? _refreshCompleter;

  Future<bool> _ensureRefreshed() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();
    try {
      final tokens = await authService.refresh();
      final success = tokens != null;
      _refreshCompleter!.complete(success);
      return success;
    } catch (_) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = authService.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    final bool refreshed = await _ensureRefreshed();

    if (refreshed) {
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer ${authService.accessToken}';
      try {
        final response = await dio.fetch<dynamic>(options);
        handler.resolve(response);
        return;
      } on DioException catch (retryErr) {
        handler.next(retryErr);
        return;
      }
    }

    onLogout();
    handler.next(err);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Dio instance pre-configured with [AuthInterceptor].
/// Use this for all authenticated API calls.
final apiClientProvider = Provider<Dio>((ref) {
  final authService = ref.read(authServiceProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ),
  );
  dio.interceptors.add(
    AuthInterceptor(
      authService: authService,
      dio: dio,
      onLogout: () =>
          ref.read(authNotifierProvider.notifier).logout(),
    ),
  );
  return dio;
});
