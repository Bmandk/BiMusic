import { createReadStream, statSync } from "fs";
import { access, constants } from "fs/promises";
import path from "path";
import { Request, Response } from "express";
import type { FfmpegCommand } from "fluent-ffmpeg";
import { env } from "../config/env.js";
import { getTrack, getTrackFile, getRootFolders } from "./lidarrClient.js";
import { createError } from "../middleware/errorHandler.js";
import { logger } from "../utils/logger.js";

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
      throw createError(
        500,
        "INTERNAL_ERROR",
        "No root folders configured in Lidarr",
      );
    }
    // Normalise: strip trailing slashes for reliable prefix matching.
    lidarrRootPath = roots[0].path.replace(/[\\/]+$/, "");
    logger.info(
      { lidarrRootPath, musicLibraryPath: env.MUSIC_LIBRARY_PATH },
      "Cached Lidarr root folder for path remapping",
    );
    return lidarrRootPath;
  })().catch((err) => {
    lidarrRootPromise = null;
    throw err;
  });

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
  const normFile = lidarrFilePath.replace(/\\/g, "/");
  const normRoot = lidarrRoot.replace(/\\/g, "/");

  if (normFile.startsWith(normRoot)) {
    const relative = normFile.slice(normRoot.length);
    return path.join(env.MUSIC_LIBRARY_PATH, relative);
  }
  // If already under MUSIC_LIBRARY_PATH, return as-is.
  return lidarrFilePath;
}

// Tracks all active ffmpeg command objects for graceful shutdown.
const activeTranscodeCommands = new Set<FfmpegCommand>();

/** Register an active ffmpeg command (called by hlsService and downloadService). */
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
    try {
      cmd.kill("SIGTERM");
    } catch {
      /* ignore */
    }
  }
  activeTranscodeCommands.clear();
}

/** Resolve the on-disk path and duration for a Lidarr track, verifying it is readable. */
export async function resolveFilePath(
  trackId: number,
): Promise<{ sourcePath: string; durationMs: number }> {
  const track = await getTrack(trackId);
  if (!track.hasFile || !track.trackFileId) {
    logger.warn(
      { trackId, hasFile: track.hasFile, trackFileId: track.trackFileId },
      "Track has no associated file",
    );
    throw createError(404, "NOT_FOUND", "Track has no associated file");
  }

  const trackFile = await getTrackFile(track.trackFileId);
  if (!trackFile.path) {
    logger.warn(
      { trackId, trackFileId: track.trackFileId },
      "Track file path is not set",
    );
    throw createError(404, "NOT_FOUND", "Track file path is not set");
  }

  const lidarrRoot = await getLidarrRootPath();
  const localPath = remapPath(trackFile.path, lidarrRoot);

  // Boundary check: ensure the resolved path stays within MUSIC_LIBRARY_PATH.
  // remapPath can produce an out-of-bounds path if Lidarr returns a crafted
  // file path containing ".." sequences.
  const libraryRoot = path.resolve(env.MUSIC_LIBRARY_PATH);
  const resolvedLocal = path.resolve(localPath);
  if (
    resolvedLocal !== libraryRoot &&
    !resolvedLocal.startsWith(libraryRoot + path.sep)
  ) {
    logger.warn(
      { trackId, lidarrPath: trackFile.path, resolvedLocal, libraryRoot },
      "Resolved path is outside music library — possible path traversal",
    );
    throw createError(
      403,
      "FORBIDDEN",
      "Track file is outside the music library",
    );
  }

  try {
    await access(localPath, constants.R_OK);
  } catch {
    logger.warn(
      { trackId, lidarrPath: trackFile.path, localPath },
      "Track file is not readable on disk",
    );
    throw createError(404, "NOT_FOUND", "Track file is not readable");
  }

  return { sourcePath: localPath, durationMs: track.duration };
}

/**
 * Returns true if the source file can be served as-is (MP3).
 * We always passthrough MP3 regardless of the requested bitrate — transcoding
 * lossy-to-lossy at a higher bitrate adds no quality benefit.
 */
export function isPassthrough(sourcePath: string): boolean {
  return path.extname(sourcePath).toLowerCase() === ".mp3";
}

/** Serve a file with Range support (206 Partial Content or 200 OK). */
export function serveFile(
  filePath: string,
  req: Request,
  res: Response,
  options?: { contentType?: string; fileSize?: number },
): void {
  const contentType = options?.contentType ?? "audio/mpeg";
  const fileSize = options?.fileSize ?? statSync(filePath).size;
  const rangeHeader = req.headers.range;

  res.setHeader("Accept-Ranges", "bytes");
  res.setHeader("Content-Type", contentType);

  if (rangeHeader) {
    const [unit, range] = rangeHeader.split("=");
    if (unit !== "bytes" || !range) {
      res.status(400).json({
        error: { code: "BAD_REQUEST", message: "Invalid Range header" },
      });
      return;
    }

    const [startStr, endStr] = range.split("-");
    const start = parseInt(startStr, 10);
    const end = endStr ? parseInt(endStr, 10) : fileSize - 1;

    if (isNaN(start) || isNaN(end) || start > end || start >= fileSize) {
      res.status(416).setHeader("Content-Range", `bytes */${fileSize}`).end();
      return;
    }
    // Clamp end per RFC 7233 §2.1: a valid start with an oversized end is
    // satisfiable — clamp to the last byte rather than returning 416.
    const clampedEnd = Math.min(end, fileSize - 1);

    const chunkSize = clampedEnd - start + 1;
    res.status(206);
    res.setHeader("Content-Range", `bytes ${start}-${clampedEnd}/${fileSize}`);
    res.setHeader("Content-Length", chunkSize);
    const rangeStream = createReadStream(filePath, { start, end: clampedEnd });
    rangeStream.on("error", (err: Error) => {
      logger.error({ err, filePath }, "File read error during range serve");
      if (!res.headersSent) res.status(500).end();
      else if (!res.destroyed) res.destroy();
    });
    rangeStream.pipe(res);
  } else {
    res.status(200);
    res.setHeader("Content-Length", fileSize);
    const fileStream = createReadStream(filePath);
    fileStream.on("error", (err: Error) => {
      logger.error({ err, filePath }, "File read error during serve");
      if (!res.headersSent) res.status(500).end();
      else if (!res.destroyed) res.destroy();
    });
    fileStream.pipe(res);
  }
}
