import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/user.dart';
import 'package:bimusic_app/services/auth_service.dart';

// ---------------------------------------------------------------------------
// Fake FlutterSecureStorage (avoids platform channels)
// ---------------------------------------------------------------------------

class _FakeStorage extends Fake implements FlutterSecureStorage {
  final _store = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a fake JWT whose payload contains the given fields.
String _makeJwt({
  required String userId,
  required String username,
  required bool isAdmin,
}) {
  final payloadJson =
      '{"userId":"$userId","username":"$username","isAdmin":$isAdmin}';
  final payload =
      base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');
  return 'eyJhbGciOiJIUzI1NiJ9.$payload.fakesig';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeStorage fakeStorage;
  late AuthService service;

  setUp(() {
    fakeStorage = _FakeStorage();
    service = AuthService(fakeStorage);
  });

  group('accessToken', () {
    test('is null initially', () {
      expect(service.accessToken, isNull);
    });
  });

  group('storeTokens', () {
    test('sets in-memory accessToken and writes both tokens to storage',
        () async {
      final access = _makeJwt(userId: 'u1', username: 'admin', isAdmin: true);
      final tokens = AuthTokens(
        accessToken: access,
        refreshToken: 'refresh-token',
        user: const User(userId: 'u1', username: 'admin', isAdmin: true),
      );

      await service.storeTokens(tokens);

      expect(service.accessToken, access);
      expect(fakeStorage._store['bimusic_access_token'], access);
      expect(fakeStorage._store['bimusic_refresh_token'], 'refresh-token');
    });
  });

  group('clearTokens', () {
    test('clears in-memory accessToken and removes both tokens from storage',
        () async {
      final access = _makeJwt(userId: 'u1', username: 'admin', isAdmin: true);
      fakeStorage._store['bimusic_access_token'] = access;
      fakeStorage._store['bimusic_refresh_token'] = 'refresh-token';

      await service.clearTokens();

      expect(service.accessToken, isNull);
      expect(fakeStorage._store.containsKey('bimusic_access_token'), isFalse);
      expect(fakeStorage._store.containsKey('bimusic_refresh_token'), isFalse);
    });
  });

  group('readStoredTokens', () {
    test('returns null when no tokens are stored', () async {
      final result = await service.readStoredTokens();
      expect(result, isNull);
    });

    test('returns null when only access token is stored', () async {
      fakeStorage._store['bimusic_access_token'] = 'only-access';

      final result = await service.readStoredTokens();
      expect(result, isNull);
    });

    test('returns null when only refresh token is stored', () async {
      fakeStorage._store['bimusic_refresh_token'] = 'only-refresh';

      final result = await service.readStoredTokens();
      expect(result, isNull);
    });

    test('returns AuthTokens and updates in-memory token when both are stored',
        () async {
      final access =
          _makeJwt(userId: 'u2', username: 'bob', isAdmin: false);
      fakeStorage._store['bimusic_access_token'] = access;
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      final result = await service.readStoredTokens();

      expect(result, isNotNull);
      expect(result!.accessToken, access);
      expect(result.refreshToken, 'stored-refresh');
      expect(result.user.userId, 'u2');
      expect(result.user.username, 'bob');
      expect(result.user.isAdmin, isFalse);
      // In-memory token is updated too.
      expect(service.accessToken, access);
    });

    test('decodes admin flag from JWT payload', () async {
      final access =
          _makeJwt(userId: 'u3', username: 'superuser', isAdmin: true);
      fakeStorage._store['bimusic_access_token'] = access;
      fakeStorage._store['bimusic_refresh_token'] = 'r';

      final result = await service.readStoredTokens();

      expect(result!.user.isAdmin, isTrue);
    });
  });

  group('refresh', () {
    test('returns null immediately when no refresh token is stored', () async {
      // Storage is empty — no HTTP call should be made.
      final result = await service.refresh();
      expect(result, isNull);
    });
  });

  group('logout', () {
    test('clears tokens even when no tokens are stored', () async {
      // Neither storage entry nor in-memory token exists — no HTTP call.
      await service.logout();

      // Storage should still be clean.
      expect(fakeStorage._store.containsKey('bimusic_access_token'), isFalse);
      expect(fakeStorage._store.containsKey('bimusic_refresh_token'), isFalse);
      expect(service.accessToken, isNull);
    });

    test('clears tokens when refresh is stored but in-memory token is null',
        () async {
      // Store a refresh token but leave _accessToken null — HTTP call is skipped.
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      await service.logout();

      expect(fakeStorage._store.containsKey('bimusic_refresh_token'), isFalse);
      expect(service.accessToken, isNull);
    });
  });
}
