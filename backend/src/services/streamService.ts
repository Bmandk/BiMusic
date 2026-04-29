import { createHash } from "crypto";
import {
  createReadStream,
  createWriteStream,
  mkdirSync,
  readdirSync,
  renameSync,
  statSync,
  existsSync,
  unlinkSync,
} from "fs";
import { access, constants } from "fs/promises";
import { PassThrough } from "stream";
import path from "path";
import { Request, Response } from "express";
import ffmpeg, { FfmpegCommand } from "fluent-ffmpeg";
import { env } from "../config/env.js";
import { getTrack, getTrackFile, getRootFolders } from "./lidarrClient.js";
import { createError } from "../middleware/errorHandler.js";
import { logger } from "../utils/logger.js";

// Cached Lidarr root folder paths (fetched once on first stream request).
let lidarrRootPaths: string[] | null = null;
let lidarrRootPromise: Promise<string[]> | null = null;

/** Reset cached Lidarr root paths (for tests). */
export function resetLidarrRootCache(): void {
  lidarrRootPaths = null;
  lidarrRootPromise = null;
}

async function getLidarrRootPaths(): Promise<string[]> {
  if (lidarrRootPaths !== null) return lidarrRootPaths;
  if (lidarrRootPromise !== null) return lidarrRootPromise;

  lidarrRootPromise = (async () => {
    try {
      const roots = await getRootFolders();
      if (roots.length === 0) {
        throw createError(
          500,
          "INTERNAL_ERROR",
          "No root folders configured in Lidarr",
        );
      }
      // Normalise: strip trailing slashes for reliable prefix matching.
      lidarrRootPaths = roots.map((r) => r.path.replace(/[\\/]+$/, ""));
      logger.info(
        { lidarrRootPaths, musicLibraryPath: env.MUSIC_LIBRARY_PATH },
        "Cached Lidarr root folders for path remapping",
      );
      return lidarrRootPaths;
    } catch (err) {
      lidarrRootPromise = null;
      throw err;
    }
  })();

  return lidarrRootPromise;
}

/**
 * Remap a Lidarr absolute path to the local MUSIC_LIBRARY_PATH.
 * Uses the longest matching root for multi-root Lidarr setups.
 * e.g. Lidarr returns "/music/Artist/Album/track.flac"
 *      MUSIC_LIBRARY_PATH = "/c/test-music"
 *      → "/c/test-music/Artist/Album/track.flac"
 */
function remapPath(lidarrFilePath: string, lidarrRoots: string[]): string {
  const normFile = lidarrFilePath.replace(/\\/g, "/");
  // Pick the longest matching root to handle nested/overlapping root paths.
  const matchingRoot = lidarrRoots
    .map((r) => r.replace(/\\/g, "/"))
    .filter((r) => normFile === r || normFile.startsWith(r + "/"))
    .sort((a, b) => b.length - a.length)[0];

  if (matchingRoot) {
    const relative = normFile.slice(matchingRoot.length);
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
    try {
      cmd.kill("SIGTERM");
    } catch {
      /* ignore */
    }
  }
  activeTranscodeCommands.clear();
}

/** Create temp dir and clear any leftover files from a previous run. */
export function initTempDir(): void {
  mkdirSync(env.TEMP_DIR, { recursive: true });
  let cleaned = 0;
  try {
    for (const file of readdirSync(env.TEMP_DIR)) {
      try {
        unlinkSync(path.join(env.TEMP_DIR, file));
        cleaned++;
      } catch {
        // ignore individual file errors
      }
    }
    if (cleaned > 0) {
      logger.info(
        { count: cleaned },
        "Cleaned up leftover temp files on startup",
      );
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
            logger.info({ filePath }, "Cleaned up old temp file");
          }
        } catch {
          // ignore
        }
      }
    } catch (err) {
      logger.error({ err }, "Temp file cleanup failed");
    }
  }, ONE_HOUR);
}

/** Resolve the on-disk path for a Lidarr track, verifying it is readable. */
export async function resolveFilePath(trackId: number): Promise<string> {
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

  const lidarrRoots = await getLidarrRootPaths();
  const localPath = remapPath(trackFile.path, lidarrRoots);

  try {
    await access(localPath, constants.R_OK);
  } catch {
    logger.warn(
      { trackId, lidarrPath: trackFile.path, localPath },
      "Track file is not readable on disk",
    );
    throw createError(404, "NOT_FOUND", "Track file is not readable");
  }

  return localPath;
}

