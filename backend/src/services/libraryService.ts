import type { AxiosResponse } from "axios";
import type { Readable } from "stream";
import * as lidarrClient from "./lidarrClient.js";
import { logger } from "../utils/logger.js";
import type {
  LidarrArtist,
  LidarrAlbum,
  LidarrTrack,
  LidarrMediaCover,
} from "../types/lidarr.js";
import type { Artist, Album, Track, SearchResults } from "../types/api.js";

function getImageFilename(
  images: LidarrMediaCover[] | null,
  coverType: string,
): string {
  const image = images?.find((img) => img.coverType === coverType);
  if (!image?.url) return `${coverType}.jpg`;
  const urlPath = image.url.split("?")[0] ?? "";
  const parts = urlPath.split("/");
  return parts[parts.length - 1] || `${coverType}.jpg`;
}

function shapeArtist(a: LidarrArtist, albumCount: number): Artist {
  return {
    id: a.id,
    name: a.artistName ?? "Unknown Artist",
    overview: a.overview,
    imageUrl: `/api/library/artists/${a.id}/image`,
    albumCount,
  };
}

function shapeAlbum(a: LidarrAlbum, trackCount: number): Album {
  return {
    id: a.id,
    title: a.title ?? "Unknown Album",
    artistId: a.artistId,
    artistName: a.artist?.artistName ?? "Unknown Artist",
    imageUrl: `/api/library/albums/${a.id}/image`,
    releaseDate: a.releaseDate,
    genres: a.genres ?? [],
    trackCount,
    duration: a.duration ?? 0,
  };
}

function shapeTrack(t: LidarrTrack): Track {
  return {
    id: t.id,
    title: t.title ?? "Unknown Track",
    trackNumber: t.trackNumber ?? "0",
    duration: t.duration,
    albumId: t.albumId,
    artistId: t.artistId,
    hasFile: t.hasFile,
    streamUrl: `/api/stream/${t.id}`,
  };
}

export async function getArtists(): Promise<Artist[]> {
  const [artists, albums] = await Promise.all([
    lidarrClient.getArtists(),
    lidarrClient.getAlbums(),
  ]);
  const albumCountByArtistId = new Map<number, number>();
  for (const album of albums) {
    albumCountByArtistId.set(
      album.artistId,
      (albumCountByArtistId.get(album.artistId) ?? 0) + 1,
    );
  }
  return artists.map((a) =>
    shapeArtist(a, albumCountByArtistId.get(a.id) ?? 0),
  );
}

export async function getArtist(id: number): Promise<Artist> {
  const [artist, albums] = await Promise.all([
    lidarrClient.getArtist(id),
    lidarrClient.getAlbums(id),
  ]);
  return shapeArtist(artist, albums.length);
}

export async function getArtistAlbums(artistId: number): Promise<Album[]> {
  const albums = await lidarrClient.getAlbums(artistId);
  // trackCount not fetched here to avoid N+1 calls; populated in getAlbum()
  return albums.map((a) => shapeAlbum(a, 0));
}

export async function getAlbum(id: number): Promise<Album> {
  const [album, tracks] = await Promise.all([
    lidarrClient.getAlbum(id),
    lidarrClient.getTracks(id),
  ]);
  return shapeAlbum(album, tracks.length);
}

export async function getAlbumTracks(albumId: number): Promise<Track[]> {
  const tracks = await lidarrClient.getTracks(albumId);
  return tracks.map((t) => shapeTrack(t));
}

export async function getTrack(id: number): Promise<Track> {
  const track = await lidarrClient.getTrack(id);
  return shapeTrack(track);
}

export async function search(term: string): Promise<SearchResults> {
  logger.debug({ term }, "libraryService.search: calling Lidarr search");
  const results = await lidarrClient.search(term);

  const artistsMap = new Map<number, LidarrArtist>();
  const albums: Album[] = [];

  for (const result of results) {
    if (result.artist) {
      artistsMap.set(result.artist.id, result.artist);
    }
    if (result.album) {
      albums.push(shapeAlbum(result.album, 0));
    }
  }

  const artists = Array.from(artistsMap.values()).map((a) => shapeArtist(a, 0));

  logger.debug(
    { term, artistCount: artists.length, albumCount: albums.length },
    "libraryService.search: results",
  );
  return { artists, albums };
}

export async function getArtistImageStream(
  artistId: number,
): Promise<AxiosResponse<Readable>> {
  const artist = await lidarrClient.getArtist(artistId);
  const filename = getImageFilename(artist.images, "poster");
  return lidarrClient.getArtistCover(artistId, filename);
}

export async function getAlbumImageStream(
  albumId: number,
): Promise<AxiosResponse<Readable>> {
  const album = await lidarrClient.getAlbum(albumId);
  const filename = getImageFilename(album.images, "cover");
  return lidarrClient.getAlbumCover(albumId, filename);
}
