import axios, { AxiosInstance, AxiosResponse } from 'axios';
import type { Readable } from 'stream';
import { env } from '../config/env.js';
import { createError } from '../middleware/errorHandler.js';
import type {
  LidarrArtist,
  LidarrAlbum,
  LidarrTrack,
  LidarrTrackFile,
  LidarrSearchResult,
  LidarrQueue,
  LidarrCommand,
} from '../types/lidarr.js';

export const lidarrApi: AxiosInstance = axios.create({
  baseURL: `${env.LIDARR_URL}/api/v1`,
  headers: { 'X-Api-Key': env.LIDARR_API_KEY },
  timeout: 30000,
});

function mapError(err: unknown): never {
  if (axios.isAxiosError(err)) {
    if (err.code === 'ECONNABORTED' || err.code === 'ETIMEDOUT') {
      throw createError(504, 'LIDARR_TIMEOUT', 'Lidarr request timed out');
    }
    if (err.response) {
      const status = err.response.status;
      if (status === 404) {
        throw createError(404, 'NOT_FOUND', 'Resource not found in Lidarr');
      }
      if (status >= 500) {
        throw createError(502, 'LIDARR_ERROR', 'Lidarr returned an error');
      }
    }
  }
  throw err;
}

export async function getArtists(): Promise<LidarrArtist[]> {
  try {
    const res = await lidarrApi.get<LidarrArtist[]>('/artist');
    return Array.isArray(res.data) ? res.data : [];
  } catch (err) {
    return mapError(err);
  }
}

export async function getArtist(id: number): Promise<LidarrArtist> {
  try {
    const res = await lidarrApi.get<LidarrArtist>(`/artist/${id}`);
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function lookupArtist(term: string): Promise<LidarrArtist[]> {
  try {
    const res = await lidarrApi.get<LidarrArtist[]>('/artist/lookup', { params: { term } });
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function addArtist(payload: Record<string, unknown>): Promise<LidarrArtist> {
  try {
    const res = await lidarrApi.post<LidarrArtist>('/artist', payload);
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function getAlbums(artistId?: number): Promise<LidarrAlbum[]> {
  try {
    const params = artistId !== undefined ? { artistId } : {};
    const res = await lidarrApi.get<LidarrAlbum[]>('/album', { params });
    return Array.isArray(res.data) ? res.data : [];
  } catch (err) {
    return mapError(err);
  }
}

export async function getAlbum(id: number): Promise<LidarrAlbum> {
  try {
    const res = await lidarrApi.get<LidarrAlbum>(`/album/${id}`);
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function lookupAlbum(term: string): Promise<LidarrAlbum[]> {
  try {
    const res = await lidarrApi.get<LidarrAlbum[]>('/album/lookup', { params: { term } });
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function monitorAlbum(ids: number[], monitored: boolean): Promise<void> {
  try {
    await lidarrApi.put('/album/monitor', { albumIds: ids, monitored });
  } catch (err) {
    mapError(err);
  }
}

export async function getTracks(albumId?: number): Promise<LidarrTrack[]> {
  try {
    const params = albumId !== undefined ? { albumId } : {};
    const res = await lidarrApi.get<LidarrTrack[]>('/track', { params });
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function getTrack(id: number): Promise<LidarrTrack> {
  try {
    const res = await lidarrApi.get<LidarrTrack>(`/track/${id}`);
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function getTrackFile(id: number): Promise<LidarrTrackFile> {
  try {
    const res = await lidarrApi.get<LidarrTrackFile>(`/trackfile/${id}`);
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function getTrackFiles(albumId: number): Promise<LidarrTrackFile[]> {
  try {
    const res = await lidarrApi.get<LidarrTrackFile[]>('/trackfile', { params: { albumId } });
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function search(term: string): Promise<LidarrSearchResult[]> {
  try {
    const res = await lidarrApi.get<LidarrSearchResult[]>('/search', { params: { term } });
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function getArtistCover(
  artistId: number,
  filename: string,
): Promise<AxiosResponse<Readable>> {
  try {
    const res = await lidarrApi.get<Readable>(
      `/mediacover/artist/${artistId}/${filename}`,
      { responseType: 'stream' },
    );
    return res;
  } catch (err) {
    return mapError(err);
  }
}

export async function getAlbumCover(
  albumId: number,
  filename: string,
): Promise<AxiosResponse<Readable>> {
  try {
    const res = await lidarrApi.get<Readable>(
      `/mediacover/album/${albumId}/${filename}`,
      { responseType: 'stream' },
    );
    return res;
  } catch (err) {
    return mapError(err);
  }
}

export async function runCommand(
  name: string,
  body?: Record<string, unknown>,
): Promise<LidarrCommand> {
  try {
    const res = await lidarrApi.post<LidarrCommand>('/command', { name, ...body });
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}

export async function getQueue(): Promise<LidarrQueue[]> {
  try {
    const res = await lidarrApi.get<LidarrQueue[]>('/queue');
    return res.data;
  } catch (err) {
    return mapError(err);
  }
}
