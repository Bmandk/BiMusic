import { createHash } from 'crypto';
import {
  createReadStream,
  mkdirSync,
  readdirSync,
  statSync,
  existsSync,
  unlinkSync,
} from 'fs';
import { access, constants } from 'fs/promises';
import path from 'path';
import { Request, Response } from 'express';
import ffmpeg, { FfmpegCommand } from 'fluent-ffmpeg';
import { env } from '../config/env.js';
import { getTrack, getTrackFile, getRootFolders } from './lidarrClient.js';
import { createError } from '../middleware/errorHandler.js';
import { logger } from '../utils/logger.js';

// Cached Lidarr root folder path (fetched once on first stream request).
let lidarrRootPath: string | null = null;
let lidarrRootPromise: Promise<string> | null = null;

/** Reset cached Lidarr root path (for tests). */
export function resetLidarrRootCache(): void {
  lidarrRootPath = null;
  lidarrRootPromise = null;
}

async function getLidarrRootPath(): Promise<string> {
  if (lidarrRootPath !== null) return lidarrRootPath;
  if (lidarrRootPromise !== null) return lidarrRootPromise;

  lidarrRootPromise = (async () => {
    const roots = await getRootFolders();
    if (roots.length === 0) {
      throw createError(500, 'INTERNAL_ERROR', 'No root folders configured in Lidarr');
    }
    // Normalise: strip trailing slashes for reliable prefix matching.
    lidarrRootPath = roots[0].path.replace(/[\\/]+$/, '');
    logger.info({ lidarrRootPath, musicLibraryPath: env.MUSIC_LIBRARY_PATH }, 'Cached Lidarr root folder for path remapping');
    return lidarrRootPath;
  })();

  return lidarrRootPromise;
}

/**
 * Remap a Lidarr absolute path to the local MUSIC_LIBRARY_PATH.
 * e.g. Lidarr returns "/music/Artist/Album/track.flac"
 *      MUSIC_LIBRARY_PATH = "/c/test-music"
 *      → "/c/test-music/Artist/Album/track.flac"
 */
function remapPath(lidarrFilePath: string, lidarrRoot: string): string {
  // Normalise separators to forward slashes for comparison.
  const normFile = lidarrFilePath.replace(/\\/g, '/');
  const normRoot = lidarrRoot.replace(/\\/g, '/');

  if (normFile.startsWith(normRoot)) {
    const relative = normFile.slice(normRoot.length);
    return path.join(env.MUSIC_LIBRARY_PATH, relative);
  }
  // If already under MUSIC_LIBRARY_PATH, return as-is.
  return lidarrFilePath;
}

// Tracks in-progress transcodes so concurrent requests wait on the same promise.
const inProgressTranscodes = new Map<string, Promise<void>>();

// Tracks all active ffmpeg command objects for graceful shutdown.
const activeTranscodeCommands = new Set<FfmpegCommand>();

/** Register an active ffmpeg command (called by streamService and downloadService). */
export function registerFfmpegCommand(cmd: FfmpegCommand): void {
  activeTranscodeCommands.add(cmd);
}

/** Unregister a completed/failed ffmpeg command. */
export function unregisterFfmpegCommand(cmd: FfmpegCommand): void {
  activeTranscodeCommands.delete(cmd);
}

/** Kill all active ffmpeg processes — call during graceful shutdown. */
export function killAllActiveTranscodes(): void {
  for (const cmd of activeTranscodeCommands) {
    try { cmd.kill('SIGTERM'); } catch { /* ignore */ }
  }
  activeTranscodeCommands.clear();
}

/** Create temp dir and clear any leftover files from a previous run. */
export function initTempDir(): void {
  mkdirSync(env.TEMP_DIR, { recursive: true });
  try {
    for (const file of readdirSync(env.TEMP_DIR)) {
      try {
        unlinkSync(path.join(env.TEMP_DIR, file));
      } catch {
        // ignore individual file errors
      }
    }
  } catch {
    // ignore if dir was just created
  }
}

/** Schedule hourly cleanup of temp files older than 24 hours. */
export function startTempFileCleanup(): void {
  const ONE_HOUR = 60 * 60 * 1000;
  const MAX_AGE = 24 * ONE_HOUR;

  setInterval(() => {
    try {
      const files = readdirSync(env.TEMP_DIR);
      const now = Date.now();
      for (const file of files) {
        const filePath = path.join(env.TEMP_DIR, file);
        try {
          const stat = statSync(filePath);
          if (now - stat.mtimeMs > MAX_AGE) {
            unlinkSync(filePath);
            logger.info({ filePath }, 'Cleaned up old temp file');
          }
        } catch {
          // ignore
        }
      }
    } catch (err) {
      logger.error({ err }, 'Temp file cleanup failed');
    }
  }, ONE_HOUR);
}

