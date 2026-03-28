// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AlbumImpl _$$AlbumImplFromJson(Map<String, dynamic> json) => _$AlbumImpl(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      artistId: (json['artistId'] as num).toInt(),
      artistName: json['artistName'] as String,
      imageUrl: json['imageUrl'] as String,
      releaseDate: json['releaseDate'] as String?,
      genres:
          (json['genres'] as List<dynamic>).map((e) => e as String).toList(),
      trackCount: (json['trackCount'] as num).toInt(),
      duration: (json['duration'] as num).toInt(),
    );

Map<String, dynamic> _$$AlbumImplToJson(_$AlbumImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'artistId': instance.artistId,
      'artistName': instance.artistName,
      'imageUrl': instance.imageUrl,
      'releaseDate': instance.releaseDate,
      'genres': instance.genres,
      'trackCount': instance.trackCount,
      'duration': instance.duration,
    };
