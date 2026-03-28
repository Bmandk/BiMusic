// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TrackImpl _$$TrackImplFromJson(Map<String, dynamic> json) => _$TrackImpl(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      trackNumber: json['trackNumber'] as String,
      duration: (json['duration'] as num).toInt(),
      albumId: (json['albumId'] as num).toInt(),
      artistId: (json['artistId'] as num).toInt(),
      hasFile: json['hasFile'] as bool,
      streamUrl: json['streamUrl'] as String,
    );

Map<String, dynamic> _$$TrackImplToJson(_$TrackImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'trackNumber': instance.trackNumber,
      'duration': instance.duration,
      'albumId': instance.albumId,
      'artistId': instance.artistId,
      'hasFile': instance.hasFile,
      'streamUrl': instance.streamUrl,
    };
