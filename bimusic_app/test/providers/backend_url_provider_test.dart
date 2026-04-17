import 'package:flutter_test/flutter_test.dart';
import 'package:bimusic_app/providers/backend_url_provider.dart';
import 'package:bimusic_app/utils/url_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeBackendUrl', () {
    test('accepts http URL', () {
      expect(normalizeBackendUrl('http://example.com'), 'http://example.com');
    });

    test('accepts https URL', () {
      expect(normalizeBackendUrl('https://example.com'), 'https://example.com');
    });

    test('strips trailing slash', () {
      expect(normalizeBackendUrl('http://example.com/'), 'http://example.com');
    });

    test('strips multiple trailing slashes', () {
      expect(
          normalizeBackendUrl('http://example.com///'), 'http://example.com');
    });

    test('trims leading/trailing whitespace', () {
      expect(
          normalizeBackendUrl('  http://example.com  '), 'http://example.com');
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
}
