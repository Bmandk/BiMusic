import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../providers/backend_url_provider.dart';
import 'auth_service.dart';

// ---------------------------------------------------------------------------
// Auth interceptor
// ---------------------------------------------------------------------------

/// Dio interceptor that:
/// 1. Attaches `Authorization: Bearer <jwt>` to every outgoing request.
/// 2. On 401: attempts token refresh (single-flight lives in [AuthService]).
/// 3. On server rejection: calls [onLogout] to force the user back to login.
/// 4. On transient network failure: forwards the 401 without logging out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.authService,
    required this.dio,
    required this.onLogout,
  });

  final AuthService authService;
  final Dio dio;
  final void Function() onLogout;

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

    final result = await authService.refresh();

    switch (result.outcome) {
      case RefreshOutcome.success:
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
      case RefreshOutcome.rejected:
        onLogout();
        handler.next(err);
      case RefreshOutcome.transient:
        // Network failure — don't log out. The user keeps their session;
        // they'll see a failed request but remain authenticated.
        handler.next(err);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Dio instance pre-configured with [AuthInterceptor].
/// Use this for all authenticated API calls.
final apiClientProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(backendUrlProvider).valueOrNull;
  if (baseUrl == null) {
    throw StateError(
      'apiClientProvider accessed before backend URL was configured',
    );
  }
  final authService = ref.read(authServiceProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
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
