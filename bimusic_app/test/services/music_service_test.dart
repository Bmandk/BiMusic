import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/services/music_service.dart';

// ---------------------------------------------------------------------------
// Fake Dio
// ---------------------------------------------------------------------------

class _FakeDio extends Fake implements Dio {
  final _responses = <String, dynamic>{};

  void stubGet(String path, dynamic data) => _responses[path] = data;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final resp = _responses[path];
    if (resp == null) throw StateError('No stub for GET $path');
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: resp as T,
    );
  }
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _artistJson = {
  'id': 1,
  'name': 'Test Artist',
  'imageUrl': 'http://example.com/artist.jpg',
  'albumCount': 2,
};

const _albumJson = {
  'id': 10,
  'title': 'Test Album',
  'artistId': 1,
  'artistName': 'Test Artist',
  'imageUrl': 'http://example.com/album.jpg',
  'genres': <String>[],
  'trackCount': 3,
  'duration': 720,
};

const _trackJson = {
  'id': 100,
  'title': 'Test Track',
  'trackNumber': '1',
  'duration': 240,
  'albumId': 10,
  'artistId': 1,
  'hasFile': true,
  'streamUrl': 'http://example.com/stream/100',
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeDio fakeDio;
  late MusicService service;

  setUp(() {
    fakeDio = _FakeDio();
    service = MusicService(fakeDio);
  });

  group('getArtists', () {
    test('returns list of artists', () async {
      fakeDio.stubGet('/api/library/artists', [_artistJson]);

      final result = await service.getArtists();

      expect(result, hasLength(1));
      expect(result.first.id, 1);
      expect(result.first.name, 'Test Artist');
    });

    test('returns empty list when no artists', () async {
      fakeDio.stubGet('/api/library/artists', <dynamic>[]);

      final result = await service.getArtists();

      expect(result, isEmpty);
    });
  });

  group('getArtist', () {
    test('returns single artist', () async {
      fakeDio.stubGet('/api/library/artists/1', _artistJson);

      final result = await service.getArtist(1);

      expect(result.id, 1);
      expect(result.name, 'Test Artist');
    });
  });

  group('getArtistAlbums', () {
    test('returns list of albums for artist', () async {
      fakeDio.stubGet('/api/library/artists/1/albums', [_albumJson]);

      final result = await service.getArtistAlbums(1);

      expect(result, hasLength(1));
      expect(result.first.id, 10);
      expect(result.first.title, 'Test Album');
    });
  });

  group('getAlbum', () {
    test('returns single album', () async {
      fakeDio.stubGet('/api/library/albums/10', _albumJson);

      final result = await service.getAlbum(10);

      expect(result.id, 10);
      expect(result.title, 'Test Album');
      expect(result.artistId, 1);
    });
  });

  group('getAlbumTracks', () {
    test('returns list of tracks for album', () async {
      fakeDio.stubGet('/api/library/albums/10/tracks', [_trackJson]);

      final result = await service.getAlbumTracks(10);

      expect(result, hasLength(1));
      expect(result.first.id, 100);
      expect(result.first.title, 'Test Track');
      expect(result.first.hasFile, isTrue);
    });

    test('returns empty list when album has no tracks', () async {
      fakeDio.stubGet('/api/library/albums/10/tracks', <dynamic>[]);

      final result = await service.getAlbumTracks(10);

      expect(result, isEmpty);
    });
  });

  group('searchLibrary', () {
    test('returns search results', () async {
      fakeDio.stubGet('/api/search', {
        'artists': [_artistJson],
        'albums': [_albumJson],
      });

      final result = await service.searchLibrary('test');

      expect(result.artists, hasLength(1));
      expect(result.albums, hasLength(1));
      expect(result.artists.first.name, 'Test Artist');
    });

    test('returns empty results when nothing matches', () async {
      fakeDio.stubGet('/api/search', {'artists': [], 'albums': []});

      final result = await service.searchLibrary('zzz');

      expect(result.artists, isEmpty);
      expect(result.albums, isEmpty);
    });
  });
}
