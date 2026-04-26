import 'package:bimusic_app/models/lidarr_search_results.dart';
import 'package:bimusic_app/models/music_request.dart';
import 'package:bimusic_app/models/playlist_import.dart';
import 'package:bimusic_app/services/playlist_import_service.dart';
import 'package:bimusic_app/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSearchService extends Mock implements SearchService {}

MusicRequest _fakeRequest() => const MusicRequest(
      id: 'fake-id',
      type: 'album',
      lidarrId: 1,
      name: 'test',
      status: 'pending',
      requestedAt: '2025-01-01T00:00:00Z',
    );

void main() {
  late _MockSearchService mockSearch;
  late PlaylistImportService service;

  setUp(() {
    mockSearch = _MockSearchService();
    service = PlaylistImportService(mockSearch);
  });

  // ---------------------------------------------------------------------------
  // parseCsv
  // ---------------------------------------------------------------------------

  group('parseCsv', () {
    test('parses rows from valid CSV', () {
      const csv =
          'Track URI,Track Name,Album Name,Artist Name(s),Release Date\n'
          'id1,"A Song","Timely!!","Anri",1983-12-05\n'
          'id2,"Another Song","Timely!!","Anri",1983-12-05\n'
          "id3,\"Third Song\",\"midnight cruisin'\",\"Kingo Hamada\",1982-10-21\n";

      final rows = service.parseCsv(csv);
      expect(rows.length, 3);
      expect(rows[0].albumName, 'Timely!!');
      expect(rows[0].artistName, 'Anri');
      expect(rows[2].albumName, "midnight cruisin'");
      expect(rows[2].artistName, 'Kingo Hamada');
    });

    test('handles quoted fields with embedded commas', () {
      const csv =
          'Track URI,Track Name,Album Name,Artist Name(s),Release Date\n'
          'id1,"My Song","Best Of, Vol. 1","The Artist",2000\n';

      final rows = service.parseCsv(csv);
      expect(rows.length, 1);
      expect(rows[0].albumName, 'Best Of, Vol. 1');
    });

    test('handles CRLF line endings', () {
      const csv =
          'Track URI,Track Name,Album Name,Artist Name(s)\r\n'
          'id1,"Song","Album","Artist"\r\n';

      final rows = service.parseCsv(csv);
      expect(rows.length, 1);
      expect(rows[0].trackName, 'Song');
    });

    test('throws FormatException when required headers are missing', () {
      const csv = 'Column A,Column B\nval1,val2\n';
      expect(() => service.parseCsv(csv), throwsA(isA<FormatException>()));
    });

    test('throws FormatException on empty CSV', () {
      expect(() => service.parseCsv(''), throwsA(isA<FormatException>()));
    });

    test('takes first artist when multiple artists are listed', () {
      const csv =
          'Track URI,Track Name,Album Name,Artist Name(s)\n'
          'id1,"Song","Album","Artist A, Artist B"\n';

      final rows = service.parseCsv(csv);
      expect(rows[0].artistName, 'Artist A');
    });

    test('skips rows with empty album or artist', () {
      const csv =
          'Track URI,Track Name,Album Name,Artist Name(s)\n'
          'id1,"Song","","Artist"\n'
          'id2,"Song","Album",""\n'
          'id3,"Song","Album","Artist"\n';

      final rows = service.parseCsv(csv);
      expect(rows.length, 1);
    });

    test('handles columns in different order', () {
      const csv =
          'Artist Name(s),Album Name,Track Name\n'
          '"Anri","Timely!!","A Song"\n';

      final rows = service.parseCsv(csv);
      expect(rows.length, 1);
      expect(rows[0].albumName, 'Timely!!');
      expect(rows[0].artistName, 'Anri');
    });
  });

  // ---------------------------------------------------------------------------
  // dedupeAlbums
  // ---------------------------------------------------------------------------

  group('dedupeAlbums', () {
    test('collapses identical album/artist pairs', () {
      final rows = [
        const ImportRow(trackName: 'T1', albumName: 'Timely!!', artistName: 'Anri'),
        const ImportRow(trackName: 'T2', albumName: 'Timely!!', artistName: 'Anri'),
        const ImportRow(
            trackName: 'T3',
            albumName: "midnight cruisin'",
            artistName: 'Kingo Hamada'),
      ];

      final albums = service.dedupeAlbums(rows);
      expect(albums.length, 2);
      expect(albums[0].albumName, 'Timely!!');
      expect(albums[0].trackCount, 2);
      expect(albums[1].trackCount, 1);
    });

    test('deduplication is case-insensitive', () {
      final rows = [
        const ImportRow(trackName: 'T1', albumName: 'Timely!!', artistName: 'Anri'),
        const ImportRow(trackName: 'T2', albumName: 'timely!!', artistName: 'anri'),
      ];

      final albums = service.dedupeAlbums(rows);
      expect(albums.length, 1);
      expect(albums.first.trackCount, 2);
    });

    test('preserves insertion order', () {
      final rows = [
        const ImportRow(trackName: 'T1', albumName: 'Z Album', artistName: 'Z'),
        const ImportRow(trackName: 'T2', albumName: 'A Album', artistName: 'A'),
      ];

      final albums = service.dedupeAlbums(rows);
      expect(albums[0].albumName, 'Z Album');
      expect(albums[1].albumName, 'A Album');
    });
  });

  // ---------------------------------------------------------------------------
  // processAlbum
  // ---------------------------------------------------------------------------

  group('processAlbum', () {
    setUpAll(() {
      registerFallbackValue('');
    });

    const testAlbum = ImportAlbum(
      albumName: 'Timely!!',
      artistName: 'Anri',
      trackCount: 3,
    );

    test('returns requestedAlbum when album match found', () async {
      const albumResult = LidarrAlbumResult(
        id: 42,
        title: 'Timely!!',
        artist: LidarrArtistResult(
          id: 1,
          artistName: 'Anri',
          images: [],
        ),
        images: [],
      );

      when(() => mockSearch.searchLidarr(any())).thenAnswer(
        (_) async =>
            const LidarrSearchResults(artists: [], albums: [albumResult]),
      );
      when(() => mockSearch.requestAlbum(42, coverUrl: null))
          .thenAnswer((_) async => _fakeRequest());

      final result = await service.processAlbum(testAlbum);
      expect(result.status, ImportStatus.requestedAlbum);
      expect(result.matchedTitle, 'Timely!!');
      verify(() => mockSearch.requestAlbum(42, coverUrl: null)).called(1);
    });

    test('uses contains match for album title', () async {
      const albumResult = LidarrAlbumResult(
        id: 7,
        title: 'Timely!! (Remaster)',
        artist: LidarrArtistResult(
          id: 1,
          artistName: 'Anri',
          images: [],
        ),
        images: [],
      );

      when(() => mockSearch.searchLidarr(any())).thenAnswer(
        (_) async =>
            const LidarrSearchResults(artists: [], albums: [albumResult]),
      );
      when(() => mockSearch.requestAlbum(7, coverUrl: null))
          .thenAnswer((_) async => _fakeRequest());

      final result = await service.processAlbum(testAlbum);
      expect(result.status, ImportStatus.requestedAlbum);
    });

    test('falls back to artist request when no album match', () async {
      const artistResult = LidarrArtistResult(
        id: 1,
        artistName: 'Anri',
        foreignArtistId: 'mbid-anri-123',
        images: [],
      );

      when(() => mockSearch.searchLidarr(any())).thenAnswer(
        (_) async =>
            const LidarrSearchResults(artists: [artistResult], albums: []),
      );
      when(() => mockSearch.requestArtist(
            foreignArtistId: any(named: 'foreignArtistId'),
            artistName: any(named: 'artistName'),
            coverUrl: any(named: 'coverUrl'),
          )).thenAnswer((_) async => _fakeRequest());

      final result = await service.processAlbum(testAlbum);
      expect(result.status, ImportStatus.requestedArtist);
      expect(result.matchedTitle, 'Anri');
      verify(() => mockSearch.requestArtist(
            foreignArtistId: 'mbid-anri-123',
            artistName: 'Anri',
            coverUrl: any(named: 'coverUrl'),
          )).called(1);
    });

    test('returns notFound when no match in results', () async {
      when(() => mockSearch.searchLidarr(any())).thenAnswer(
        (_) async =>
            const LidarrSearchResults(artists: [], albums: []),
      );

      final result = await service.processAlbum(testAlbum);
      expect(result.status, ImportStatus.notFound);
    });

    test('returns failed status on network exception', () async {
      when(() => mockSearch.searchLidarr(any()))
          .thenThrow(Exception('network error'));

      final result = await service.processAlbum(testAlbum);
      expect(result.status, ImportStatus.failed);
      expect(result.errorMessage, contains('network error'));
    });

    test('ignores artist result without foreignArtistId', () async {
      const artistResult = LidarrArtistResult(
        id: 1,
        artistName: 'Anri',
        images: [],
      );

      when(() => mockSearch.searchLidarr(any())).thenAnswer(
        (_) async =>
            const LidarrSearchResults(artists: [artistResult], albums: []),
      );

      final result = await service.processAlbum(testAlbum);
      expect(result.status, ImportStatus.notFound);
    });
  });
}
