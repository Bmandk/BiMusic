import 'package:csv/csv.dart';

import '../models/lidarr_search_results.dart';
import '../models/playlist_import.dart';
import 'search_service.dart';

class PlaylistImportService {
  PlaylistImportService(this._search);

  final SearchService _search;

  /// Parses a Spotify/Exportify CSV string into track rows.
  ///
  /// Required column headers: "Track Name", "Album Name", "Artist Name(s)".
  /// Throws [FormatException] when any required header is absent.
  List<ImportRow> parseCsv(String contents) {
    final normalized = contents
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    const converter = CsvToListConverter(eol: '\n');
    final rows = converter.convert(normalized);

    if (rows.isEmpty) throw const FormatException('CSV file is empty');

    final headers = rows.first.map((h) => h.toString().trim()).toList();
    final trackIdx = headers.indexOf('Track Name');
    final albumIdx = headers.indexOf('Album Name');
    final artistIdx = headers.indexOf('Artist Name(s)');

    if (trackIdx == -1 || albumIdx == -1 || artistIdx == -1) {
      throw const FormatException(
        'Missing required columns: "Track Name", "Album Name", "Artist Name(s)"',
      );
    }

    final minLen = [trackIdx, albumIdx, artistIdx]
        .fold(0, (max, v) => v > max ? v : max) +
        1;

    final result = <ImportRow>[];
    for (final row in rows.skip(1)) {
      if (row.length < minLen) continue;
      final trackName = row[trackIdx].toString().trim();
      final albumName = row[albumIdx].toString().trim();
      final rawArtist = row[artistIdx].toString().trim();
      // Take only the first artist when multiple are comma-separated.
      final artistName = rawArtist.split(',').first.trim();

      if (albumName.isEmpty || artistName.isEmpty) continue;
      result.add(ImportRow(
        trackName: trackName,
        albumName: albumName,
        artistName: artistName,
      ));
    }

    return result;
  }

  /// Collapses rows into unique (album, artist) pairs, counting tracks per album.
  /// Deduplication is case-insensitive. Insertion order is preserved.
  List<ImportAlbum> dedupeAlbums(List<ImportRow> rows) {
    final counts = <String, int>{};
    final first = <String, ({String album, String artist})>{};

    for (final row in rows) {
      final key =
          '${row.albumName.toLowerCase()}||${row.artistName.toLowerCase()}';
      counts[key] = (counts[key] ?? 0) + 1;
      first.putIfAbsent(key, () => (album: row.albumName, artist: row.artistName));
    }

    return first.entries.map((e) {
      return ImportAlbum(
        albumName: e.value.album,
        artistName: e.value.artist,
        trackCount: counts[e.key]!,
      );
    }).toList();
  }

  /// Looks up [album] on Lidarr and submits a request.
  ///
  /// Strategy:
  /// 1. Search Lidarr with "$artistName $albumName".
  /// 2. Try to match an album by artist + title → POST /api/requests/album.
  /// 3. Fall back to matching an artist → POST /api/requests/artist.
  /// 4. Return [ImportStatus.notFound] if nothing matched.
  ///
  /// Errors are caught and returned as [ImportStatus.failed].
  Future<ImportItemResult> processAlbum(ImportAlbum album) async {
    try {
      final results = await _search.searchLidarr(
        '${album.artistName} ${album.albumName}',
      );

      final albumMatch =
          _matchAlbum(results.albums, album.albumName, album.artistName);
      if (albumMatch != null) {
        await _search.requestAlbum(albumMatch.id, coverUrl: albumMatch.coverUrl);
        return ImportItemResult(
          album: album,
          status: ImportStatus.requestedAlbum,
          matchedTitle: albumMatch.title,
        );
      }

      final artistMatch = _matchArtist(results.artists, album.artistName);
      if (artistMatch != null && artistMatch.foreignArtistId != null) {
        await _search.requestArtist(
          foreignArtistId: artistMatch.foreignArtistId!,
          artistName: artistMatch.artistName,
          coverUrl: artistMatch.coverUrl,
        );
        return ImportItemResult(
          album: album,
          status: ImportStatus.requestedArtist,
          matchedTitle: artistMatch.artistName,
        );
      }

      return ImportItemResult(album: album, status: ImportStatus.notFound);
    } catch (e) {
      return ImportItemResult(
        album: album,
        status: ImportStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  LidarrAlbumResult? _matchAlbum(
    List<LidarrAlbumResult> albums,
    String albumName,
    String artistName,
  ) {
    final aLower = albumName.toLowerCase();
    final rLower = artistName.toLowerCase();

    for (final a in albums) {
      if (a.title.toLowerCase() == aLower &&
          a.artist.artistName.toLowerCase() == rLower) {
        return a;
      }
    }
    for (final a in albums) {
      if ((a.title.toLowerCase().contains(aLower) ||
              aLower.contains(a.title.toLowerCase())) &&
          a.artist.artistName.toLowerCase() == rLower) {
        return a;
      }
    }
    return null;
  }

  LidarrArtistResult? _matchArtist(
    List<LidarrArtistResult> artists,
    String artistName,
  ) {
    final lower = artistName.toLowerCase();
    for (final a in artists) {
      if (a.artistName.toLowerCase() == lower) return a;
    }
    return null;
  }
}