/** Resolve the on-disk path for a Lidarr track, verifying it is readable. */
export async function resolveFilePath(trackId: number): Promise<string> {
  const track = await getTrack(trackId);
  if (!track.hasFile || !track.trackFileId) {
    logger.warn({ trackId, hasFile: track.hasFile, trackFileId: track.trackFileId }, 'Track has no associated file');
    throw createError(404, 'NOT_FOUND', 'Track has no associated file');
  }

  const trackFile = await getTrackFile(track.trackFileId);
  if (!trackFile.path) {
    logger.warn({ trackId, trackFileId: track.trackFileId }, 'Track file path is not set');
    throw createError(404, 'NOT_FOUND', 'Track file path is not set');
  }

  const lidarrRoot = await getLidarrRootPath();
  const localPath = remapPath(trackFile.path, lidarrRoot);

  try {
    await access(localPath, constants.R_OK);
  } catch {
    logger.warn({ trackId, lidarrPath: trackFile.path, localPath }, 'Track file is not readable on disk');
    throw createError(404, 'NOT_FOUND', 'Track file is not readable');
  }

  return localPath;
}

/** Returns the deterministic temp file path for a given source + bitrate. */
export function getTempFilePath(sourcePath: string, bitrate: number): string {
  const hash = createHash('sha256').update(`${sourcePath}:${bitrate}`).digest('hex');
  return path.join(env.TEMP_DIR, `${hash}.mp3`);
}

/**
 * Returns true if the source file can be served as-is (MP3).
 * We always passthrough MP3 regardless of the requested bitrate — transcoding
 * lossy-to-lossy at a higher bitrate adds no quality benefit.
 */
export function isPassthrough(sourcePath: string): boolean {
  return path.extname(sourcePath).toLowerCase() === '.mp3';
}

/**
 * Ensure a transcoded temp file exists for the given source + bitrate.
 * Concurrent callers for the same key share the same ffmpeg promise.
 */
export async function ensureTranscoded(sourcePath: string, bitrate: number): Promise<string> {
  const tempPath = getTempFilePath(sourcePath, bitrate);

  if (existsSync(tempPath)) {
    return tempPath;
  }

  const existing = inProgressTranscodes.get(tempPath);
  if (existing) {
    await existing;
    return tempPath;
  }

  const transcodePromise = new Promise<void>((resolve, reject) => {
    const cmd = ffmpeg(sourcePath)
      .noVideo()
      .audioCodec('libmp3lame')
      .audioBitrate(bitrate)
      .output(tempPath)
      .on('end', () => {
        unregisterFfmpegCommand(cmd);
        inProgressTranscodes.delete(tempPath);
        resolve();
      })
      .on('error', (err: Error) => {
        unregisterFfmpegCommand(cmd);
        inProgressTranscodes.delete(tempPath);
        try { unlinkSync(tempPath); } catch { /* ignore partial file */ }
        reject(err);
      });

    registerFfmpegCommand(cmd);
    cmd.run();
  });

  inProgressTranscodes.set(tempPath, transcodePromise);

  try {
    await transcodePromise;
  } catch (err) {
    logger.error({ err, sourcePath, bitrate }, 'Transcoding failed');
    throw createError(500, 'TRANSCODE_ERROR', 'Audio transcoding failed');
  }

  return tempPath;
}

/** Serve a file with Range support (206 Partial Content or 200 OK). */
export function serveFile(filePath: string, req: Request, res: Response): void {
  const stat = statSync(filePath);
  const fileSize = stat.size;
  const rangeHeader = req.headers.range;

  res.setHeader('Accept-Ranges', 'bytes');
  res.setHeader('Content-Type', 'audio/mpeg');

  if (rangeHeader) {
    const [unit, range] = rangeHeader.split('=');
    if (unit !== 'bytes' || !range) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid Range header' } });
      return;
    }

    const [startStr, endStr] = range.split('-');
    const start = parseInt(startStr, 10);
    const end = endStr ? parseInt(endStr, 10) : fileSize - 1;

    if (isNaN(start) || isNaN(end) || start > end || end >= fileSize) {
      res.status(416).setHeader('Content-Range', `bytes */${fileSize}`).end();
      return;
    }

    const chunkSize = end - start + 1;
    res.status(206);
    res.setHeader('Content-Range', `bytes ${start}-${end}/${fileSize}`);
    res.setHeader('Content-Length', chunkSize);
    createReadStream(filePath, { start, end }).pipe(res);
  } else {
    res.status(200);
    res.setHeader('Content-Length', fileSize);
    createReadStream(filePath).pipe(res);
  }
}
