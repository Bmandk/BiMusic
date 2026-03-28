import 'package:freezed_annotation/freezed_annotation.dart';

part 'track.freezed.dart';
part 'track.g.dart';

@freezed
class Track with _$Track {
  const factory Track({
    required int id,
    required String title,
    required String trackNumber,
    required int duration,
    required int albumId,
    required int artistId,
    required bool hasFile,
    required String streamUrl,
  }) = _Track;

  factory Track.fromJson(Map<String, dynamic> json) => _$TrackFromJson(json);
}
