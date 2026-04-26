class ImportRow {
  const ImportRow({
    required this.trackName,
    required this.albumName,
    required this.artistName,
  });

  final String trackName;
  final String albumName;
  final String artistName;
}

class ImportAlbum {
  const ImportAlbum({
    required this.albumName,
    required this.artistName,
    required this.trackCount,
  });

  final String albumName;
  final String artistName;
  final int trackCount;
}

enum ImportStatus {
  pending,
  searching,
  requestedAlbum,
  requestedArtist,
  notFound,
  failed,
}

class ImportItemResult {
  ImportItemResult({
    required this.album,
    this.status = ImportStatus.pending,
    this.errorMessage,
    this.matchedTitle,
  });

  final ImportAlbum album;
  ImportStatus status;
  String? errorMessage;
  String? matchedTitle;
}
