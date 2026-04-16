import 'track.dart';

class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int trackCount;
  final String createdAt;

  factory PlaylistSummary.fromJson(Map<String, dynamic> json) {
    return PlaylistSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      trackCount: (json['trackCount'] as num).toInt(),
      createdAt: json['createdAt'] as String,
    );
  }
}

class PlaylistDetail {
  const PlaylistDetail({
    required this.id,
    required this.name,
    required this.tracks,
  });

  final String id;
  final String name;
  final List<Track> tracks;

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) {
    return PlaylistDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      tracks: (json['tracks'] as List<dynamic>)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
