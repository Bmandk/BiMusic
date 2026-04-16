import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lidarr_search_results.dart';
import '../models/music_request.dart';
import '../models/search_results.dart';
import 'api_client.dart';

class SearchService {
  SearchService(this._dio);

  final Dio _dio;

  /// Library search via GET /api/search?term=
  Future<SearchResults> searchLibrary(String term) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/search',
      queryParameters: {'term': term},
    );
    return SearchResults.fromJson(response.data!);
  }

  /// Lidarr lookup via GET /api/requests/search?term=
  Future<LidarrSearchResults> searchLidarr(String term) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/requests/search',
      queryParameters: {'term': term},
    );
    return LidarrSearchResults.fromJson(response.data!);
  }

  /// Request an artist via POST /api/requests/artist
  /// qualityProfileId, metadataProfileId, rootFolderPath are omitted so the
  /// backend auto-populates them from Lidarr defaults.
  Future<MusicRequest> requestArtist({
    required String foreignArtistId,
    required String artistName,
    String? coverUrl,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/requests/artist',
      data: {
        'foreignArtistId': foreignArtistId,
        'artistName': artistName,
        if (coverUrl != null) 'coverUrl': coverUrl,
      },
    );
    return MusicRequest.fromJson(response.data!);
  }

  /// Request an album via POST /api/requests/album
  Future<MusicRequest> requestAlbum(int albumId, {String? coverUrl}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/requests/album',
      data: {
        'albumId': albumId,
        if (coverUrl != null) 'coverUrl': coverUrl,
      },
    );
    return MusicRequest.fromJson(response.data!);
  }

  /// List current user's requests via GET /api/requests
  Future<List<MusicRequest>> getRequests() async {
    final response = await _dio.get<List<dynamic>>('/api/requests');
    return response.data!
        .map((e) => MusicRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(ref.watch(apiClientProvider));
});
