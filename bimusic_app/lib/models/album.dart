import 'package:freezed_annotation/freezed_annotation.dart';

part 'album.freezed.dart';
part 'album.g.dart';

@freezed
class Album with _$Album {
  const factory Album({
    required int id,
    required String title,
    required int artistId,
    required String artistName,
    required String imageUrl,
    String? releaseDate,
    required List<String> genres,
    required int trackCount,
    required int duration,
  }) = _Album;

  factory Album.fromJson(Map<String, dynamic> json) => _$AlbumFromJson(json);
}
