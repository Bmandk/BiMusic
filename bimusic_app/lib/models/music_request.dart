class MusicRequest {
  const MusicRequest({
    required this.id,
    required this.type,
    required this.lidarrId,
    required this.name,
    this.coverUrl,
    required this.status,
    required this.requestedAt,
    this.resolvedAt,
  });

  final String id;

  /// 'artist' or 'album'
  final String type;

  final int lidarrId;

  /// Human-readable artist or album name.
  final String name;

  /// Optional cover art URL (may be null for artist requests or older records).
  final String? coverUrl;

  /// 'pending' | 'downloading' | 'available'
  final String status;

  final String requestedAt;
  final String? resolvedAt;

  factory MusicRequest.fromJson(Map<String, dynamic> json) {
    return MusicRequest(
      id: json['id'] as String,
      type: json['type'] as String,
      lidarrId: (json['lidarrId'] as num).toInt(),
      name: (json['name'] as String?) ?? '',
      coverUrl: json['coverUrl'] as String?,
      status: json['status'] as String,
      requestedAt: json['requestedAt'] as String,
      resolvedAt: json['resolvedAt'] as String?,
    );
  }
}
