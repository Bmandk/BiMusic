import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../services/music_service.dart';

// ---------------------------------------------------------------------------
// Artists list — cached until explicit refresh
// ---------------------------------------------------------------------------

class LibraryNotifier extends AsyncNotifier<List<Artist>> {
  @override
  Future<List<Artist>> build() {
    return ref.read(musicServiceProvider).getArtists();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(musicServiceProvider).getArtists(),
    );
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, List<Artist>>(LibraryNotifier.new);

// ---------------------------------------------------------------------------
// Per-item providers
// ---------------------------------------------------------------------------

final artistProvider = FutureProvider.family<Artist, int>((ref, id) {
  return ref.read(musicServiceProvider).getArtist(id);
});

final artistAlbumsProvider = FutureProvider.family<List<Album>, int>((ref, id) {
  return ref.read(musicServiceProvider).getArtistAlbums(id);
});

final albumProvider = FutureProvider.family<Album, int>((ref, id) {
  return ref.read(musicServiceProvider).getAlbum(id);
});

final albumTracksProvider = FutureProvider.family<List<Track>, int>((ref, id) {
  return ref.read(musicServiceProvider).getAlbumTracks(id);
});
