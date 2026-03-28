import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import '../services/playlist_service.dart';

class PlaylistNotifier extends AsyncNotifier<List<PlaylistSummary>> {
  @override
  Future<List<PlaylistSummary>> build() {
    return ref.read(playlistServiceProvider).listPlaylists();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(playlistServiceProvider).listPlaylists(),
    );
  }

  Future<PlaylistSummary> createPlaylist(String name) async {
    final playlist =
        await ref.read(playlistServiceProvider).createPlaylist(name);
    await refresh();
    return playlist;
  }

  Future<void> updatePlaylist(String id, String name) async {
    await ref.read(playlistServiceProvider).updatePlaylist(id, name);
    await refresh();
    ref.invalidate(playlistDetailProvider(id));
  }

  Future<void> deletePlaylist(String id) async {
    await ref.read(playlistServiceProvider).deletePlaylist(id);
    await refresh();
    ref.invalidate(playlistDetailProvider(id));
  }

  Future<void> addTracks(String playlistId, List<int> trackIds) async {
    await ref.read(playlistServiceProvider).addTracks(playlistId, trackIds);
    await refresh();
    ref.invalidate(playlistDetailProvider(playlistId));
  }

  Future<void> removeTrack(String playlistId, int trackId) async {
    await ref.read(playlistServiceProvider).removeTrack(playlistId, trackId);
    await refresh();
    ref.invalidate(playlistDetailProvider(playlistId));
  }

  Future<void> reorderTracks(String playlistId, List<int> trackIds) async {
    await ref.read(playlistServiceProvider).reorderTracks(playlistId, trackIds);
    ref.invalidate(playlistDetailProvider(playlistId));
  }
}

final playlistProvider =
    AsyncNotifierProvider<PlaylistNotifier, List<PlaylistSummary>>(
  PlaylistNotifier.new,
);

final playlistDetailProvider =
    FutureProvider.family<PlaylistDetail, String>((ref, id) {
  return ref.read(playlistServiceProvider).getPlaylist(id);
});
