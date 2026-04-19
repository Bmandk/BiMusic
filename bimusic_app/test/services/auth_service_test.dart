import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/user.dart';
import 'package:bimusic_app/services/auth_service.dart';

// ---------------------------------------------------------------------------
// Fakes / mocks
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

class MockDio extends Mock implements Dio {}

class _FakeRequestOptions extends Fake implements RequestOptions {}

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

/// Builds a fake JWT where [isAdminRaw] is an arbitrary JSON value
/// (e.g. integer 1, integer 0) rather than a Dart bool literal.
String _makeJwtRaw({
  required String userId,
  required String username,
  required String isAdminRaw,
}) {
  final payloadJson =
      '{"userId":"$userId","username":"$username","isAdmin":$isAdminRaw}';
  final payload =
      base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');
  return 'eyJhbGciOiJIUzI1NiJ9.$payload.fakesig';
}

Response<Map<String, dynamic>> _makeRefreshResponse(String access, String refresh) =>
    Response<Map<String, dynamic>>(
      data: {'accessToken': access, 'refreshToken': refresh},
      requestOptions: RequestOptions(path: '/api/auth/refresh'),
      statusCode: 200,
    );

DioException _makeDioException(int statusCode) => DioException(
      requestOptions: RequestOptions(path: '/api/auth/refresh'),
      response: Response<dynamic>(
        statusCode: statusCode,
        requestOptions: RequestOptions(path: '/api/auth/refresh'),
      ),
      type: DioExceptionType.badResponse,
    );

DioException _makeConnectionError() => DioException(
      requestOptions: RequestOptions(path: '/api/auth/refresh'),
      type: DioExceptionType.connectionError,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeRequestOptions());
  });

  late _FakeStorage fakeStorage;
  late MockDio mockDio;
  late AuthService service;

  setUp(() {
    fakeStorage = _FakeStorage();
    mockDio = MockDio();
    service = AuthService(fakeStorage, 'http://test', httpClient: mockDio);
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

    test('decodes integer 1 isAdmin as true without throwing', () async {
      final access = _makeJwtRaw(userId: 'u4', username: 'admin2', isAdminRaw: '1');
      fakeStorage._store['bimusic_access_token'] = access;
      fakeStorage._store['bimusic_refresh_token'] = 'r';

      final result = await service.readStoredTokens();

      expect(result!.user.isAdmin, isFalse);
    });

    test('decodes integer 0 isAdmin as false without throwing', () async {
      final access = _makeJwtRaw(userId: 'u5', username: 'user2', isAdminRaw: '0');
      fakeStorage._store['bimusic_access_token'] = access;
      fakeStorage._store['bimusic_refresh_token'] = 'r';

      final result = await service.readStoredTokens();

      expect(result!.user.isAdmin, isFalse);
    });
  });

  group('refresh', () {
    test('returns rejected when no refresh token is stored', () async {
      final result = await service.refresh();
      expect(result.outcome, RefreshOutcome.rejected);
      verifyNever(() => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')));
    });

    test('returns success with new tokens on HTTP 200', () async {
      final access = _makeJwt(userId: 'u1', username: 'admin', isAdmin: false);
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      when(() => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenAnswer((_) async => _makeRefreshResponse(access, 'new-refresh'));

      final result = await service.refresh();

      expect(result.outcome, RefreshOutcome.success);
      expect(result.tokens?.accessToken, access);
      expect(result.tokens?.refreshToken, 'new-refresh');
      expect(fakeStorage._store['bimusic_access_token'], access);
      expect(fakeStorage._store['bimusic_refresh_token'], 'new-refresh');
    });

    test('returns rejected on HTTP 401', () async {
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      when(() => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(_makeDioException(401));

      final result = await service.refresh();

      expect(result.outcome, RefreshOutcome.rejected);
      expect(result.tokens, isNull);
    });

    test('returns rejected on HTTP 403', () async {
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      when(() => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(_makeDioException(403));

      final result = await service.refresh();

      expect(result.outcome, RefreshOutcome.rejected);
    });

    test('returns transient on connection error', () async {
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      when(() => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(_makeConnectionError());

      final result = await service.refresh();

      expect(result.outcome, RefreshOutcome.transient);
    });

    test('returns transient on HTTP 500', () async {
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      when(() => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(_makeDioException(500));

      final result = await service.refresh();

      expect(result.outcome, RefreshOutcome.transient);
    });

    test('does not clear storage on transient failure', () async {
      final access = _makeJwt(userId: 'u1', username: 'admin', isAdmin: false);
      fakeStorage._store['bimusic_access_token'] = access;
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      when(() => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(_makeConnectionError());

      await service.refresh();

      expect(fakeStorage._store.containsKey('bimusic_access_token'), isTrue);
      expect(fakeStorage._store.containsKey('bimusic_refresh_token'), isTrue);
    });

    test('concurrent calls share one network request (single-flight)', () async {
      final access = _makeJwt(userId: 'u1', username: 'admin', isAdmin: false);
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      int callCount = 0;
      when(() => mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenAnswer((_) async {
        callCount++;
        return _makeRefreshResponse(access, 'new-refresh');
      });

      final results = await Future.wait([service.refresh(), service.refresh()]);

      expect(callCount, 1, reason: 'only one HTTP request should be made');
      expect(results[0].outcome, RefreshOutcome.success);
      expect(results[1].outcome, RefreshOutcome.success);
    });
  });

  group('logout', () {
    test('clears tokens even when no tokens are stored', () async {
      await service.logout();

      expect(fakeStorage._store.containsKey('bimusic_access_token'), isFalse);
      expect(fakeStorage._store.containsKey('bimusic_refresh_token'), isFalse);
      expect(service.accessToken, isNull);
    });

    test('clears tokens when refresh is stored but in-memory token is null',
        () async {
      fakeStorage._store['bimusic_refresh_token'] = 'stored-refresh';

      await service.logout();

      expect(fakeStorage._store.containsKey('bimusic_refresh_token'), isFalse);
      expect(service.accessToken, isNull);
    });
  });
}
