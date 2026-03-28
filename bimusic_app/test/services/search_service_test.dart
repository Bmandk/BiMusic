import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/services/search_service.dart';

// ---------------------------------------------------------------------------
// Fake Dio that supports both GET and POST
// ---------------------------------------------------------------------------

class _FakeDio extends Fake implements Dio {
  final _getResponses = <String, dynamic>{};
  final _postResponses = <String, dynamic>{};

  void stubGet(String path, dynamic data) => _getResponses[path] = data;
  void stubPost(String path, dynamic data) => _postResponses[path] = data;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final resp = _getResponses[path];
    if (resp == null) throw StateError('No GET stub for $path');
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: resp as T,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final resp = _postResponses[path];
    if (resp == null) throw StateError('No POST stub for $path');
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

const _lidarrArtistJson = {
  'id': 42,
  'artistName': 'Lidarr Artist',
  'foreignArtistId': 'mbid-42',
  'overview': 'An overview',
  'images': <dynamic>[],
};

const _lidarrAlbumJson = {
  'id': 10,
  'title': 'Lidarr Album',
  'images': <dynamic>[],
  'artist': {
    'id': 42,
    'artistName': 'Lidarr Artist',
    'images': <dynamic>[],
  },
};

const _requestJson = {
  'id': 'req-uuid',
  'type': 'artist',
  'lidarrId': 42,
  'status': 'pending',
  'requestedAt': '2026-03-28T00:00:00Z',
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeDio fakeDio;
  late SearchService service;

  setUp(() {
    fakeDio = _FakeDio();
    service = SearchService(fakeDio);
  });

  group('searchLibrary', () {
    test('returns SearchResults parsed from response', () async {
      fakeDio.stubGet('/api/search', {
        'artists': [_artistJson],
        'albums': [_albumJson],
      });

      final result = await service.searchLibrary('test');

      expect(result.artists, hasLength(1));
      expect(result.albums, hasLength(1));
      expect(result.artists.first.name, 'Test Artist');
      expect(result.albums.first.title, 'Test Album');
    });

    test('returns empty results when no matches', () async {
      fakeDio.stubGet('/api/search', {'artists': [], 'albums': []});

      final result = await service.searchLibrary('zzz');

      expect(result.artists, isEmpty);
      expect(result.albums, isEmpty);
    });
  });

  group('searchLidarr', () {
    test('returns LidarrSearchResults parsed from response', () async {
      fakeDio.stubGet('/api/requests/search', {
        'artists': [_lidarrArtistJson],
        'albums': [_lidarrAlbumJson],
      });

      final result = await service.searchLidarr('metal');

      expect(result.artists, hasLength(1));
      expect(result.albums, hasLength(1));
      expect(result.artists.first.artistName, 'Lidarr Artist');
      expect(result.albums.first.title, 'Lidarr Album');
    });

    test('returns empty results for empty response', () async {
      fakeDio.stubGet('/api/requests/search', {'artists': [], 'albums': []});

      final result = await service.searchLidarr('unknown');

      expect(result.artists, isEmpty);
      expect(result.albums, isEmpty);
    });
  });

  group('requestArtist', () {
    test('posts to /api/requests/artist and returns MusicRequest', () async {
      fakeDio.stubPost('/api/requests/artist', _requestJson);

      final result = await service.requestArtist(
        foreignArtistId: 'mbid-42',
        artistName: 'Lidarr Artist',
      );

      expect(result.id, 'req-uuid');
      expect(result.type, 'artist');
      expect(result.lidarrId, 42);
      expect(result.status, 'pending');
    });
  });

  group('requestAlbum', () {
    test('posts to /api/requests/album and returns MusicRequest', () async {
      fakeDio.stubPost('/api/requests/album', {
        'id': 'req-album',
        'type': 'album',
        'lidarrId': 10,
        'status': 'pending',
        'requestedAt': '2026-03-28T00:00:00Z',
      });

      final result = await service.requestAlbum(10);

      expect(result.id, 'req-album');
      expect(result.type, 'album');
      expect(result.lidarrId, 10);
    });
  });

  group('getRequests', () {
    test('returns list of MusicRequests', () async {
      fakeDio.stubGet('/api/requests', [
        _requestJson,
        {
          'id': 'req-2',
          'type': 'album',
          'lidarrId': 99,
          'status': 'downloading',
          'requestedAt': '2026-03-28T01:00:00Z',
        },
      ]);

      final result = await service.getRequests();

      expect(result, hasLength(2));
      expect(result.first.id, 'req-uuid');
      expect(result.last.status, 'downloading');
    });

    test('returns empty list when no requests', () async {
      fakeDio.stubGet('/api/requests', <dynamic>[]);

      final result = await service.getRequests();

      expect(result, isEmpty);
    });
  });
}
