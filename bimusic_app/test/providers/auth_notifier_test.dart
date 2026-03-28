import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/user.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/services/auth_service.dart';

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
}
