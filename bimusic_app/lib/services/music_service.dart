import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/search_results.dart';
import '../models/track.dart';
import 'api_client.dart';

class MusicService {
  MusicService(this._dio);

  final Dio _dio;

  Future<List<Artist>> getArtists() async {
    final response = await _dio.get<List<dynamic>>('/api/library/artists');
    return response.data!
        .map((e) => Artist.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Artist> getArtist(int id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/library/artists/$id');
    return Artist.fromJson(response.data!);
  }

  Future<List<Album>> getArtistAlbums(int id) async {
    final response =
        await _dio.get<List<dynamic>>('/api/library/artists/$id/albums');
    return response.data!
        .map((e) => Album.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Album> getAlbum(int id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/library/albums/$id');
    return Album.fromJson(response.data!);
  }

  Future<List<Track>> getAlbumTracks(int albumId) async {
    final response =
        await _dio.get<List<dynamic>>('/api/library/albums/$albumId/tracks');
    return response.data!
        .map((e) => Track.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SearchResults> searchLibrary(String term) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/search',
      queryParameters: {'term': term},
    );
    return SearchResults.fromJson(response.data!);
  }
}

final musicServiceProvider = Provider<MusicService>((ref) {
  return MusicService(ref.watch(apiClientProvider));
});