/** Returns the deterministic temp file path for a given source + bitrate. */
export function getTempFilePath(sourcePath: string, bitrate: number): string {
  const hash = createHash("sha256")
    .update(`${sourcePath}:${bitrate}`)
    .digest("hex");
  return path.join(env.TEMP_DIR, `${hash}.mp3`);
}

/**
 * Returns true if the source file can be served as-is (MP3).
 * We always passthrough MP3 regardless of the requested bitrate — transcoding
 * lossy-to-lossy at a higher bitrate adds no quality benefit.
 */
export function isPassthrough(sourcePath: string): boolean {
  return path.extname(sourcePath).toLowerCase() === ".mp3";
}

/**
 * Ensure a transcoded temp file exists for the given source + bitrate.
 * Concurrent callers for the same key share the same ffmpeg promise.
 */
export async function ensureTranscoded(
  sourcePath: string,
  bitrate: number,
): Promise<string> {
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
      .audioCodec("libmp3lame")
      .audioBitrate(bitrate)
      .output(tempPath)
      .on("end", () => {
        unregisterFfmpegCommand(cmd);
        inProgressTranscodes.delete(tempPath);
        resolve();
      })
      .on("error", (err: Error) => {
        unregisterFfmpegCommand(cmd);
        inProgressTranscodes.delete(tempPath);
        try {
          unlinkSync(tempPath);
        } catch {
          /* ignore partial file */
        }
        reject(err);
      });

    registerFfmpegCommand(cmd);
    cmd.run();
  });

  inProgressTranscodes.set(tempPath, transcodePromise);

  try {
    await transcodePromise;
  } catch (err) {
    logger.error({ err, sourcePath, bitrate }, "Transcoding failed");
    throw createError(500, "TRANSCODE_ERROR", "Audio transcoding failed");
  }

  return tempPath;
}

/**
 * Stream a transcoded track to the response, tee-ing to disk for caching.
 *
 * First request with no Range header: pipes ffmpeg stdout directly to the
 * response while simultaneously writing to a temp file. Bytes flow to the
 * client immediately instead of waiting for the full transcode.
 *
 * Subsequent requests (cached file exists): served with full Range / 206
 * support via serveFile.
 *
 * Range requests that are not an open bytes=0- probe: fall back to the
 * blocking ensureTranscoded path so seek 206 semantics are preserved.
 */
