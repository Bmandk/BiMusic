import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/providers/backend_url_provider.dart';
import 'package:bimusic_app/utils/url_resolver.dart';

// ---------------------------------------------------------------------------
// Fakes / mocks for BackendUrlNotifier tests
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
    if (value != null) _store[key] = value;
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

class _MockDio extends Mock implements Dio {
  @override
  void close({bool force = false}) {}
}

/// Subclass that injects a fake storage and optional mock Dio.
class _TestableBackendUrlNotifier extends BackendUrlNotifier {
  _TestableBackendUrlNotifier({String? initialUrl, Dio? dio})
      : _storage = _FakeStorage() {
    if (initialUrl != null) {
      _storage._store['bimusic_backend_url'] = initialUrl;
    }
    if (dio != null) dioFactory = () => dio;
  }

  final _FakeStorage _storage;

  @override
  _FakeStorage buildStorage() => _storage;

  @override
  Future<String?> build() async =>
      _storage._store['bimusic_backend_url'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeBackendUrl', () {
    test('accepts http with loopback 127.0.0.1', () {
      expect(normalizeBackendUrl('http://127.0.0.1'), 'http://127.0.0.1');
    });

    test('accepts http with localhost', () {
      expect(normalizeBackendUrl('http://localhost'), 'http://localhost');
    });

    test('accepts http with 10.x.x.x', () {
      expect(normalizeBackendUrl('http://10.0.0.1'), 'http://10.0.0.1');
    });

    test('accepts http with 172.16.x.x', () {
      expect(normalizeBackendUrl('http://172.16.0.1'), 'http://172.16.0.1');
    });

    test('accepts http with 172.31.x.x', () {
      expect(normalizeBackendUrl('http://172.31.255.1'), 'http://172.31.255.1');
    });

    test('accepts http with 192.168.x.x', () {
      expect(
        normalizeBackendUrl('http://192.168.1.1'),
        'http://192.168.1.1',
      );
    });

    test('accepts https URL with public host', () {
      expect(normalizeBackendUrl('https://example.com'), 'https://example.com');
    });

    test('rejects http with public hostname', () {
      expect(
        () => normalizeBackendUrl('http://example.com'),
        throwsA(isA<String>()),
      );
    });

    test('rejects http with non-private public IP', () {
      expect(
        () => normalizeBackendUrl('http://203.0.113.1'),
        throwsA(isA<String>()),
      );
    });

    test('strips trailing slash', () {
      expect(
        normalizeBackendUrl('http://192.168.1.1/'),
        'http://192.168.1.1',
      );
    });

    test('strips multiple trailing slashes', () {
      expect(
        normalizeBackendUrl('http://192.168.1.1///'),
        'http://192.168.1.1',
      );
    });

    test('trims leading/trailing whitespace', () {
      expect(
        normalizeBackendUrl('  http://192.168.1.1  '),
        'http://192.168.1.1',
      );
    });

    test('preserves path and port', () {
      expect(
        normalizeBackendUrl('http://192.168.1.1:3000/base'),
        'http://192.168.1.1:3000/base',
      );
    });

    test('throws String when scheme is missing', () {
      expect(() => normalizeBackendUrl('example.com'), throwsA(isA<String>()));
    });

    test('throws String when blank after trim', () {
      expect(() => normalizeBackendUrl('   '), throwsA(isA<String>()));
    });
  });

  group('resolveBackendUrl', () {
    test('prepends base to relative path', () {
      expect(
        resolveBackendUrl('http://host', '/api/library/artists/1/image'),
        'http://host/api/library/artists/1/image',
      );
    });

    test('returns absolute http URL unchanged', () {
      expect(
        resolveBackendUrl(
          'http://host',
          'http://other/api/library/artists/1/image',
        ),
        'http://other/api/library/artists/1/image',
      );
    });

    test('returns absolute https URL unchanged', () {
      expect(
        resolveBackendUrl('http://host', 'https://cdn.example.com/img.jpg'),
        'https://cdn.example.com/img.jpg',
      );
    });

    test('handles empty base with absolute URL', () {
      expect(
        resolveBackendUrl('', 'http://other/path'),
        'http://other/path',
      );
    });

    test('returns relative path unchanged when base is empty', () {
      expect(
        resolveBackendUrl('', '/api/stream/1'),
        '/api/stream/1',
      );
    });

    test('normalises missing leading slash on relative path', () {
      expect(
        resolveBackendUrl('http://host', 'api/stream/1'),
        'http://host/api/stream/1',
      );
    });

    test('strips trailing slash from base before joining', () {
      expect(
        resolveBackendUrl('http://host/', '/api/stream/1'),
        'http://host/api/stream/1',
      );
    });
  });

  group('BackendUrlNotifier', () {
    late _MockDio mockDio;

    setUp(() {
      mockDio = _MockDio();
    });

    ProviderContainer makeContainer({String? initialUrl, Dio? dio}) {
      final container = ProviderContainer(overrides: [
        backendUrlProvider.overrideWith(
          () => _TestableBackendUrlNotifier(initialUrl: initialUrl, dio: dio),
        ),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('build returns stored URL when one exists', () async {
      final container = makeContainer(initialUrl: 'http://server');
      final url = await container.read(backendUrlProvider.future);
      expect(url, 'http://server');
    });

    test('build returns null when no URL is stored', () async {
      final container = makeContainer();
      final url = await container.read(backendUrlProvider.future);
      expect(url, isNull);
    });

    test('setUrl updates state and persists on 200 response', () async {
      when(() => mockDio.get<dynamic>(any())).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
        ),
      );

      final container = makeContainer(dio: mockDio);
      await container.read(backendUrlProvider.future);
      final notifier = container.read(backendUrlProvider.notifier)
          as _TestableBackendUrlNotifier;

      await notifier.setUrl('http://192.168.1.1:3000/');

      final state = container.read(backendUrlProvider);
      expect(state.value, 'http://192.168.1.1:3000');
      expect(notifier.buildStorage()._store['bimusic_backend_url'],
          'http://192.168.1.1:3000');
    });

    test('setUrl throws when server returns 500', () async {
      when(() => mockDio.get<dynamic>(any())).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 500,
        ),
      );

      final container = makeContainer(dio: mockDio);
      await container.read(backendUrlProvider.future);
      final notifier = container.read(backendUrlProvider.notifier);

      await expectLater(
        () => notifier.setUrl('http://192.168.1.1'),
        throwsA('Server returned 500'),
      );
    });

    test('setUrl throws friendly message on connection timeout', () async {
      when(() => mockDio.get<dynamic>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final container = makeContainer(dio: mockDio);
      await container.read(backendUrlProvider.future);
      final notifier = container.read(backendUrlProvider.notifier);

      await expectLater(
        () => notifier.setUrl('http://192.168.1.1'),
        throwsA('Connection timed out. Check the URL and try again.'),
      );
    });

    test('setUrl throws friendly message on generic DioException', () async {
      when(() => mockDio.get<dynamic>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
          message: 'connection refused',
        ),
      );

      final container = makeContainer(dio: mockDio);
      await container.read(backendUrlProvider.future);
      final notifier = container.read(backendUrlProvider.notifier);

      await expectLater(
        () => notifier.setUrl('http://192.168.1.1'),
        throwsA('Could not reach server: connection refused'),
      );
    });

    test('clearUrl resets state to null and removes stored key', () async {
      final container = makeContainer(initialUrl: 'http://existing');
      await container.read(backendUrlProvider.future);
      final notifier = container.read(backendUrlProvider.notifier)
          as _TestableBackendUrlNotifier;

      await notifier.clearUrl();

      final state = container.read(backendUrlProvider);
      expect(state.value, isNull);
      expect(
        notifier.buildStorage()._store.containsKey('bimusic_backend_url'),
        isFalse,
      );
    });
  });
}
