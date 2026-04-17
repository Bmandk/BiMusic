import 'dart:async';
import 'dart:convert';

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
    final svc = ref.read(authServiceProvider);
    final stored = await svc.readStoredTokens();
    if (stored == null) {
      state = const AuthStateUnauthenticated();
      return;
    }
    final refreshed = await svc.refresh();
    if (refreshed == null) {
      await svc.clearTokens();
      state = const AuthStateUnauthenticated();
      return;
    }
    state = AuthStateAuthenticated(refreshed);
    _scheduleTokenRefresh(refreshed);
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
    try {
      final refreshed = await svc.refresh();
      // Bail out if logout was called while the refresh was in-flight.
      if (state is AuthStateUnauthenticated) return;
      if (refreshed != null) {
        state = AuthStateAuthenticated(refreshed);
        _scheduleTokenRefresh(refreshed);
      } else {
        await svc.clearTokens();
        state = const AuthStateUnauthenticated();
      }
    } catch (_) {
      // Network error — retry in 30 s rather than logging the user out.
      if (state is AuthStateUnauthenticated) return;
      _refreshTimer = Timer(const Duration(seconds: 30), _backgroundRefresh);
    }
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
