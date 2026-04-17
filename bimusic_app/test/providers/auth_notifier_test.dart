import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/user.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/services/auth_service.dart';

/// Builds a minimal JWT-like string. Pass [exp] (seconds since epoch) to
/// include an expiry claim; omit to produce a token with no exp field.
String _makeJwt({int? exp}) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payloadJson =
      exp != null ? '{"sub":"u1","exp":$exp}' : '{"sub":"u1"}';
  final payload = base64Url.encode(utf8.encode(payloadJson));
  return '$header.$payload.fakesig';
}

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService mockAuthService;
  late ProviderContainer container;

  const testUser = User(userId: 'u1', username: 'admin', isAdmin: true);
  const testTokens = AuthTokens(
    accessToken: 'access_token',
    refreshToken: 'refresh_token',
    user: testUser,
  );

  setUp(() {
    mockAuthService = MockAuthService();
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWith((_) => mockAuthService),
      ],
    );
  });

  tearDown(() => container.dispose());

  // Helper: trigger provider build and wait for async init to complete.
  Future<void> waitForInit() async {
    container.read(authNotifierProvider); // trigger build
    await container.read(authNotifierProvider.notifier).initialized;
  }

  group('startup', () {
    test('starts in loading state', () {
      when(() => mockAuthService.readStoredTokens()).thenAnswer((_) async => null);

      // Read the provider before init completes.
      final state = container.read(authNotifierProvider);
      expect(state, isA<AuthStateLoading>());
    });

    test('goes unauthenticated when no stored tokens', () async {
      when(() => mockAuthService.readStoredTokens()).thenAnswer((_) async => null);

      await waitForInit();

      expect(container.read(authNotifierProvider), isA<AuthStateUnauthenticated>());
    });

    test('authenticates when stored tokens refresh successfully', () async {
      when(() => mockAuthService.readStoredTokens())
          .thenAnswer((_) async => testTokens);
      when(() => mockAuthService.refresh())
          .thenAnswer((_) async => testTokens);

      await waitForInit();

      final state = container.read(authNotifierProvider);
      expect(state, isA<AuthStateAuthenticated>());
      expect((state as AuthStateAuthenticated).tokens, testTokens);
    });

    test('goes unauthenticated and clears tokens when refresh fails', () async {
      when(() => mockAuthService.readStoredTokens())
          .thenAnswer((_) async => testTokens);
      when(() => mockAuthService.refresh()).thenAnswer((_) async => null);
      when(() => mockAuthService.clearTokens()).thenAnswer((_) async {});

      await waitForInit();

      expect(container.read(authNotifierProvider), isA<AuthStateUnauthenticated>());
      verify(() => mockAuthService.clearTokens()).called(1);
    });
  });

  group('login', () {
    setUp(() {
      when(() => mockAuthService.readStoredTokens()).thenAnswer((_) async => null);
    });

    test('success sets state to authenticated', () async {
      when(() => mockAuthService.login(any(), any()))
          .thenAnswer((_) async => testTokens);

      await waitForInit();
      await container.read(authNotifierProvider.notifier).login('admin', 'pass');

      final state = container.read(authNotifierProvider);
      expect(state, isA<AuthStateAuthenticated>());
      expect((state as AuthStateAuthenticated).tokens, testTokens);
    });

    test('failure sets state to unauthenticated and rethrows', () async {
      when(() => mockAuthService.login(any(), any()))
          .thenThrow(Exception('bad credentials'));

      await waitForInit();

      await expectLater(
        container.read(authNotifierProvider.notifier).login('admin', 'wrong'),
        throwsException,
      );
      expect(container.read(authNotifierProvider), isA<AuthStateUnauthenticated>());
    });
  });

  group('logout', () {
    test('clears state to unauthenticated', () async {
      when(() => mockAuthService.readStoredTokens())
          .thenAnswer((_) async => testTokens);
      when(() => mockAuthService.refresh())
          .thenAnswer((_) async => testTokens);
      when(() => mockAuthService.logout()).thenAnswer((_) async {});

      await waitForInit();
      expect(container.read(authNotifierProvider), isA<AuthStateAuthenticated>());

      await container.read(authNotifierProvider.notifier).logout();

      expect(container.read(authNotifierProvider), isA<AuthStateUnauthenticated>());
      verify(() => mockAuthService.logout()).called(1);
    });
  });

  group('proactive token refresh', () {
    // Epoch second in the distant past → token is already expired.
    final pastEpoch = DateTime(2000).millisecondsSinceEpoch ~/ 1000;

    setUp(() {
      when(() => mockAuthService.readStoredTokens())
          .thenAnswer((_) async => null);
    });

    test('immediately calls refresh when access token is already expired',
        () async {
      final expiredTokens = AuthTokens(
        accessToken: _makeJwt(exp: pastEpoch),
        refreshToken: 'rtoken',
        user: testUser,
      );

      when(() => mockAuthService.login(any(), any()))
          .thenAnswer((_) async => expiredTokens);
      when(() => mockAuthService.refresh())
          .thenAnswer((_) async => testTokens);

      await waitForInit();
      await container.read(authNotifierProvider.notifier).login('admin', 'pass');
      await Future<void>.delayed(Duration.zero);

      verify(() => mockAuthService.refresh()).called(1);
    });

    test('updates state to new tokens after immediate background refresh',
        () async {
      final expiredTokens = AuthTokens(
        accessToken: _makeJwt(exp: pastEpoch),
        refreshToken: 'rtoken',
        user: testUser,
      );

      when(() => mockAuthService.login(any(), any()))
          .thenAnswer((_) async => expiredTokens);
      when(() => mockAuthService.refresh())
          .thenAnswer((_) async => testTokens);

      await waitForInit();
      await container.read(authNotifierProvider.notifier).login('admin', 'pass');
      await Future<void>.delayed(Duration.zero);

      final s = container.read(authNotifierProvider);
      expect(s, isA<AuthStateAuthenticated>());
      expect((s as AuthStateAuthenticated).tokens, testTokens);
    });

    test('goes unauthenticated when background refresh returns null', () async {
      final expiredTokens = AuthTokens(
        accessToken: _makeJwt(exp: pastEpoch),
        refreshToken: 'rtoken',
        user: testUser,
      );

      when(() => mockAuthService.login(any(), any()))
          .thenAnswer((_) async => expiredTokens);
      when(() => mockAuthService.refresh()).thenAnswer((_) async => null);
      when(() => mockAuthService.clearTokens()).thenAnswer((_) async {});

      await waitForInit();
      await container.read(authNotifierProvider.notifier).login('admin', 'pass');
      await Future<void>.delayed(Duration.zero);

      expect(
          container.read(authNotifierProvider), isA<AuthStateUnauthenticated>());
      verify(() => mockAuthService.clearTokens()).called(1);
    });

    test('stays authenticated when background refresh throws (network error)',
        () async {
      final expiredTokens = AuthTokens(
        accessToken: _makeJwt(exp: pastEpoch),
        refreshToken: 'rtoken',
        user: testUser,
      );

      when(() => mockAuthService.login(any(), any()))
          .thenAnswer((_) async => expiredTokens);
      when(() => mockAuthService.refresh())
          .thenThrow(Exception('network error'));

      await waitForInit();
      await container.read(authNotifierProvider.notifier).login('admin', 'pass');
      await Future<void>.delayed(Duration.zero);

      expect(
          container.read(authNotifierProvider), isA<AuthStateAuthenticated>());
    });

    test('does not schedule refresh when token has no exp field', () async {
      final noExpTokens = AuthTokens(
        accessToken: _makeJwt(),
        refreshToken: 'rtoken',
        user: testUser,
      );

      when(() => mockAuthService.login(any(), any()))
          .thenAnswer((_) async => noExpTokens);

      await waitForInit();
      await container.read(authNotifierProvider.notifier).login('admin', 'pass');

      verifyNever(() => mockAuthService.refresh());
      expect(container.read(authNotifierProvider), isA<AuthStateAuthenticated>());
    });

    test('does not crash or schedule refresh for a malformed access token',
        () async {
      const badTokens = AuthTokens(
        accessToken: 'not-a-jwt',
        refreshToken: 'rtoken',
        user: testUser,
      );

      when(() => mockAuthService.login(any(), any()))
          .thenAnswer((_) async => badTokens);

      await waitForInit();
      await container.read(authNotifierProvider.notifier).login('admin', 'pass');

      verifyNever(() => mockAuthService.refresh());
      expect(container.read(authNotifierProvider), isA<AuthStateAuthenticated>());
    });
  });
}