export async function streamTranscoded(
  sourcePath: string,
  bitrate: number,
  req: Request,
  res: Response,
): Promise<void> {
  const tempPath = getTempFilePath(sourcePath, bitrate);

  // Cached: serve with full Range support.
  if (existsSync(tempPath)) {
    serveFile(tempPath, req, res);
    return;
  }

  // Non-trivial range (seek) with no cached file: wait for full transcode.
  const rangeHeader = req.headers.range;
  if (rangeHeader && rangeHeader.trim() !== "bytes=0-") {
    const filePath = await ensureTranscoded(sourcePath, bitrate);
    serveFile(filePath, req, res);
    return;
  }

  // Another request is already transcoding: wait for the file to be ready.
  const existing = inProgressTranscodes.get(tempPath);
  if (existing) {
    try {
      await existing;
    } catch {
      // The in-flight transcode failed; fall through to a fresh ensureTranscoded.
      const filePath = await ensureTranscoded(sourcePath, bitrate);
      serveFile(filePath, req, res);
      return;
    }
    serveFile(tempPath, req, res);
    return;
  }

  // First request: tee ffmpeg stdout → HTTP response + part file.
  const partPath = `${tempPath}.part`;

  const partStream = createWriteStream(partPath);

  let headersFlushed = false;
  const flushStreamingHeaders = () => {
    if (headersFlushed) return;
    headersFlushed = true;
    res.status(200);
    res.setHeader("Content-Type", "audio/mpeg");
    res.setHeader("Accept-Ranges", "none");
    res.flushHeaders();
  };

  let externalResolve!: () => void;
  let externalReject!: (err: Error) => void;
  const streamDonePromise = new Promise<void>((resolve, reject) => {
    externalResolve = resolve;
    externalReject = reject;
  });

  inProgressTranscodes.set(tempPath, streamDonePromise);

  let ffmpegEnded = false;
  let partFinished = false;
  let settled = false;

  const settle = (err?: Error) => {
    if (settled) return;
    settled = true;
    inProgressTranscodes.delete(tempPath);
    if (err) {
      if (!ffmpegEnded) {
        try {
          cmd.kill("SIGKILL");
        } catch {
          /* ignore */
        }
      }
      try {
        unlinkSync(partPath);
      } catch {
        /* ignore */
      }
      if (!headersFlushed && !res.headersSent) {
        res.status(500).json({
          error: {
            code: "TRANSCODE_ERROR",
            message: "Audio transcoding failed",
          },
        });
      } else if (!res.destroyed) {
        res.destroy();
      }
      partStream.destroy();
      externalReject(err);
    } else {
      try {
        renameSync(partPath, tempPath);
        externalResolve();
      } catch (renameErr) {
        logger.warn(
          { renameErr, partPath, tempPath },
          "Failed to rename part file",
        );
        externalReject(
          renameErr instanceof Error ? renameErr : new Error(String(renameErr)),
        );
      }
    }
  };

  const tryFinalize = () => {
    if (ffmpegEnded && partFinished) settle();
  };

  const cmd = ffmpeg(sourcePath)
    .noVideo()
    .audioCodec("libmp3lame")
    .audioBitrate(bitrate)
    .format("mp3")
    .on("end", () => {
      unregisterFfmpegCommand(cmd);
      ffmpegEnded = true;
      tryFinalize();
    })
    .on("error", (err: Error) => {
      unregisterFfmpegCommand(cmd);
      logger.error({ err, sourcePath, bitrate }, "Streaming transcode failed");
      settle(err);
    });

  registerFfmpegCommand(cmd);

  const ffmpegOut = cmd.pipe() as PassThrough;

  ffmpegOut.on("error", (err: Error) => {
    settle(err);
  });

  let pendingDrains = 0;
  const waitForDrain = (stream: NodeJS.WritableStream) => {
    pendingDrains += 1;
    ffmpegOut.pause();
    stream.once("drain", () => {
      pendingDrains -= 1;
      if (pendingDrains === 0) ffmpegOut.resume();
    });
  };

  ffmpegOut.on("data", (chunk: Buffer) => {
    flushStreamingHeaders();
    if (!partStream.destroyed) {
      const partOk = partStream.write(chunk);
      if (!partOk) waitForDrain(partStream);
    }
    if (!res.destroyed && !res.writableEnded) {
      const ok = res.write(chunk);
      if (!ok) waitForDrain(res);
    }
  });

  ffmpegOut.on("end", () => {
    if (!res.destroyed && !res.writableEnded) res.end();
    if (!partStream.destroyed) partStream.end();
  });

  partStream.on("finish", () => {
    partFinished = true;
    tryFinalize();
  });

  partStream.on("error", (err: Error) => {
    logger.error(
      { err, partPath },
      "Part file write error during stream transcode",
    );
    settle(err);
  });

  res.on("close", () => {
    if (!ffmpegEnded && !res.writableEnded) {
      try {
        cmd.kill("SIGKILL");
      } catch {
        /* ignore */
      }
      settle(new Error("Client disconnected"));
    }
  });

  return streamDonePromise;
}

/** Serve a file with Range support (206 Partial Content or 200 OK). */
export function serveFile(filePath: string, req: Request, res: Response): void {
  const stat = statSync(filePath);
  const fileSize = stat.size;
  const rangeHeader = req.headers.range;

  res.setHeader("Accept-Ranges", "bytes");
  res.setHeader("Content-Type", "audio/mpeg");

  if (rangeHeader) {
    const [unit, range] = rangeHeader.split("=");
    if (unit !== "bytes" || !range) {
      res.status(400).json({
        error: { code: "BAD_REQUEST", message: "Invalid Range header" },
      });
      return;
    }

    // Reject multi-range requests (not worth implementing; clients should use single ranges).
    if (range.includes(",")) {
      res.status(416).setHeader("Content-Range", `bytes */${fileSize}`).end();
      return;
    }

    const [startStr, endStr] = range.split("-");
    let start: number;
    let end: number;

    if (startStr === "") {
      // Suffix range: bytes=-N (last N bytes).
      const suffixLength = parseInt(endStr, 10);
      if (isNaN(suffixLength) || suffixLength <= 0) {
        res.status(416).setHeader("Content-Range", `bytes */${fileSize}`).end();
        return;
      }
      start = Math.max(0, fileSize - suffixLength);
      end = fileSize - 1;
    } else {
      start = parseInt(startStr, 10);
      end = endStr ? parseInt(endStr, 10) : fileSize - 1;

      if (isNaN(start) || isNaN(end) || start >= fileSize || start > end) {
        res.status(416).setHeader("Content-Range", `bytes */${fileSize}`).end();
        return;
      }

      end = Math.min(end, fileSize - 1);
    }

    const chunkSize = end - start + 1;
    res.status(206);
    res.setHeader("Content-Range", `bytes ${start}-${end}/${fileSize}`);
    res.setHeader("Content-Length", chunkSize);
    const rangeStream = createReadStream(filePath, { start, end });
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
