import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/artist.dart';
import 'package:bimusic_app/providers/library_provider.dart';
import 'package:bimusic_app/services/music_service.dart';

class MockMusicService extends Mock implements MusicService {}

void main() {
  late MockMusicService mockService;
  late ProviderContainer container;

  const testArtist1 = Artist(
    id: 1,
    name: 'Artist One',
    imageUrl: 'http://example.com/1.jpg',
    albumCount: 2,
  );

  const testArtist2 = Artist(
    id: 2,
    name: 'Artist Two',
    imageUrl: 'http://example.com/2.jpg',
    albumCount: 1,
  );

  setUp(() {
    mockService = MockMusicService();
    container = ProviderContainer(
      overrides: [
        musicServiceProvider.overrideWith((_) => mockService),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('libraryProvider', () {
    test('build loads artists on first access', () async {
      when(() => mockService.getArtists())
          .thenAnswer((_) async => [testArtist1]);

      final result = await container.read(libraryProvider.future);

      expect(result, hasLength(1));
      expect(result.first.id, 1);
      verify(() => mockService.getArtists()).called(1);
    });

    test('refresh reloads the artist list', () async {
      when(() => mockService.getArtists())
          .thenAnswer((_) async => [testArtist1]);

      // Initial load.
      await container.read(libraryProvider.future);
      expect(container.read(libraryProvider).value, hasLength(1));

      // Stub a second response for refresh.
      when(() => mockService.getArtists())
          .thenAnswer((_) async => [testArtist1, testArtist2]);

      await container.read(libraryProvider.notifier).refresh();

      expect(container.read(libraryProvider).value, hasLength(2));
      expect(container.read(libraryProvider).value!.last.id, 2);
    });

    test('refresh sets AsyncLoading before resolving', () async {
      when(() => mockService.getArtists())
          .thenAnswer((_) async => [testArtist1]);
      await container.read(libraryProvider.future);

      final loadingStates = <bool>[];
      container.listen(
        libraryProvider,
        (_, next) => loadingStates.add(next.isLoading),
      );

      when(() => mockService.getArtists())
          .thenAnswer((_) async => [testArtist2]);

      await container.read(libraryProvider.notifier).refresh();

      expect(loadingStates, contains(true));
    });
  });

  group('artistProvider', () {
    test('fetches single artist by id', () async {
      when(() => mockService.getArtist(1))
          .thenAnswer((_) async => testArtist1);

      final result = await container.read(artistProvider(1).future);

      expect(result.id, 1);
      expect(result.name, 'Artist One');
    });
  });
}
