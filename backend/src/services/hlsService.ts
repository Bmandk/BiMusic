import { createHash } from "crypto";
import {
  mkdirSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
  existsSync,
  rmdirSync,
} from "fs";
import path from "path";
import ffmpeg from "fluent-ffmpeg";
import { env } from "../config/env.js";
import { logger } from "../utils/logger.js";
import {
  registerFfmpegCommand,
  unregisterFfmpegCommand,
} from "./trackFileResolver.js";

// In-flight dedup map: segmentKey → Promise<segmentPath>
const inFlightSegments = new Map<string, Promise<string>>();

/**
 * Stable cache key for a (source file, bitrate) pair.
 * Includes mtime + size so the key changes when the source file is replaced
 * at the same path (e.g. Lidarr re-downloads at higher quality).
 */
export function computeTrackKey(
  sourcePath: string,
  sourceMtimeMs: number,
  sourceSize: number,
  bitrate: number,
): string {
  return createHash("sha256")
    .update(`${sourcePath}:${sourceMtimeMs}:${sourceSize}:${bitrate}`)
    .digest("hex");
}

/**
 * Build a HLS VOD playlist for the given track.
 * Rebuilt on every request — never cached — because the token is embedded in
 * every segment URI and must not be shared across users.
 */
export function buildPlaylist(
  durationMs: number,
  segmentCount: number,
  segmentSeconds: number,
  bitrate: number,
  token: string,
): string {
  const durationSec = durationMs / 1000;
  const lines: string[] = [
    "#EXTM3U",
    "#EXT-X-VERSION:3",
    `#EXT-X-TARGETDURATION:${segmentSeconds}`,
    "#EXT-X-MEDIA-SEQUENCE:0",
    "#EXT-X-PLAYLIST-TYPE:VOD",
  ];
  for (let i = 0; i < segmentCount; i++) {
    const isLast = i === segmentCount - 1;
    const segDuration = isLast
      ? (durationSec - i * segmentSeconds).toFixed(3)
      : segmentSeconds.toFixed(3);
    const idx = String(i).padStart(3, "0");
    lines.push(`#EXTINF:${segDuration},`);
    lines.push(`segment/${idx}?bitrate=${bitrate}&token=${token}`);
  }
  lines.push("#EXT-X-ENDLIST");
  return lines.join("\n") + "\n";
}

/** Absolute path to the cached .ts file for a given track key + segment index. */
export function getSegmentCachePath(
  trackKey: string,
  segmentIndex: number,
): string {
  const idx = String(segmentIndex).padStart(3, "0");
  return path.join(env.HLS_CACHE_DIR, trackKey, `segment${idx}.ts`);
}

/**
 * Transcode exactly one 6-second HLS segment using ffmpeg.
 * Writes to a .part file then atomically renames to the final path.
 * Registers the ffmpeg command for graceful shutdown.
 */
export async function generateSegment(opts: {
  sourcePath: string;
  trackKey: string;
  segmentIndex: number;
  bitrate: number;
  segmentSeconds: number;
}): Promise<string> {
  const { sourcePath, trackKey, segmentIndex, bitrate, segmentSeconds } = opts;
  const segPath = getSegmentCachePath(trackKey, segmentIndex);
  const partPath = `${segPath}.part`;
  const cacheDir = path.dirname(segPath);
  mkdirSync(cacheDir, { recursive: true });

  const segmentStart = segmentIndex * segmentSeconds;

  return new Promise<string>((resolve, reject) => {
    const cmd = ffmpeg()
      .input(sourcePath)
      .seekInput(segmentStart)
      .noVideo()
      .audioCodec("libmp3lame")
      .audioBitrate(bitrate)
      .duration(segmentSeconds)
      .outputOptions([
        `-output_ts_offset ${segmentStart}`,
        "-muxdelay 0",
        "-muxpreload 0",
      ])
      .format("mpegts")
      .output(partPath)
      .on("end", () => {
        unregisterFfmpegCommand(cmd);
        try {
          renameSync(partPath, segPath);
          resolve(segPath);
        } catch (err) {
          reject(err);
        }
      })
      .on("error", (err: Error) => {
        unregisterFfmpegCommand(cmd);
        try {
          unlinkSync(partPath);
        } catch {
          /* ignore */
        }
        reject(err);
      });

    registerFfmpegCommand(cmd);
    cmd.run();
  });
}

/**
 * Return the absolute path to a ready segment, generating it on demand.
 * Concurrent callers for the same segment share one ffmpeg invocation.
 */
export async function ensureSegment(opts: {
  sourcePath: string;
  trackKey: string;
  segmentIndex: number;
  bitrate: number;
  segmentSeconds: number;
}): Promise<string> {
  const { trackKey, segmentIndex } = opts;
  const segPath = getSegmentCachePath(trackKey, segmentIndex);

  if (existsSync(segPath)) return segPath;

  const key = `${trackKey}/segment${segmentIndex}`;
  const inflight = inFlightSegments.get(key);
  if (inflight) return inflight;

  const promise = generateSegment(opts).finally(() =>
    inFlightSegments.delete(key),
  );
  inFlightSegments.set(key, promise);
  return promise;
}

/** Create cache dir and remove any stale .part files from previous runs. */
export function initHlsCacheDir(): void {
  mkdirSync(env.HLS_CACHE_DIR, { recursive: true });
  try {
    for (const entry of readdirSync(env.HLS_CACHE_DIR)) {
      const dir = path.join(env.HLS_CACHE_DIR, entry);
      try {
        for (const file of readdirSync(dir)) {
          if (file.endsWith(".part")) {
            try {
              unlinkSync(path.join(dir, file));
            } catch {
              /* ignore */
            }
          }
        }
      } catch {
        /* ignore */
      }
    }
  } catch {
    /* ignore */
  }
}

/** Hourly prune of cache subdirectories not written to in the last 24 hours. */
export function startHlsCacheCleanup(): void {
  const ONE_HOUR = 60 * 60 * 1000;
  const MAX_AGE = 24 * ONE_HOUR;

  setInterval(() => {
    try {
      const now = Date.now();
      for (const entry of readdirSync(env.HLS_CACHE_DIR)) {
        const dir = path.join(env.HLS_CACHE_DIR, entry);
        try {
          const stat = statSync(dir);
          if (!stat.isDirectory()) continue;
          if (now - stat.mtimeMs > MAX_AGE) {
            for (const file of readdirSync(dir)) {
              try {
                unlinkSync(path.join(dir, file));
              } catch {
                /* ignore */
              }
            }
            try {
              rmdirSync(dir);
            } catch {
              /* ignore */
            }
            logger.info({ dir }, "Cleaned up stale HLS cache directory");
          }
        } catch {
          /* ignore */
        }
      }
    } catch (err) {
      logger.error({ err }, "HLS cache cleanup failed");
    }
  }, ONE_HOUR);
}
