import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/music_request.dart';

void main() {
  group('MusicRequest.fromJson', () {
    test('parses all fields', () {
      final request = MusicRequest.fromJson({
        'id': 'req-uuid',
        'type': 'artist',
        'lidarrId': 42,
        'name': 'The Beatles',
        'status': 'pending',
        'requestedAt': '2026-03-28T00:00:00Z',
        'resolvedAt': null,
      });

      expect(request.id, 'req-uuid');
      expect(request.type, 'artist');
      expect(request.lidarrId, 42);
      expect(request.name, 'The Beatles');
      expect(request.status, 'pending');
      expect(request.requestedAt, '2026-03-28T00:00:00Z');
      expect(request.resolvedAt, isNull);
    });

    test('defaults name to empty string when absent', () {
      final request = MusicRequest.fromJson({
        'id': 'req-old',
        'type': 'artist',
        'lidarrId': 5,
        'status': 'pending',
        'requestedAt': '2026-03-28T00:00:00Z',
      });

      expect(request.name, '');
    });

    test('parses album type', () {
      final request = MusicRequest.fromJson({
        'id': 'req-2',
        'type': 'album',
        'lidarrId': 99,
        'status': 'downloading',
        'requestedAt': '2026-03-28T01:00:00Z',
      });

      expect(request.type, 'album');
      expect(request.status, 'downloading');
    });

    test('parses available status', () {
      final request = MusicRequest.fromJson({
        'id': 'req-3',
        'type': 'artist',
        'lidarrId': 1,
        'status': 'available',
        'requestedAt': '2026-03-27T00:00:00Z',
        'resolvedAt': '2026-03-28T00:00:00Z',
      });

      expect(request.status, 'available');
      expect(request.resolvedAt, '2026-03-28T00:00:00Z');
    });

    test('handles lidarrId as float', () {
      final request = MusicRequest.fromJson({
        'id': 'req-4',
        'type': 'artist',
        'lidarrId': 42.0,
        'status': 'pending',
        'requestedAt': '2026-03-28T00:00:00Z',
      });

      expect(request.lidarrId, 42);
    });
  });

  group('MusicRequest constructor', () {
    test('exposes all fields', () {
      const request = MusicRequest(
        id: 'req-1',
        type: 'artist',
        lidarrId: 10,
        name: 'Test Artist',
        status: 'pending',
        requestedAt: '2026-03-28T00:00:00Z',
        resolvedAt: '2026-03-29T00:00:00Z',
      );

      expect(request.id, 'req-1');
      expect(request.type, 'artist');
      expect(request.lidarrId, 10);
      expect(request.name, 'Test Artist');
      expect(request.status, 'pending');
      expect(request.requestedAt, '2026-03-28T00:00:00Z');
      expect(request.resolvedAt, '2026-03-29T00:00:00Z');
    });

    test('resolvedAt defaults to null', () {
      const request = MusicRequest(
        id: 'req-1',
        type: 'artist',
        lidarrId: 10,
        name: 'Test Artist',
        status: 'pending',
        requestedAt: '2026-03-28T00:00:00Z',
      );

      expect(request.resolvedAt, isNull);
    });
  });
}
