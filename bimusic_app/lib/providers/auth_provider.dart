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

  /// Resolves once the startup token-validation check completes.
  Future<void> get initialized => _initialized;

  @override
  AuthState build() {
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
  }

  /// Log in. Sets state to [AuthStateAuthenticated] on success.
  /// Rethrows on failure so callers can display error messages.
  Future<void> login(String username, String password) async {
    state = const AuthStateLoading();
    try {
      final tokens =
          await ref.read(authServiceProvider).login(username, password);
      state = AuthStateAuthenticated(tokens);
    } catch (_) {
      state = const AuthStateUnauthenticated();
      rethrow;
    }
  }

  /// Log out and clear state.
  Future<void> logout() async {
    await ref.read(authServiceProvider).logout();
    state = const AuthStateUnauthenticated();
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
