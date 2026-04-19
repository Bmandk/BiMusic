import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';
import '../models/auth_tokens.dart';
import '../models/user.dart';
import '../providers/backend_url_provider.dart';

enum RefreshOutcome { success, rejected, transient }

class RefreshResult {
  const RefreshResult(this.outcome, [this.tokens]);
  final RefreshOutcome outcome;
  final AuthTokens? tokens;
}

class AuthService {
  AuthService(this._storage, String baseUrl, {Dio? httpClient})
      : _dio = httpClient ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: ApiConfig.connectTimeout,
                receiveTimeout: ApiConfig.receiveTimeout,
              ),
            );

  final FlutterSecureStorage _storage;
  final Dio _dio;

  Future<RefreshResult>? _inflight;
  String? _accessToken;

  /// The current in-memory access token, used by [AuthInterceptor].
  String? get accessToken => _accessToken;

  static const _kAccessToken = 'bimusic_access_token';
  static const _kRefreshToken = 'bimusic_refresh_token';

  /// Log in with [username] and [password]. Returns [AuthTokens] on success.
  /// Throws [DioException] on invalid credentials.
  Future<AuthTokens> login(String username, String password) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'username': username, 'password': password},
    );
    final tokens = _buildTokens(response.data!);
    await storeTokens(tokens);
    return tokens;
  }

  /// Attempt to refresh tokens using the stored refresh token.
  ///
  /// Returns [RefreshResult] with outcome:
  /// - [RefreshOutcome.success]: new tokens were issued and stored.
  /// - [RefreshOutcome.rejected]: server rejected the token (HTTP 4xx) — session is dead.
  /// - [RefreshOutcome.transient]: network/transport error — session may still be valid.
  ///
  /// Concurrent calls share a single in-flight request (single-flight).
  Future<RefreshResult> refresh() async {
    if (_inflight != null) return _inflight!;

    // Set _inflight before any await so concurrent callers immediately join
    // this in-flight future rather than starting a second refresh request.
    final completer = Completer<RefreshResult>();
    _inflight = completer.future;
    try {
      final storedRefresh = await _storage.read(key: _kRefreshToken);
      if (storedRefresh == null) {
        const result = RefreshResult(RefreshOutcome.rejected);
        completer.complete(result);
        return result;
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        data: {'refreshToken': storedRefresh},
      );
      final tokens = _buildTokens(response.data!);
      await storeTokens(tokens);
      final result = RefreshResult(RefreshOutcome.success, tokens);
      completer.complete(result);
      return result;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final result =
          (statusCode != null && statusCode >= 400 && statusCode < 500)
              ? const RefreshResult(RefreshOutcome.rejected)
              : const RefreshResult(RefreshOutcome.transient);
      completer.complete(result);
      return result;
    } catch (_) {
      const result = RefreshResult(RefreshOutcome.transient);
      completer.complete(result);
      return result;
    } finally {
      _inflight = null;
    }
  }

  /// Log out the current user. Revokes the refresh token on the server and
  /// clears local storage. Errors during the server call are silently ignored.
  Future<void> logout() async {
    final storedRefresh = await _storage.read(key: _kRefreshToken);
    if (storedRefresh != null && _accessToken != null) {
      try {
        await _dio.post<void>(
          '/api/auth/logout',
          data: {'refreshToken': storedRefresh},
          options: Options(
            headers: {'Authorization': 'Bearer $_accessToken'},
          ),
        );
      } catch (_) {}
    }
    await clearTokens();
  }

  /// Persist [tokens] to secure storage and update the in-memory token.
  Future<void> storeTokens(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
    await Future.wait([
      _storage.write(key: _kAccessToken, value: tokens.accessToken),
      _storage.write(key: _kRefreshToken, value: tokens.refreshToken),
    ]);
  }

  /// Delete all stored tokens and clear the in-memory token.
  Future<void> clearTokens() async {
    _accessToken = null;
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
    ]);
  }

  /// Read tokens from secure storage. Returns null if not found.
  /// Updates the in-memory access token on success.
  Future<AuthTokens?> readStoredTokens() async {
    final accessToken = await _storage.read(key: _kAccessToken);
    final refreshToken = await _storage.read(key: _kRefreshToken);
    if (accessToken == null || refreshToken == null) return null;
    _accessToken = accessToken;
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: _userFromJwt(accessToken),
    );
  }

  AuthTokens _buildTokens(Map<String, dynamic> data) {
    final accessToken = data['accessToken'] as String;
    final refreshToken = data['refreshToken'] as String;
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: _userFromJwt(accessToken),
    );
  }

  /// Decode the JWT payload (without verification) to extract user fields.
  User _userFromJwt(String token) {
    final parts = token.split('.');
    final payload = base64Url.normalize(parts[1]);
    final map = jsonDecode(utf8.decode(base64Url.decode(payload)))
        as Map<String, dynamic>;
    return User(
      userId: map['userId'] as String,
      username: map['username'] as String,
      isAdmin: map['isAdmin'] == true,
    );
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final url = ref.watch(backendUrlProvider).valueOrNull ?? '';
  return AuthService(const FlutterSecureStorage(), url);
});
