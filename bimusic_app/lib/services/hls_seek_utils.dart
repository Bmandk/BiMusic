import 'dart:math';

/// Describes the outcome of an HLS seek computation.
class HlsSeekTarget {
  const HlsSeekTarget({
    required this.targetSegment,
    required this.withinSegment,
    required this.sameSegment,
  });

  /// Zero-based index of the 6-second segment that contains [seekTo].
  final int targetSegment;

  /// Position within [targetSegment] (i.e. seekTo modulo segmentDuration).
  final Duration withinSegment;

  /// True when [targetSegment] equals the segment currently loaded by mpv.
  /// A same-segment seek can be satisfied with a direct `Player.seek()`;
  /// a cross-segment seek requires reloading the playlist with `startSegment`.
  final bool sameSegment;
}

/// Pure computation: given a desired playback position, the current segment
/// offset, and the segment duration, returns which segment to load and
/// where within it to position the playhead.
///
/// [seekTo] is clamped to ≥ 0.
HlsSeekTarget computeHlsSeekTarget({
  required Duration seekTo,
  required Duration currentSegmentOffset,
  required Duration segmentDuration,
}) {
  if (segmentDuration.inMilliseconds <= 0) {
    return HlsSeekTarget(
      targetSegment: 0,
      withinSegment: Duration(milliseconds: max(0, seekTo.inMilliseconds)),
      sameSegment: true,
    );
  }
  final segmentMs = segmentDuration.inMilliseconds;
  final clampedMs = max(0, seekTo.inMilliseconds);
  final targetSegment = clampedMs ~/ segmentMs;
  final withinSegment =
      Duration(milliseconds: clampedMs - targetSegment * segmentMs);
  final currentSegment = currentSegmentOffset.inMilliseconds ~/ segmentMs;
  return HlsSeekTarget(
    targetSegment: targetSegment,
    withinSegment: withinSegment,
    sameSegment: targetSegment == currentSegment,
  );
}

/// Find the queue index whose URI matches [path].
///
/// Tries an exact URI string match first, then falls back to a track-ID prefix
/// extracted from the `/api/stream/<id>/` pattern. The trailing `/` prevents
/// IDs that are numeric prefixes of other IDs (e.g. 1 vs 10) from producing
/// false positives.
///
/// Returns null if [queueUris] is empty or no match is found.
int? matchHlsUriToQueueIndex(String path, List<Uri> queueUris) {
  if (queueUris.isEmpty) return null;
  for (var i = 0; i < queueUris.length; i++) {
    if (queueUris[i].toString() == path) return i;
  }
  final m = RegExp(r'/api/stream/(\d+)/').firstMatch(path);
  if (m == null) return null;
  final prefix = m.group(0)!; // "/api/stream/<id>/"
  for (var i = 0; i < queueUris.length; i++) {
    if (queueUris[i].toString().contains(prefix)) return i;
  }
  return null;
}
