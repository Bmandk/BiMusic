import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/album.dart';
import 'package:bimusic_app/models/track.dart';

void main() {
  group('Track', () {
    const track = Track(
      id: 1,
      title: 'Track One',
      trackNumber: '1',
      duration: 240,
      albumId: 10,
      artistId: 5,
      hasFile: true,
      streamUrl: 'http://localhost:3000/api/stream/1',
    );

    test('fromJson round-trips via toJson', () {
      final json = track.toJson();
      final restored = Track.fromJson(json);
      expect(restored.id, track.id);
      expect(restored.title, track.title);
      expect(restored.trackNumber, track.trackNumber);
      expect(restored.duration, track.duration);
      expect(restored.albumId, track.albumId);
      expect(restored.artistId, track.artistId);
      expect(restored.hasFile, track.hasFile);
      expect(restored.streamUrl, track.streamUrl);
    });

    test('toJson produces expected keys', () {
      final json = track.toJson();
      expect(json['id'], 1);
      expect(json['title'], 'Track One');
      expect(json['trackNumber'], '1');
      expect(json['duration'], 240);
      expect(json['albumId'], 10);
      expect(json['artistId'], 5);
      expect(json['hasFile'], isTrue);
      expect(json['streamUrl'], 'http://localhost:3000/api/stream/1');
    });
  });

  group('Album', () {
    const album = Album(
      id: 10,
      title: 'Test Album',
      artistId: 5,
      artistName: 'Test Artist',
      imageUrl: 'http://localhost:3000/api/library/albums/10/image',
      releaseDate: '2020-01-01',
      genres: ['Rock', 'Pop'],
      trackCount: 12,
      duration: 3600,
    );

    test('fromJson round-trips via toJson', () {
      final json = album.toJson();
      final restored = Album.fromJson(json);
      expect(restored.id, album.id);
      expect(restored.title, album.title);
      expect(restored.artistId, album.artistId);
      expect(restored.artistName, album.artistName);
      expect(restored.imageUrl, album.imageUrl);
      expect(restored.releaseDate, album.releaseDate);
      expect(restored.genres, album.genres);
      expect(restored.trackCount, album.trackCount);
      expect(restored.duration, album.duration);
    });

    test('toJson produces expected keys', () {
      final json = album.toJson();
      expect(json['id'], 10);
      expect(json['title'], 'Test Album');
      expect(json['releaseDate'], '2020-01-01');
      expect(json['genres'], ['Rock', 'Pop']);
      expect(json['trackCount'], 12);
    });

    test('handles null releaseDate in toJson', () {
      const noDate = Album(
        id: 2,
        title: 'No Date Album',
        artistId: 1,
        artistName: 'Artist',
        imageUrl: 'http://img',
        releaseDate: null,
        genres: [],
        trackCount: 0,
        duration: 0,
      );
      final json = noDate.toJson();
      expect(json['releaseDate'], isNull);
    });
  });
}
