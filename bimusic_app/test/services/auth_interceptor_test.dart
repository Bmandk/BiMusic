import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/user.dart';
import 'package:bimusic_app/providers/auth_provider.dart';
import 'package:bimusic_app/services/api_client.dart';
import 'package:bimusic_app/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

class MockDio extends Mock implements Dio {}

class _StubAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  @override
  Future<void> get initialized async {}
  @override
  AuthState build() => const AuthStateUnauthenticated();
  @override
  Future<void> login(String u, String p) async {}
  @override
  Future<void> logout() async {}
}

class _FakeRequestOptions extends Fake implements RequestOptions {}

// Minimal fake handlers that capture what happens to the request/error.
class _FakeRequestHandler extends Fake implements RequestInterceptorHandler {
  RequestOptions? forwarded;
  @override
  void next(RequestOptions options) => forwarded = options;
}

class _FakeErrorHandler extends Fake implements ErrorInterceptorHandler {
  DioException? forwarded;
  Response<dynamic>? resolved;
  @override
  void next(DioException err) => forwarded = err;
  @override
  void resolve(Response<dynamic> response) => resolved = response;
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeRequestOptions());
  });

  late MockAuthService mockAuthService;
  late MockDio mockDio;
  late AuthInterceptor interceptor;
  bool logoutCalled = false;

  const testUser = User(userId: 'u1', username: 'admin', isAdmin: true);
  const testTokens = AuthTokens(
    accessToken: 'new_access',
    refreshToken: 'new_refresh',
    user: testUser,
  );

  setUp(() {
    logoutCalled = false;
    mockAuthService = MockAuthService();
    mockDio = MockDio();
    interceptor = AuthInterceptor(
      authService: mockAuthService,
      dio: mockDio,
      onLogout: () => logoutCalled = true,
    );
  });

  group('onRequest', () {
    test('attaches Authorization header when token is present', () {
      when(() => mockAuthService.accessToken).thenReturn('my_token');

      final options = RequestOptions(path: '/test');
      final handler = _FakeRequestHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], 'Bearer my_token');
      expect(handler.forwarded, options);
    });

    test('does not add Authorization header when token is null', () {
      when(() => mockAuthService.accessToken).thenReturn(null);

      final options = RequestOptions(path: '/test');
      final handler = _FakeRequestHandler();

      interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('onError', () {
    DioException make401() => DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response<dynamic>(
            statusCode: 401,
            requestOptions: RequestOptions(path: '/api/test'),
          ),
          type: DioExceptionType.badResponse,
        );

    test('non-401 errors are forwarded unchanged', () async {
      final err = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionError,
      );
      final handler = _FakeErrorHandler();

      await interceptor.onError(err, handler);

      expect(handler.forwarded, err);
      expect(handler.resolved, isNull);
      verifyNever(() => mockAuthService.refresh());
    });

    test('401 triggers refresh and retries on success', () async {
      when(() => mockAuthService.refresh()).thenAnswer((_) async => testTokens);
      when(() => mockAuthService.accessToken).thenReturn('new_access');
      when(() => mockDio.fetch<dynamic>(any())).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/test'),
          statusCode: 200,
        ),
      );

      final err = make401();
      final handler = _FakeErrorHandler();

      await interceptor.onError(err, handler);

      verify(() => mockAuthService.refresh()).called(1);
      expect(handler.resolved?.statusCode, 200);
      expect(handler.forwarded, isNull);
    });

    test('401 calls onLogout and forwards error when refresh fails', () async {
      when(() => mockAuthService.refresh()).thenAnswer((_) async => null);

      final err = make401();
      final handler = _FakeErrorHandler();

      await interceptor.onError(err, handler);

      expect(logoutCalled, isTrue);
      expect(handler.forwarded, err);
    });

    test('401 calls onLogout and forwards error when refresh throws', () async {
      when(() => mockAuthService.refresh()).thenThrow(Exception('network'));

      final err = make401();
      final handler = _FakeErrorHandler();

      await interceptor.onError(err, handler);

      expect(logoutCalled, isTrue);
      expect(handler.forwarded, err);
    });

    test('401 forwards retry DioException when retry fetch fails', () async {
      when(() => mockAuthService.refresh()).thenAnswer((_) async => testTokens);
      when(() => mockAuthService.accessToken).thenReturn('new_access');
      final retryErr = DioException(
        requestOptions: RequestOptions(path: '/api/test'),
        type: DioExceptionType.connectionError,
      );
      when(() => mockDio.fetch<dynamic>(any())).thenThrow(retryErr);

      final err = make401();
      final handler = _FakeErrorHandler();

      await interceptor.onError(err, handler);

      expect(handler.forwarded, retryErr);
      expect(handler.resolved, isNull);
    });

    test('concurrent 401s only trigger one refresh', () async {
      int refreshCount = 0;
      final firstStarted = Completer<void>();
      final refreshGate = Completer<AuthTokens?>();

      when(() => mockAuthService.refresh()).thenAnswer((_) async {
        refreshCount++;
        firstStarted.complete();
        return refreshGate.future;
      });
      when(() => mockAuthService.accessToken).thenReturn('new_access');
      when(() => mockDio.fetch<dynamic>(any())).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/test'),
          statusCode: 200,
        ),
      );

      final err1 = make401();
      final err2 = make401();
      final handler1 = _FakeErrorHandler();
      final handler2 = _FakeErrorHandler();

      // Start both error handlers concurrently.
      final future1 = interceptor.onError(err1, handler1);
      await firstStarted.future; // ensure first refresh is in-flight
      final future2 = interceptor.onError(err2, handler2);

      // Unblock the refresh.
      refreshGate.complete(testTokens);
      await Future.wait([future1, future2]);

      expect(refreshCount, 1, reason: 'only one refresh should be attempted');
      expect(handler1.resolved?.statusCode, 200);
      expect(handler2.resolved?.statusCode, 200);
    });
  });

  group('apiClientProvider', () {
    test('provides a configured Dio instance with AuthInterceptor', () {
      final fakeAuthService = MockAuthService();
      final container = ProviderContainer(overrides: [
        authServiceProvider.overrideWith((_) => fakeAuthService),
        authNotifierProvider.overrideWith(() => _StubAuthNotifier()),
      ]);
      addTearDown(container.dispose);

      final dio = container.read(apiClientProvider);

      expect(dio, isA<Dio>());
      expect(
        dio.interceptors.whereType<AuthInterceptor>().length,
        1,
      );
    });
  });
}
