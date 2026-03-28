// Plain Dart models for Lidarr artist/album lookup results.
// These are distinct from Artist/Album which are BiMusic library types.
// They represent items that may not yet be in the local library.

class LidarrMediaCover {
  const LidarrMediaCover({
    required this.coverType,
    this.url,
    this.remoteUrl,
  });

  final String coverType;
  final String? url;
  final String? remoteUrl;

  factory LidarrMediaCover.fromJson(Map<String, dynamic> json) {
    return LidarrMediaCover(
      coverType: (json['coverType'] as String?) ?? '',
      url: json['url'] as String?,
      remoteUrl: json['remoteUrl'] as String?,
    );
  }
}

class LidarrArtistResult {
  const LidarrArtistResult({
    required this.id,
    required this.artistName,
    this.foreignArtistId,
    this.overview,
    required this.images,
  });

  final int id;
  final String artistName;
  final String? foreignArtistId;
  final String? overview;
  final List<LidarrMediaCover> images;

  /// Best available cover URL (prefers remoteUrl for external lookup results).
  String? get coverUrl {
    final poster = images.where((i) => i.coverType == 'poster').firstOrNull;
    final cover = images.where((i) => i.coverType == 'cover').firstOrNull;
    final any = images.firstOrNull;
    final best = poster ?? cover ?? any;
    return best?.remoteUrl ?? best?.url;
  }

  factory LidarrArtistResult.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'] as List<dynamic>? ?? [];
    return LidarrArtistResult(
      id: (json['id'] as num?)?.toInt() ?? 0,
      artistName: (json['artistName'] as String?) ?? '',
      foreignArtistId: json['foreignArtistId'] as String?,
      overview: json['overview'] as String?,
      images: rawImages
          .map((e) => LidarrMediaCover.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LidarrAlbumResult {
  const LidarrAlbumResult({
    required this.id,
    required this.title,
    this.foreignAlbumId,
    required this.artist,
    required this.images,
    this.releaseDate,
  });

  final int id;
  final String title;
  final String? foreignAlbumId;
  final LidarrArtistResult artist;
  final List<LidarrMediaCover> images;
  final String? releaseDate;

  String? get releaseYear =>
      releaseDate != null && releaseDate!.length >= 4
          ? releaseDate!.substring(0, 4)
          : null;

  /// Best available cover URL.
  String? get coverUrl {
    final cover = images.where((i) => i.coverType == 'cover').firstOrNull;
    final any = images.firstOrNull;
    final best = cover ?? any;
    return best?.remoteUrl ?? best?.url;
  }

  factory LidarrAlbumResult.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'] as List<dynamic>? ?? [];
    final rawArtist = json['artist'] as Map<String, dynamic>? ?? {};
    return LidarrAlbumResult(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      foreignAlbumId: json['foreignAlbumId'] as String?,
      artist: LidarrArtistResult.fromJson(rawArtist),
      images: rawImages
          .map((e) => LidarrMediaCover.fromJson(e as Map<String, dynamic>))
          .toList(),
      releaseDate: json['releaseDate'] as String?,
    );
  }
}

class LidarrSearchResults {
  const LidarrSearchResults({
    required this.artists,
    required this.albums,
  });

  final List<LidarrArtistResult> artists;
  final List<LidarrAlbumResult> albums;

  factory LidarrSearchResults.fromJson(Map<String, dynamic> json) {
    final rawArtists = json['artists'] as List<dynamic>? ?? [];
    final rawAlbums = json['albums'] as List<dynamic>? ?? [];
    return LidarrSearchResults(
      artists: rawArtists
          .map((e) => LidarrArtistResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      albums: rawAlbums
          .map((e) => LidarrAlbumResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
