import { createHash } from "crypto";
import { mkdirSync, readdirSync, renameSync, unlinkSync, existsSync } from "fs";
import { readdir, stat as statAsync, unlink, rmdir } from "fs/promises";
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

// Concurrency cap: at most 4 parallel ffmpeg transcodes.
// Callers beyond the cap queue and are served as slots free up.
const MAX_CONCURRENT_TRANSCODES = 4;
let activeTranscodes = 0;
const transcodeWaitQueue: Array<() => void> = [];

function acquireTranscodeSlot(): Promise<void> {
  if (activeTranscodes < MAX_CONCURRENT_TRANSCODES) {
    activeTranscodes++;
    return Promise.resolve();
  }
  return new Promise<void>((resolve) => transcodeWaitQueue.push(resolve));
}

function releaseTranscodeSlot(): void {
  const next = transcodeWaitQueue.shift();
  if (next) {
    next(); // transfer slot directly to next waiter
  } else {
    activeTranscodes--;
  }
}

// Maximum seconds before an ffmpeg transcode is killed and the caller gets an error.
const SEGMENT_TRANSCODE_TIMEOUT_MS = 60_000;

// Maximum cached track-key directories before LRU eviction during cleanup.
const MAX_CACHE_DIRS = 500;

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
 *
 * `startSegment` skips the first N segments from the output. Used by the
 * Windows client to implement cross-segment seeking: mpv's native playlist
 * demuxer flattens HLS into per-segment playlist entries and can only seek
 * within the currently-loaded segment, so the client asks for a new playlist
 * starting at the desired segment and seeks within that. Segment URIs still
 * carry their original track-relative index (`segment/020`, not `segment/000`)
 * so the client's URL-based offset tracking keeps working.
 */
export function buildPlaylist(
  durationMs: number,
  segmentCount: number,
  segmentSeconds: number,
  bitrate: number,
  token: string,
  startSegment: number = 0,
): string {
  const durationSec = durationMs / 1000;
  const lines: string[] = [
    "#EXTM3U",
    "#EXT-X-VERSION:3",
    `#EXT-X-TARGETDURATION:${Math.ceil(segmentSeconds)}`,
    `#EXT-X-MEDIA-SEQUENCE:${startSegment}`,
    "#EXT-X-PLAYLIST-TYPE:VOD",
  ];
  for (let i = startSegment; i < segmentCount; i++) {
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

/** Absolute path to the cached .mp3 file for a given track key + segment index. */
export function getSegmentCachePath(
  trackKey: string,
  segmentIndex: number,
): string {
  const idx = String(segmentIndex).padStart(3, "0");
  return path.join(env.HLS_CACHE_DIR, trackKey, `segment${idx}.mp3`);
}

/**
 * Transcode exactly one HLS segment using ffmpeg.
 *
 * Segments are plain MP3 (not MPEG-TS): each segment is a self-contained MP3
 * frame sequence with no container. This is the simplest HLS audio variant —
 * required because mpv on Windows treats HLS as a flat playlist and plays each
 * segment as an independent media item. An MPEG-TS wrapper made format probe
 * fail (lavf's TS probe returns 0, MP3 inside scored only 1) while a bare MP3
 * segment is immediately recognized by lavf's mp3 demuxer.
 *
 * Writes to a .part file then atomically renames to the final path.
 * Registers the ffmpeg command for graceful shutdown.
 * Acquires a concurrency slot and times out after SEGMENT_TRANSCODE_TIMEOUT_MS.
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

  await acquireTranscodeSlot();

  return new Promise<string>((resolve, reject) => {
    const cmd = ffmpeg()
      .input(sourcePath)
      .seekInput(segmentStart)
      .noVideo()
      .audioCodec("libmp3lame")
      .audioBitrate(bitrate)
      .duration(segmentSeconds)
      .format("mp3")
      .output(partPath);

    let done = false;

    const timeout = setTimeout(() => {
      if (done) return;
      done = true;
      try {
        cmd.kill("SIGTERM");
      } catch {
        /* ignore */
      }
      unregisterFfmpegCommand(cmd);
      releaseTranscodeSlot();
      try {
        unlinkSync(partPath);
      } catch {
        /* ignore */
      }
      reject(
        new Error(
          `ffmpeg segment transcode timed out after ${SEGMENT_TRANSCODE_TIMEOUT_MS}ms`,
        ),
      );
    }, SEGMENT_TRANSCODE_TIMEOUT_MS);

    cmd
      .on("end", () => {
        if (done) return;
        done = true;
        clearTimeout(timeout);
        unregisterFfmpegCommand(cmd);
        releaseTranscodeSlot();
        try {
          renameSync(partPath, segPath);
          resolve(segPath);
        } catch (err) {
          reject(err);
        }
      })
      .on("error", (err: Error) => {
        if (done) return;
        done = true;
        clearTimeout(timeout);
        unregisterFfmpegCommand(cmd);
        releaseTranscodeSlot();
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

/** Hourly prune: removes dirs older than 24 h and caps total dirs at MAX_CACHE_DIRS. */
export function startHlsCacheCleanup(): void {
  const ONE_HOUR = 60 * 60 * 1000;
  const MAX_AGE = 24 * ONE_HOUR;

  const runCleanup = async () => {
    try {
      const now = Date.now();
      const entries = await readdir(env.HLS_CACHE_DIR);

      type DirEntry = { dir: string; mtimeMs: number };
      const dirs: DirEntry[] = [];

      for (const entry of entries) {
        const dir = path.join(env.HLS_CACHE_DIR, entry);
        try {
          const s = await statAsync(dir);
          if (!s.isDirectory()) continue;

          const hasInflight = [...inFlightSegments.keys()].some((k) =>
            k.startsWith(entry),
          );

          if (now - s.mtimeMs > MAX_AGE) {
            // Skip dirs with active in-flight segments — they'll be cleaned next run.
            if (hasInflight) continue;
            const files = await readdir(dir);
            await Promise.allSettled(
              files.map((f) => unlink(path.join(dir, f))),
            );
            try {
              await rmdir(dir);
              logger.info({ dir }, "Cleaned up stale HLS cache directory");
            } catch {
              /* non-empty dir — leave for next run */
            }
          } else if (!hasInflight) {
            dirs.push({ dir, mtimeMs: s.mtimeMs });
          }
        } catch {
          /* ignore per-entry errors */
        }
      }

      // LRU eviction: if remaining dirs exceed MAX_CACHE_DIRS, remove the oldest.
      if (dirs.length > MAX_CACHE_DIRS) {
        dirs.sort((a, b) => a.mtimeMs - b.mtimeMs);
        const toEvict = dirs.slice(0, dirs.length - MAX_CACHE_DIRS);
        await Promise.allSettled(
          toEvict.map(async ({ dir }) => {
            try {
              const files = await readdir(dir);
              await Promise.allSettled(
                files.map((f) => unlink(path.join(dir, f))),
              );
              await rmdir(dir);
              logger.info({ dir }, "Evicted HLS cache directory (LRU cap)");
            } catch {
              /* ignore */
            }
          }),
        );
      }
    } catch (err) {
      logger.error({ err }, "HLS cache cleanup failed");
    }
  };

  setInterval(() => void runCleanup(), ONE_HOUR);
}
