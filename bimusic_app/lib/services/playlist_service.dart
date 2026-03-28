import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import 'api_client.dart';

class PlaylistService {
  PlaylistService(this._dio);

  final Dio _dio;

  Future<List<PlaylistSummary>> listPlaylists() async {
    final response = await _dio.get<List<dynamic>>('/api/playlists');
    return response.data!
        .map((e) => PlaylistSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlaylistSummary> createPlaylist(String name) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/playlists',
      data: {'name': name},
    );
    final data = response.data!;
    return PlaylistSummary(
      id: data['id'] as String,
      name: data['name'] as String,
      trackCount: 0,
      createdAt: data['createdAt'] as String,
    );
  }

  Future<PlaylistDetail> getPlaylist(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/playlists/$id');
    return PlaylistDetail.fromJson(response.data!);
  }

  Future<void> updatePlaylist(String id, String name) async {
    await _dio.put<void>('/api/playlists/$id', data: {'name': name});
  }

  Future<void> deletePlaylist(String id) async {
    await _dio.delete<void>('/api/playlists/$id');
  }

  Future<void> addTracks(String playlistId, List<int> trackIds) async {
    await _dio.post<void>(
      '/api/playlists/$playlistId/tracks',
      data: {'trackIds': trackIds},
    );
  }

  Future<void> removeTrack(String playlistId, int trackId) async {
    await _dio.delete<void>('/api/playlists/$playlistId/tracks/$trackId');
  }

  Future<void> reorderTracks(String playlistId, List<int> trackIds) async {
    await _dio.put<void>(
      '/api/playlists/$playlistId/tracks/reorder',
      data: {'trackIds': trackIds},
    );
  }
}

final playlistServiceProvider = Provider<PlaylistService>((ref) {
  return PlaylistService(ref.watch(apiClientProvider));
});
