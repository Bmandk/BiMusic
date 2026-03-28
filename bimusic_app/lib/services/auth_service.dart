import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';
import '../models/auth_tokens.dart';
import '../models/user.dart';

class AuthService {
  AuthService(this._storage);

  final FlutterSecureStorage _storage;

  // Separate Dio instance for auth endpoints — never goes through AuthInterceptor.
  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ),
  );

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
  /// Returns [AuthTokens] on success, or null if the token is missing/expired.
  Future<AuthTokens?> refresh() async {
    final storedRefresh = await _storage.read(key: _kRefreshToken);
    if (storedRefresh == null) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        data: {'refreshToken': storedRefresh},
      );
      final tokens = _buildTokens(response.data!);
      await storeTokens(tokens);
      return tokens;
    } on DioException {
      return null;
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
      isAdmin: map['isAdmin'] as bool,
    );
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(const FlutterSecureStorage());
});
