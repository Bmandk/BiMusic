import 'package:flutter_test/flutter_test.dart';
import 'package:bimusic_app/utils/url_resolver.dart';

// ---------------------------------------------------------------------------
// Normalization logic, extracted inline so it can be unit-tested without
// spinning up a Riverpod container or hitting FlutterSecureStorage.
// The implementation must stay in sync with BackendUrlNotifier._normalize.
// ---------------------------------------------------------------------------

String _normalize(String raw) {
  var url = raw.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    throw 'URL must start with http:// or https://';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('URL normalization (mirrors BackendUrlNotifier._normalize)', () {
    test('accepts http URL', () {
      expect(_normalize('http://example.com'), 'http://example.com');
    });

    test('accepts https URL', () {
      expect(_normalize('https://example.com'), 'https://example.com');
    });

    test('strips trailing slash', () {
      expect(_normalize('http://example.com/'), 'http://example.com');
    });

    test('strips multiple trailing slashes', () {
      expect(_normalize('http://example.com///'), 'http://example.com');
    });

    test('trims leading/trailing whitespace', () {
      expect(_normalize('  http://example.com  '), 'http://example.com');
    });

    test('preserves path and port', () {
      expect(
        _normalize('http://192.168.1.1:3000/base'),
        'http://192.168.1.1:3000/base',
      );
    });

    test('throws String when scheme is missing', () {
      expect(() => _normalize('example.com'), throwsA(isA<String>()));
    });

    test('throws String when blank after trim', () {
      expect(() => _normalize('   '), throwsA(isA<String>()));
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
  });
}
