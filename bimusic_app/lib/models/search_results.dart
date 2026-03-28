import 'package:freezed_annotation/freezed_annotation.dart';

import 'album.dart';
import 'artist.dart';

part 'search_results.freezed.dart';
part 'search_results.g.dart';

@freezed
class SearchResults with _$SearchResults {
  const factory SearchResults({
    required List<Artist> artists,
    required List<Album> albums,
  }) = _SearchResults;

  factory SearchResults.fromJson(Map<String, dynamic> json) =>
      _$SearchResultsFromJson(json);
}
