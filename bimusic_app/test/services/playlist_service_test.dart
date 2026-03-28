import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/services/playlist_service.dart';

// ---------------------------------------------------------------------------
// Fake Dio
// ---------------------------------------------------------------------------

class _FakeDio extends Fake implements Dio {
  String? lastMethod;
  String? lastPath;
  dynamic lastData;

  dynamic _nextGetResponse;
  dynamic _nextPostResponse;

  void stubGet(dynamic data) => _nextGetResponse = data;
  void stubPost(dynamic data) => _nextPostResponse = data;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    lastMethod = 'GET';
    lastPath = path;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: _nextGetResponse as T,
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
    lastMethod = 'POST';
    lastPath = path;
    lastData = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: _nextPostResponse as T,
    );
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    lastMethod = 'PUT';
    lastPath = path;
    lastData = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: null as T,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    lastMethod = 'DELETE';
    lastPath = path;
    lastData = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: null as T,
    );
  }
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _trackJson = {
  'id': 1,
  'title': 'Track',
  'trackNumber': '1',
  'duration': 200,
  'albumId': 10,
  'artistId': 5,
  'hasFile': true,
  'streamUrl': 'http://example.com/stream/1',
};

const _playlistSummaryJson = {
  'id': 'pl-1',
  'name': 'My Playlist',
  'trackCount': 2,
  'createdAt': '2026-01-01T00:00:00Z',
};

const _playlistDetailJson = {
  'id': 'pl-1',
  'name': 'My Playlist',
  'tracks': [_trackJson],
};

const _createResponseJson = {
  'id': 'pl-new',
  'name': 'New Playlist',
  'createdAt': '2026-03-28T00:00:00Z',
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeDio fakeDio;
  late PlaylistService service;

  setUp(() {
    fakeDio = _FakeDio();
    service = PlaylistService(fakeDio);
  });

  group('listPlaylists', () {
    test('returns list of playlist summaries', () async {
      fakeDio.stubGet([_playlistSummaryJson]);

      final result = await service.listPlaylists();

      expect(result, hasLength(1));
      expect(result.first.id, 'pl-1');
      expect(result.first.name, 'My Playlist');
      expect(result.first.trackCount, 2);
    });

    test('returns empty list when no playlists', () async {
      fakeDio.stubGet(<dynamic>[]);

      final result = await service.listPlaylists();

      expect(result, isEmpty);
    });
  });

  group('createPlaylist', () {
    test('returns new playlist summary with trackCount 0', () async {
      fakeDio.stubPost(_createResponseJson);

      final result = await service.createPlaylist('New Playlist');

      expect(result.id, 'pl-new');
      expect(result.name, 'New Playlist');
      expect(result.trackCount, 0);
      expect(fakeDio.lastMethod, 'POST');
      expect(fakeDio.lastPath, '/api/playlists');
      expect((fakeDio.lastData as Map<String, dynamic>)['name'], 'New Playlist');
    });
  });

  group('getPlaylist', () {
    test('returns playlist detail with tracks', () async {
      fakeDio.stubGet(_playlistDetailJson);

      final result = await service.getPlaylist('pl-1');

      expect(result.id, 'pl-1');
      expect(result.name, 'My Playlist');
      expect(result.tracks, hasLength(1));
      expect(fakeDio.lastPath, '/api/playlists/pl-1');
    });
  });

  group('updatePlaylist', () {
    test('sends PUT with new name', () async {
      await service.updatePlaylist('pl-1', 'Renamed');

      expect(fakeDio.lastMethod, 'PUT');
      expect(fakeDio.lastPath, '/api/playlists/pl-1');
      expect((fakeDio.lastData as Map<String, dynamic>)['name'], 'Renamed');
    });
  });

  group('deletePlaylist', () {
    test('sends DELETE to playlist endpoint', () async {
      await service.deletePlaylist('pl-1');

      expect(fakeDio.lastMethod, 'DELETE');
      expect(fakeDio.lastPath, '/api/playlists/pl-1');
    });
  });

  group('addTracks', () {
    test('sends POST with track ids', () async {
      await service.addTracks('pl-1', [1, 2, 3]);

      expect(fakeDio.lastMethod, 'POST');
      expect(fakeDio.lastPath, '/api/playlists/pl-1/tracks');
      expect(
        (fakeDio.lastData as Map<String, dynamic>)['trackIds'],
        [1, 2, 3],
      );
    });
  });

  group('removeTrack', () {
    test('sends DELETE to track endpoint', () async {
      await service.removeTrack('pl-1', 99);

      expect(fakeDio.lastMethod, 'DELETE');
      expect(fakeDio.lastPath, '/api/playlists/pl-1/tracks/99');
    });
  });

  group('reorderTracks', () {
    test('sends PUT with reordered track ids', () async {
      await service.reorderTracks('pl-1', [3, 1, 2]);

      expect(fakeDio.lastMethod, 'PUT');
      expect(fakeDio.lastPath, '/api/playlists/pl-1/tracks/reorder');
      expect(
        (fakeDio.lastData as Map<String, dynamic>)['trackIds'],
        [3, 1, 2],
      );
    });
  });
}
