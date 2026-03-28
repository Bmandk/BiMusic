import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/lidarr_search_results.dart';

void main() {
  // ---------------------------------------------------------------------------
  // LidarrMediaCover
  // ---------------------------------------------------------------------------

  group('LidarrMediaCover.fromJson', () {
    test('parses all fields', () {
      final cover = LidarrMediaCover.fromJson({
        'coverType': 'poster',
        'url': '/local/poster.jpg',
        'remoteUrl': 'https://remote/poster.jpg',
      });
      expect(cover.coverType, 'poster');
      expect(cover.url, '/local/poster.jpg');
      expect(cover.remoteUrl, 'https://remote/poster.jpg');
    });

    test('handles missing optional fields', () {
      final cover = LidarrMediaCover.fromJson({'coverType': 'cover'});
      expect(cover.coverType, 'cover');
      expect(cover.url, isNull);
      expect(cover.remoteUrl, isNull);
    });

    test('defaults coverType to empty string when missing', () {
      final cover = LidarrMediaCover.fromJson({});
      expect(cover.coverType, '');
    });
  });

  // ---------------------------------------------------------------------------
  // LidarrArtistResult.fromJson
  // ---------------------------------------------------------------------------

  group('LidarrArtistResult.fromJson', () {
    test('parses all fields', () {
      final result = LidarrArtistResult.fromJson({
        'id': 42,
        'artistName': 'Test Artist',
        'foreignArtistId': 'mbid-42',
        'overview': 'An overview',
        'images': [
          {'coverType': 'poster', 'remoteUrl': 'https://poster.jpg'},
          {'coverType': 'cover', 'remoteUrl': 'https://cover.jpg'},
        ],
      });

      expect(result.id, 42);
      expect(result.artistName, 'Test Artist');
      expect(result.foreignArtistId, 'mbid-42');
      expect(result.overview, 'An overview');
      expect(result.images, hasLength(2));
    });

    test('defaults to 0 and empty string for missing required fields', () {
      final result = LidarrArtistResult.fromJson({});
      expect(result.id, 0);
      expect(result.artistName, '');
      expect(result.foreignArtistId, isNull);
      expect(result.images, isEmpty);
    });

    test('handles null images list', () {
      final result = LidarrArtistResult.fromJson({
        'id': 1,
        'artistName': 'No Images',
        'images': null,
      });
      expect(result.images, isEmpty);
    });

    test('handles numeric id as double', () {
      final result = LidarrArtistResult.fromJson({
        'id': 99.0,
        'artistName': 'Float ID',
      });
      expect(result.id, 99);
    });
  });

  // ---------------------------------------------------------------------------
  // LidarrArtistResult.coverUrl
  // ---------------------------------------------------------------------------

  group('LidarrArtistResult.coverUrl', () {
    test('returns null when images list is empty', () {
      const artist = LidarrArtistResult(
        id: 1,
        artistName: 'Empty',
        images: [],
      );
      expect(artist.coverUrl, isNull);
    });

    test('prefers poster remoteUrl', () {
      const artist = LidarrArtistResult(
        id: 1,
        artistName: 'Artist',
        images: [
          LidarrMediaCover(
              coverType: 'cover', remoteUrl: 'https://cover.jpg'),
          LidarrMediaCover(
              coverType: 'poster', remoteUrl: 'https://poster.jpg'),
        ],
      );
      expect(artist.coverUrl, 'https://poster.jpg');
    });

    test('falls back to cover when no poster', () {
      const artist = LidarrArtistResult(
        id: 1,
        artistName: 'Artist',
        images: [
          LidarrMediaCover(
              coverType: 'cover', remoteUrl: 'https://cover.jpg'),
        ],
      );
      expect(artist.coverUrl, 'https://cover.jpg');
    });

    test('falls back to any image when no poster or cover', () {
      const artist = LidarrArtistResult(
        id: 1,
        artistName: 'Artist',
        images: [
          LidarrMediaCover(
              coverType: 'disc', remoteUrl: 'https://disc.jpg'),
        ],
      );
      expect(artist.coverUrl, 'https://disc.jpg');
    });

    test('uses local url when remoteUrl is null', () {
      const artist = LidarrArtistResult(
        id: 1,
        artistName: 'Artist',
        images: [
          LidarrMediaCover(coverType: 'poster', url: '/local/poster.jpg'),
        ],
      );
      expect(artist.coverUrl, '/local/poster.jpg');
    });

    test('returns null when all images have null urls', () {
      const artist = LidarrArtistResult(
        id: 1,
        artistName: 'Artist',
        images: [
          LidarrMediaCover(coverType: 'poster'),
        ],
      );
      expect(artist.coverUrl, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // LidarrAlbumResult.fromJson
  // ---------------------------------------------------------------------------

  group('LidarrAlbumResult.fromJson', () {
    test('parses all fields', () {
      final result = LidarrAlbumResult.fromJson({
        'id': 10,
        'title': 'Test Album',
        'foreignAlbumId': 'album-mbid',
        'releaseDate': '2020-06-15',
        'images': [
          {'coverType': 'cover', 'remoteUrl': 'https://album.jpg'},
        ],
        'artist': {
          'id': 1,
          'artistName': 'Test Artist',
          'images': [],
        },
      });

      expect(result.id, 10);
      expect(result.title, 'Test Album');
      expect(result.foreignAlbumId, 'album-mbid');
      expect(result.releaseDate, '2020-06-15');
      expect(result.images, hasLength(1));
      expect(result.artist.artistName, 'Test Artist');
    });

    test('defaults id and title for missing fields', () {
      final result = LidarrAlbumResult.fromJson({});
      expect(result.id, 0);
      expect(result.title, '');
      expect(result.images, isEmpty);
      expect(result.releaseDate, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // LidarrAlbumResult.releaseYear
  // ---------------------------------------------------------------------------

  group('LidarrAlbumResult.releaseYear', () {
    test('returns first 4 chars of releaseDate', () {
      const album = LidarrAlbumResult(
        id: 1,
        title: 'Album',
        artist: LidarrArtistResult(id: 1, artistName: 'Artist', images: []),
        images: [],
        releaseDate: '2021-03-15T00:00:00Z',
      );
      expect(album.releaseYear, '2021');
    });

    test('returns null when releaseDate is null', () {
      const album = LidarrAlbumResult(
        id: 1,
        title: 'Album',
        artist: LidarrArtistResult(id: 1, artistName: 'Artist', images: []),
        images: [],
      );
      expect(album.releaseYear, isNull);
    });

    test('returns null when releaseDate is too short', () {
      const album = LidarrAlbumResult(
        id: 1,
        title: 'Album',
        artist: LidarrArtistResult(id: 1, artistName: 'Artist', images: []),
        images: [],
        releaseDate: '202',
      );
      expect(album.releaseYear, isNull);
    });

    test('returns year exactly 4 chars long', () {
      const album = LidarrAlbumResult(
        id: 1,
        title: 'Album',
        artist: LidarrArtistResult(id: 1, artistName: 'Artist', images: []),
        images: [],
        releaseDate: '1999',
      );
      expect(album.releaseYear, '1999');
    });
  });

  // ---------------------------------------------------------------------------
  // LidarrAlbumResult.coverUrl
  // ---------------------------------------------------------------------------

  group('LidarrAlbumResult.coverUrl', () {
    test('returns null when images list is empty', () {
      const album = LidarrAlbumResult(
        id: 1,
        title: 'Album',
        artist: LidarrArtistResult(id: 1, artistName: 'Artist', images: []),
        images: [],
      );
      expect(album.coverUrl, isNull);
    });

    test('prefers cover type remoteUrl', () {
      const album = LidarrAlbumResult(
        id: 1,
        title: 'Album',
        artist: LidarrArtistResult(id: 1, artistName: 'Artist', images: []),
        images: [
          LidarrMediaCover(coverType: 'disc', remoteUrl: 'https://disc.jpg'),
          LidarrMediaCover(
              coverType: 'cover', remoteUrl: 'https://cover.jpg'),
        ],
      );
      expect(album.coverUrl, 'https://cover.jpg');
    });

    test('falls back to first image when no cover type', () {
      const album = LidarrAlbumResult(
        id: 1,
        title: 'Album',
        artist: LidarrArtistResult(id: 1, artistName: 'Artist', images: []),
        images: [
          LidarrMediaCover(coverType: 'disc', remoteUrl: 'https://disc.jpg'),
        ],
      );
      expect(album.coverUrl, 'https://disc.jpg');
    });

    test('falls back to local url when remoteUrl is null', () {
      const album = LidarrAlbumResult(
        id: 1,
        title: 'Album',
        artist: LidarrArtistResult(id: 1, artistName: 'Artist', images: []),
        images: [
          LidarrMediaCover(coverType: 'cover', url: '/local/cover.jpg'),
        ],
      );
      expect(album.coverUrl, '/local/cover.jpg');
    });
  });

  // ---------------------------------------------------------------------------
  // LidarrSearchResults.fromJson
  // ---------------------------------------------------------------------------

  group('LidarrSearchResults.fromJson', () {
    test('parses artists and albums lists', () {
      final results = LidarrSearchResults.fromJson({
        'artists': [
          {
            'id': 1,
            'artistName': 'Artist One',
            'images': [],
          },
        ],
        'albums': [
          {
            'id': 10,
            'title': 'Album One',
            'images': [],
            'artist': {'id': 1, 'artistName': 'Artist One', 'images': []},
          },
        ],
      });

      expect(results.artists, hasLength(1));
      expect(results.albums, hasLength(1));
      expect(results.artists.first.artistName, 'Artist One');
      expect(results.albums.first.title, 'Album One');
    });

    test('handles missing lists as empty', () {
      final results = LidarrSearchResults.fromJson({});
      expect(results.artists, isEmpty);
      expect(results.albums, isEmpty);
    });

    test('handles explicit null lists as empty', () {
      final results = LidarrSearchResults.fromJson({
        'artists': null,
        'albums': null,
      });
      expect(results.artists, isEmpty);
      expect(results.albums, isEmpty);
    });

    test('parses multiple artists', () {
      final results = LidarrSearchResults.fromJson({
        'artists': [
          {'id': 1, 'artistName': 'First', 'images': []},
          {'id': 2, 'artistName': 'Second', 'images': []},
          {'id': 3, 'artistName': 'Third', 'images': []},
        ],
        'albums': [],
      });

      expect(results.artists, hasLength(3));
    });
  });
}
