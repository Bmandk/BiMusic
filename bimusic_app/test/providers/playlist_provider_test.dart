import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/playlist.dart';
import 'package:bimusic_app/providers/playlist_provider.dart';
import 'package:bimusic_app/services/playlist_service.dart';

class MockPlaylistService extends Mock implements PlaylistService {}

void main() {
  late MockPlaylistService mockService;
  late ProviderContainer container;

  const summary1 = PlaylistSummary(
    id: 'pl-1',
    name: 'Alpha',
    trackCount: 2,
    createdAt: '2026-01-01T00:00:00Z',
  );

  const summary2 = PlaylistSummary(
    id: 'pl-2',
    name: 'Beta',
    trackCount: 0,
    createdAt: '2026-01-02T00:00:00Z',
  );

  const newSummary = PlaylistSummary(
    id: 'pl-new',
    name: 'New',
    trackCount: 0,
    createdAt: '2026-03-28T00:00:00Z',
  );

  const emptyDetail = PlaylistDetail(id: 'pl-1', name: 'Alpha', tracks: []);

  setUp(() {
    mockService = MockPlaylistService();
    container = ProviderContainer(
      overrides: [
        playlistServiceProvider.overrideWith((_) => mockService),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('build', () {
    test('loads playlist list on first access', () async {
      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1]);

      final result = await container.read(playlistProvider.future);

      expect(result, hasLength(1));
      expect(result.first.id, 'pl-1');
      verify(() => mockService.listPlaylists()).called(1);
    });
  });

  group('refresh', () {
    test('reloads the playlist list', () async {
      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1]);
      await container.read(playlistProvider.future);

      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1, summary2]);

      await container.read(playlistProvider.notifier).refresh();

      expect(container.read(playlistProvider).value, hasLength(2));
    });
  });

  group('createPlaylist', () {
    test('creates playlist and refreshes list', () async {
      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1]);
      when(() => mockService.createPlaylist(any()))
          .thenAnswer((_) async => newSummary);
      await container.read(playlistProvider.future);

      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1, newSummary]);

      final result =
          await container.read(playlistProvider.notifier).createPlaylist('New');

      expect(result.id, 'pl-new');
      expect(container.read(playlistProvider).value, hasLength(2));
      verify(() => mockService.createPlaylist('New')).called(1);
    });
  });

  group('updatePlaylist', () {
    test('updates playlist and refreshes list', () async {
      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1]);
      when(() => mockService.updatePlaylist(any(), any()))
          .thenAnswer((_) async {});
      await container.read(playlistProvider.future);

      // After update, list refreshes
      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary2]);
      // getPlaylist is called by playlistDetailProvider when invalidated
      when(() => mockService.getPlaylist(any()))
          .thenAnswer((_) async => emptyDetail);

      await container
          .read(playlistProvider.notifier)
          .updatePlaylist('pl-1', 'Renamed');

      verify(() => mockService.updatePlaylist('pl-1', 'Renamed')).called(1);
      expect(container.read(playlistProvider).value, hasLength(1));
    });
  });

  group('deletePlaylist', () {
    test('deletes playlist and refreshes list', () async {
      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1, summary2]);
      when(() => mockService.deletePlaylist(any()))
          .thenAnswer((_) async {});
      await container.read(playlistProvider.future);

      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary2]);
      when(() => mockService.getPlaylist(any()))
          .thenAnswer((_) async => emptyDetail);

      await container
          .read(playlistProvider.notifier)
          .deletePlaylist('pl-1');

      verify(() => mockService.deletePlaylist('pl-1')).called(1);
      expect(container.read(playlistProvider).value, hasLength(1));
    });
  });

  group('addTracks', () {
    test('adds tracks and refreshes list', () async {
      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1]);
      when(() => mockService.addTracks(any(), any()))
          .thenAnswer((_) async {});
      await container.read(playlistProvider.future);

      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1]);
      when(() => mockService.getPlaylist(any()))
          .thenAnswer((_) async => emptyDetail);

      await container
          .read(playlistProvider.notifier)
          .addTracks('pl-1', [1, 2, 3]);

      verify(() => mockService.addTracks('pl-1', [1, 2, 3])).called(1);
    });
  });

  group('removeTrack', () {
    test('removes track and refreshes list', () async {
      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1]);
      when(() => mockService.removeTrack(any(), any()))
          .thenAnswer((_) async {});
      await container.read(playlistProvider.future);

      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1]);
      when(() => mockService.getPlaylist(any()))
          .thenAnswer((_) async => emptyDetail);

      await container
          .read(playlistProvider.notifier)
          .removeTrack('pl-1', 99);

      verify(() => mockService.removeTrack('pl-1', 99)).called(1);
    });
  });

  group('reorderTracks', () {
    test('reorders tracks and invalidates detail', () async {
      when(() => mockService.listPlaylists())
          .thenAnswer((_) async => [summary1]);
      when(() => mockService.reorderTracks(any(), any()))
          .thenAnswer((_) async {});
      when(() => mockService.getPlaylist(any()))
          .thenAnswer((_) async => emptyDetail);
      await container.read(playlistProvider.future);

      await container
          .read(playlistProvider.notifier)
          .reorderTracks('pl-1', [3, 1, 2]);

      verify(() => mockService.reorderTracks('pl-1', [3, 1, 2])).called(1);
    });
  });

  group('playlistDetailProvider', () {
    test('fetches playlist detail by id', () async {
      const detail = PlaylistDetail(
        id: 'pl-1',
        name: 'Alpha',
        tracks: [],
      );
      when(() => mockService.getPlaylist('pl-1'))
          .thenAnswer((_) async => detail);

      final result =
          await container.read(playlistDetailProvider('pl-1').future);

      expect(result.id, 'pl-1');
      expect(result.name, 'Alpha');
    });
  });
}
