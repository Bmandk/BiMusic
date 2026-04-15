import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bimusic_app/models/artist.dart';
import 'package:bimusic_app/models/lidarr_search_results.dart';
import 'package:bimusic_app/models/music_request.dart';
import 'package:bimusic_app/models/search_results.dart';
import 'package:bimusic_app/providers/search_provider.dart';
import 'package:bimusic_app/services/search_service.dart';

class MockSearchService extends Mock implements SearchService {}

void main() {
  late MockSearchService mockService;
  late ProviderContainer container;

  const emptyLibraryResults = SearchResults(artists: [], albums: []);
  const emptyLidarrResults = LidarrSearchResults(artists: [], albums: []);

  const testArtistResult = LidarrArtistResult(
    id: 42,
    artistName: 'Test Artist',
    foreignArtistId: 'mbid-42',
    images: [],
  );

  const testAlbumResult = LidarrAlbumResult(
    id: 10,
    title: 'Test Album',
    artist: testArtistResult,
    images: [],
  );

  const testRequest = MusicRequest(
    id: 'req-1',
    type: 'artist',
    lidarrId: 42,
    name: 'Test Artist',
    status: 'pending',
    requestedAt: '2026-03-28T00:00:00Z',
  );

  setUp(() {
    mockService = MockSearchService();
    container = ProviderContainer(
      overrides: [
        searchServiceProvider.overrideWith((_) => mockService),
      ],
    );
  });

  tearDown(() => container.dispose());

  // Helpers to read current state/notifier from the container.
  SearchNotifier n() => container.read(searchProvider.notifier);
  SearchState s() => container.read(searchProvider);

  group('initial state', () {
    test('starts with empty query and no results', () {
      expect(s().query, '');
      expect(s().libraryResults, isNull);
      expect(s().lidarrResults, isNull);
      expect(s().isSearchingLibrary, isFalse);
      expect(s().isSearchingLidarr, isFalse);
    });
  });

  group('setQuery', () {
    test('clearing query resets all results immediately', () {
      when(() => mockService.searchLibrary(any()))
          .thenAnswer((_) async => emptyLibraryResults);

      n().setQuery('hello');
      n().setQuery('');

      expect(s().query, '');
      expect(s().libraryResults, isNull);
      expect(s().isSearchingLibrary, isFalse);
    });

    test('does NOT call searchLibrary before 300ms debounce', () async {
      when(() => mockService.searchLibrary(any()))
          .thenAnswer((_) async => emptyLibraryResults);

      n().setQuery('rock');

      verifyNever(() => mockService.searchLibrary(any()));
    });

    test('calls searchLibrary after 300ms debounce', () async {
      when(() => mockService.searchLibrary('rock'))
          .thenAnswer((_) async => emptyLibraryResults);

      n().setQuery('rock');

      await Future<void>.delayed(const Duration(milliseconds: 350));

      verify(() => mockService.searchLibrary('rock')).called(1);
    });

    test('debounce resets on rapid successive calls — only last fires', () async {
      when(() => mockService.searchLibrary(any()))
          .thenAnswer((_) async => emptyLibraryResults);

      n().setQuery('r');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      n().setQuery('ro');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      n().setQuery('rock');

      await Future<void>.delayed(const Duration(milliseconds: 350));

      verify(() => mockService.searchLibrary('rock')).called(1);
      verifyNever(() => mockService.searchLibrary('r'));
      verifyNever(() => mockService.searchLibrary('ro'));
    });

    test('sets isSearchingLibrary true while fetching', () async {
      final completer = Completer<SearchResults>();
      when(() => mockService.searchLibrary(any()))
          .thenAnswer((_) => completer.future);

      n().setQuery('blues');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(s().isSearchingLibrary, isTrue);
      completer.complete(emptyLibraryResults);
    });

    test('populates libraryResults on success', () async {
      const results = SearchResults(
        artists: [
          Artist(id: 1, name: 'Blues Band', imageUrl: 'http://img', albumCount: 3),
        ],
        albums: [],
      );
      when(() => mockService.searchLibrary('blues'))
          .thenAnswer((_) async => results);

      n().setQuery('blues');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await Future<void>.delayed(Duration.zero);

      expect(s().libraryResults?.artists.length, 1);
      expect(s().isSearchingLibrary, isFalse);
    });

    test('sets libraryError on failure', () async {
      when(() => mockService.searchLibrary(any()))
          .thenThrow(Exception('network error'));

      n().setQuery('jazz');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await Future<void>.delayed(Duration.zero);

      expect(s().libraryError, isNotNull);
      expect(s().isSearchingLibrary, isFalse);
    });

    test('stale response is discarded when query has changed', () async {
      final slowCompleter = Completer<SearchResults>();
      when(() => mockService.searchLibrary('old'))
          .thenAnswer((_) => slowCompleter.future);
      when(() => mockService.searchLibrary('new'))
          .thenAnswer((_) async => emptyLibraryResults);

      n().setQuery('old');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      n().setQuery('new');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await Future<void>.delayed(Duration.zero);

      // Resolve stale response after query has already changed to 'new'
      slowCompleter.complete(const SearchResults(
        artists: [
          Artist(id: 99, name: 'Stale Artist', imageUrl: 'x', albumCount: 0),
        ],
        albums: [],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(s().libraryResults?.artists.where((a) => a.id == 99), isEmpty);
    });
  });

  group('searchLidarr', () {
    test('is a no-op when query is empty', () async {
      await n().searchLidarr();
      verifyNever(() => mockService.searchLidarr(any()));
    });

    test('sets isSearchingLidarr then populates results', () async {
      when(() => mockService.searchLibrary(any()))
          .thenAnswer((_) async => emptyLibraryResults);
      when(() => mockService.searchLidarr('metal'))
          .thenAnswer((_) async => emptyLidarrResults);

      n().setQuery('metal');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await Future<void>.delayed(Duration.zero);

      final future = n().searchLidarr();
      expect(s().isSearchingLidarr, isTrue);
      await future;

      expect(s().lidarrResults, isNotNull);
      expect(s().isSearchingLidarr, isFalse);
    });

    test('sets lidarrError on failure', () async {
      when(() => mockService.searchLibrary(any()))
          .thenAnswer((_) async => emptyLibraryResults);
      when(() => mockService.searchLidarr(any()))
          .thenThrow(Exception('lidarr down'));

      n().setQuery('pop');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await Future<void>.delayed(Duration.zero);

      await n().searchLidarr();

      expect(s().lidarrError, isNotNull);
      expect(s().isSearchingLidarr, isFalse);
    });
  });

  group('requestArtist', () {
    test('transitions idle → submitting → submitted on success', () async {
      when(() => mockService.requestArtist(
            foreignArtistId: any(named: 'foreignArtistId'),
            artistName: any(named: 'artistName'),
          )).thenAnswer((_) async => testRequest);

      final key = 'artist:${testArtistResult.id}';

      final future = n().requestArtist(testArtistResult);
      expect(s().requestStatuses[key], RequestSubmitStatus.submitting);
      await future;
      expect(s().requestStatuses[key], RequestSubmitStatus.submitted);
    });

    test('transitions to error on service failure', () async {
      when(() => mockService.requestArtist(
            foreignArtistId: any(named: 'foreignArtistId'),
            artistName: any(named: 'artistName'),
          )).thenThrow(Exception('server error'));

      final key = 'artist:${testArtistResult.id}';

      await n().requestArtist(testArtistResult);
      expect(s().requestStatuses[key], RequestSubmitStatus.error);
    });

    test('sets error immediately when foreignArtistId is null', () async {
      const artistWithoutId = LidarrArtistResult(
        id: 99,
        artistName: 'No ID',
        foreignArtistId: null,
        images: [],
      );

      await n().requestArtist(artistWithoutId);

      expect(s().requestStatuses['artist:99'], RequestSubmitStatus.error);
      verifyNever(() => mockService.requestArtist(
            foreignArtistId: any(named: 'foreignArtistId'),
            artistName: any(named: 'artistName'),
          ));
    });
  });

  group('requestAlbum', () {
    test('transitions idle → submitting → submitted on success', () async {
      when(() => mockService.requestAlbum(any()))
          .thenAnswer((_) async => testRequest);

      final key = 'album:${testAlbumResult.id}';

      final future = n().requestAlbum(testAlbumResult);
      expect(s().requestStatuses[key], RequestSubmitStatus.submitting);
      await future;
      expect(s().requestStatuses[key], RequestSubmitStatus.submitted);
    });

    test('transitions to error on failure', () async {
      when(() => mockService.requestAlbum(any()))
          .thenThrow(Exception('bad'));

      await n().requestAlbum(testAlbumResult);
      expect(
        s().requestStatuses['album:${testAlbumResult.id}'],
        RequestSubmitStatus.error,
      );
    });
  });
}
