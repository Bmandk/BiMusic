import 'package:flutter_test/flutter_test.dart';
import 'package:bimusic_app/services/hls_seek_utils.dart';

void main() {
  const seg = Duration(seconds: 6);

  // ──────────────────────────────────────────────
  // computeHlsSeekTarget
  // ──────────────────────────────────────────────

  group('computeHlsSeekTarget', () {
    test('returns segment 0 and same-segment=true when seeking within segment 0', () {
      final t = computeHlsSeekTarget(
        seekTo: const Duration(seconds: 3),
        currentSegmentOffset: Duration.zero,
        segmentDuration: seg,
      );
      expect(t.targetSegment, 0);
      expect(t.withinSegment, const Duration(seconds: 3));
      expect(t.sameSegment, isTrue);
    });

    test('returns segment 1 and same-segment=false when seeking into second segment', () {
      final t = computeHlsSeekTarget(
        seekTo: const Duration(seconds: 7),
        currentSegmentOffset: Duration.zero,
        segmentDuration: seg,
      );
      expect(t.targetSegment, 1);
      expect(t.withinSegment, const Duration(seconds: 1));
      expect(t.sameSegment, isFalse);
    });

    test('same-segment=true when current offset is also in segment 1', () {
      final t = computeHlsSeekTarget(
        seekTo: const Duration(seconds: 9),
        currentSegmentOffset: const Duration(seconds: 6),
        segmentDuration: seg,
      );
      expect(t.targetSegment, 1);
      expect(t.withinSegment, const Duration(seconds: 3));
      expect(t.sameSegment, isTrue);
    });

    test('clamps negative seekTo to segment 0, withinSegment=0', () {
      final t = computeHlsSeekTarget(
        seekTo: const Duration(milliseconds: -500),
        currentSegmentOffset: Duration.zero,
        segmentDuration: seg,
      );
      expect(t.targetSegment, 0);
      expect(t.withinSegment, Duration.zero);
      expect(t.sameSegment, isTrue);
    });

    test('exact segment boundary lands at withinSegment=0 of next segment', () {
      final t = computeHlsSeekTarget(
        seekTo: const Duration(seconds: 12),
        currentSegmentOffset: Duration.zero,
        segmentDuration: seg,
      );
      expect(t.targetSegment, 2);
      expect(t.withinSegment, Duration.zero);
      expect(t.sameSegment, isFalse);
    });

    test('large seek computes correct segment and remainder', () {
      // 3 min 37 s = 217 s = 36 * 6 + 1
      final t = computeHlsSeekTarget(
        seekTo: const Duration(seconds: 217),
        currentSegmentOffset: Duration.zero,
        segmentDuration: seg,
      );
      expect(t.targetSegment, 36);
      expect(t.withinSegment, const Duration(seconds: 1));
      expect(t.sameSegment, isFalse);
    });
  });

  // ──────────────────────────────────────────────
  // matchHlsUriToQueueIndex
  // ──────────────────────────────────────────────

  group('matchHlsUriToQueueIndex', () {
    final uris = [
      Uri.parse('http://host/api/stream/1/playlist.m3u8?bitrate=128&token=t'),
      Uri.parse('http://host/api/stream/10/playlist.m3u8?bitrate=128&token=t'),
      Uri.parse('http://host/api/stream/99/playlist.m3u8?bitrate=128&token=t'),
    ];

    test('exact match returns correct index', () {
      expect(
        matchHlsUriToQueueIndex(
          'http://host/api/stream/10/playlist.m3u8?bitrate=128&token=t',
          uris,
        ),
        1,
      );
    });

    test('segment URL prefix-matches the correct queue entry', () {
      // Segment URL carries the track ID; should resolve to track 1 (index 0)
      expect(
        matchHlsUriToQueueIndex(
          'http://host/api/stream/1/segment/005?bitrate=128&token=t',
          uris,
        ),
        0,
      );
    });

    test('track ID 1 does NOT false-positive match track ID 10', () {
      final result = matchHlsUriToQueueIndex(
        'http://host/api/stream/1/segment/000?bitrate=128&token=t',
        uris,
      );
      // Must match track 1 (index 0), not track 10 (index 1)
      expect(result, 0);
    });

    test('track ID 10 prefix-matches only index 1', () {
      expect(
        matchHlsUriToQueueIndex(
          'http://host/api/stream/10/segment/003?bitrate=128&token=t',
          uris,
        ),
        1,
      );
    });

    test('returns null when no match', () {
      expect(
        matchHlsUriToQueueIndex(
          'http://host/api/stream/42/segment/000',
          uris,
        ),
        isNull,
      );
    });

    test('returns null when queue is empty', () {
      expect(matchHlsUriToQueueIndex('http://host/api/stream/1/segment/000', []), isNull);
    });

    test('returns null for non-HLS path (no /api/stream/ pattern)', () {
      expect(
        matchHlsUriToQueueIndex('http://host/some/other/path', uris),
        isNull,
      );
    });
  });
}
