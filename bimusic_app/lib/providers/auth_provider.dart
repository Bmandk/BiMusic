import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_tokens.dart';
import '../services/auth_service.dart';

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

sealed class AuthState {
  const AuthState();
}

class AuthStateLoading extends AuthState {
  const AuthStateLoading();
}

class AuthStateUnauthenticated extends AuthState {
  const AuthStateUnauthenticated();
}

class AuthStateAuthenticated extends AuthState {
  const AuthStateAuthenticated(this.tokens);
  final AuthTokens tokens;
}

// ---------------------------------------------------------------------------
// Auth notifier
// ---------------------------------------------------------------------------

class AuthNotifier extends Notifier<AuthState> {
  late Future<void> _initialized;
  Timer? _refreshTimer;

  /// Resolves once the startup token-validation check completes.
  Future<void> get initialized => _initialized;

  @override
  AuthState build() {
    ref.onDispose(() => _refreshTimer?.cancel());
    _initialized = _init();
    return const AuthStateLoading();
  }

  Future<void> _init() async {
    dev.log('_init(): starting auth startup check', name: 'BiMusic.Auth');
    final svc = ref.read(authServiceProvider);
    final stored = await svc.readStoredTokens();

    if (stored == null) {
      // readStoredTokens() requires both tokens. On Windows, the access token
      // may not persist across restarts while the refresh token does. If we
      // have a refresh token, attempt a refresh to rebuild the session.
      final hasRefresh = await svc.hasStoredRefreshToken();
      if (!hasRefresh) {
        dev.log('_init(): no stored tokens → unauthenticated', name: 'BiMusic.Auth');
        state = const AuthStateUnauthenticated();
        return;
      }
      dev.log('_init(): access token missing but refresh token present — attempting refresh', name: 'BiMusic.Auth');
      final result = await svc.refresh();
      dev.log('_init(): refresh outcome=${result.outcome.name}', name: 'BiMusic.Auth');
      switch (result.outcome) {
        case RefreshOutcome.success:
          dev.log('_init(): → authenticated (refreshed from refresh-token-only state)', name: 'BiMusic.Auth');
          state = AuthStateAuthenticated(result.tokens!);
          _scheduleTokenRefresh(result.tokens!);
        case RefreshOutcome.rejected:
          dev.log('_init(): → unauthenticated (refresh rejected)', name: 'BiMusic.Auth');
          await svc.clearTokens();
          state = const AuthStateUnauthenticated();
        case RefreshOutcome.transient:
          // No access token and network unavailable — can't reconstruct session.
          dev.log('_init(): → unauthenticated (transient error, no access token to fall back on)', name: 'BiMusic.Auth');
          state = const AuthStateUnauthenticated();
      }
      return;
    }

    dev.log('_init(): stored tokens found for user="${stored.user.username}", attempting refresh', name: 'BiMusic.Auth');
    final result = await svc.refresh();
    dev.log('_init(): refresh outcome=${result.outcome.name}', name: 'BiMusic.Auth');
    switch (result.outcome) {
      case RefreshOutcome.success:
        dev.log('_init(): → authenticated (refreshed)', name: 'BiMusic.Auth');
        state = AuthStateAuthenticated(result.tokens!);
        _scheduleTokenRefresh(result.tokens!);
      case RefreshOutcome.rejected:
        dev.log('_init(): → unauthenticated (refresh rejected)', name: 'BiMusic.Auth');
        await svc.clearTokens();
        state = const AuthStateUnauthenticated();
      case RefreshOutcome.transient:
        dev.log('_init(): → authenticated (transient error, keeping stored session)', name: 'BiMusic.Auth');
        // Network/transport failure on launch — keep stored session alive.
        // The interceptor will refresh when the next request goes out.
        state = AuthStateAuthenticated(stored);
        _scheduleTokenRefresh(stored);
    }
  }

  /// Log in. Sets state to [AuthStateAuthenticated] on success.
  /// Rethrows on failure so callers can display error messages.
  Future<void> login(String username, String password) async {
    state = const AuthStateLoading();
    try {
      final tokens =
          await ref.read(authServiceProvider).login(username, password);
      state = AuthStateAuthenticated(tokens);
      _scheduleTokenRefresh(tokens);
    } catch (_) {
      state = const AuthStateUnauthenticated();
      rethrow;
    }
  }

  /// Log out and clear state.
  Future<void> logout() async {
    _refreshTimer?.cancel();
    await ref.read(authServiceProvider).logout();
    state = const AuthStateUnauthenticated();
  }

  // ---------------------------------------------------------------------------
  // Proactive token refresh
  // ---------------------------------------------------------------------------

  /// Schedules a background refresh ~2 minutes before the access token expires.
  void _scheduleTokenRefresh(AuthTokens tokens) {
    _refreshTimer?.cancel();
    final delay = _refreshDelay(tokens.accessToken);
    if (delay == null) return;
    if (delay <= Duration.zero) {
      _backgroundRefresh();
      return;
    }
    _refreshTimer = Timer(delay, _backgroundRefresh);
  }

  /// How long to wait before refreshing: token expiry minus a 2-minute buffer.
  Duration? _refreshDelay(String accessToken) {
    try {
      final parts = accessToken.split('.');
      if (parts.length < 2) return null;
      final padded = base64Url.normalize(parts[1]);
      final map = jsonDecode(
        utf8.decode(base64Url.decode(padded)),
      ) as Map<String, dynamic>;
      final exp = map['exp'] as int?;
      if (exp == null) return null;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      return expiry
          .subtract(const Duration(minutes: 2))
          .difference(DateTime.now().toUtc());
    } catch (_) {
      return null;
    }
  }

  Future<void> _backgroundRefresh() async {
    final svc = ref.read(authServiceProvider);
    final result = await svc.refresh();
    // Bail out if logout was called while the refresh was in-flight.
    if (state is AuthStateUnauthenticated) return;
    switch (result.outcome) {
      case RefreshOutcome.success:
        state = AuthStateAuthenticated(result.tokens!);
        _scheduleTokenRefresh(result.tokens!);
      case RefreshOutcome.rejected:
        await svc.clearTokens();
        state = const AuthStateUnauthenticated();
      case RefreshOutcome.transient:
        // Network error — retry in 30 s rather than logging the user out.
        _refreshTimer = Timer(const Duration(seconds: 30), _backgroundRefresh);
    }
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
