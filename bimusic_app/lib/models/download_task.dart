/// Persisted download record.  One row per (userId, deviceId, trackId) triple.
/// [serverId] is the UUID returned by POST /api/downloads on the backend.
/// State is saved to a JSON file in the app-documents directory on every change.
class DownloadTask {
  DownloadTask({
    required this.serverId,
    required this.trackId,
    required this.albumId,
    required this.artistId,
    required this.userId,
    required this.deviceId,
    required this.status,
    required this.trackTitle,
    required this.trackNumber,
    required this.albumTitle,
    required this.artistName,
    required this.bitrate,
    required this.requestedAt,
    this.progress,
    this.filePath,
    this.fileSizeBytes,
    this.completedAt,
    this.errorMessage,
  });

  final String serverId;
  final int trackId;
  final int albumId;
  final int artistId;
  final String userId;
  final String deviceId;
  DownloadStatus status;
  double? progress;
  String? filePath;
  int? fileSizeBytes;
  DateTime? completedAt;
  String? errorMessage;

  // Denormalised metadata kept for display (avoids extra Lidarr fetches).
  final String trackTitle;
  final String trackNumber;
  final String albumTitle;
  final String artistName;
  final int bitrate;
  final String requestedAt;

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? filePath,
    int? fileSizeBytes,
    DateTime? completedAt,
    String? errorMessage,
  }) =>
      DownloadTask(
        serverId: serverId,
        trackId: trackId,
        albumId: albumId,
        artistId: artistId,
        userId: userId,
        deviceId: deviceId,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        filePath: filePath ?? this.filePath,
        fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
        completedAt: completedAt ?? this.completedAt,
        errorMessage: errorMessage ?? this.errorMessage,
        trackTitle: trackTitle,
        trackNumber: trackNumber,
        albumTitle: albumTitle,
        artistName: artistName,
        bitrate: bitrate,
        requestedAt: requestedAt,
      );

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        serverId: json['serverId'] as String,
        trackId: json['trackId'] as int,
        albumId: json['albumId'] as int,
        artistId: json['artistId'] as int,
        userId: json['userId'] as String,
        deviceId: json['deviceId'] as String,
        status: DownloadStatus.values.byName(json['status'] as String),
        progress: (json['progress'] as num?)?.toDouble(),
        filePath: json['filePath'] as String?,
        fileSizeBytes: json['fileSizeBytes'] as int?,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        errorMessage: json['errorMessage'] as String?,
        trackTitle: json['trackTitle'] as String,
        trackNumber: json['trackNumber'] as String,
        albumTitle: json['albumTitle'] as String,
        artistName: json['artistName'] as String,
        bitrate: json['bitrate'] as int,
        requestedAt: json['requestedAt'] as String,
      );

  Map<String, dynamic> toJson() => {
        'serverId': serverId,
        'trackId': trackId,
        'albumId': albumId,
        'artistId': artistId,
        'userId': userId,
        'deviceId': deviceId,
        'status': status.name,
        'progress': progress,
        'filePath': filePath,
        'fileSizeBytes': fileSizeBytes,
        'completedAt': completedAt?.toIso8601String(),
        'errorMessage': errorMessage,
        'trackTitle': trackTitle,
        'trackNumber': trackNumber,
        'albumTitle': albumTitle,
        'artistName': artistName,
        'bitrate': bitrate,
        'requestedAt': requestedAt,
      };
}

enum DownloadStatus { pending, downloading, completed, failed }
