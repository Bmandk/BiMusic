import { randomUUID } from "crypto";
import { mkdirSync, statSync, unlinkSync } from "fs";
import { copyFile } from "fs/promises";
import path from "path";
import { eq, and, asc } from "drizzle-orm";
import ffmpeg from "fluent-ffmpeg";
import { db } from "../db/connection.js";
import { offlineTracks } from "../db/schema.js";
import { createError } from "../middleware/errorHandler.js";
import {
  resolveFilePath,
  isPassthrough,
  registerFfmpegCommand,
  unregisterFfmpegCommand,
} from "./trackFileResolver.js";
import { env } from "../config/env.js";
import { logger } from "../utils/logger.js";

export interface DownloadRecord {
  id: string;
  lidarrTrackId: number;
  deviceId: string;
  bitrate: number;
  filePath: string | null;
  fileSize: number | null;
  status: string;
  requestedAt: string;
  completedAt: string | null;
}

function getOfflineFilePath(
  userId: string,
  trackId: number,
  bitrate: number,
): string {
  return path.join(
    env.OFFLINE_STORAGE_PATH,
    userId,
    `${trackId}-${bitrate}.mp3`,
  );
}

function rowToRecord(row: typeof offlineTracks.$inferSelect): DownloadRecord {
  return {
    id: row.id,
    lidarrTrackId: row.lidarrTrackId,
    deviceId: row.deviceId,
    bitrate: row.bitrate,
    filePath: row.filePath ?? null,
    fileSize: row.fileSize ?? null,
    status: row.status,
    requestedAt: row.requestedAt,
    completedAt: row.completedAt ?? null,
  };
}

/** Request a download. If a record for this user/device/track already exists, returns it. */
export function requestDownload(
  userId: string,
  deviceId: string,
  trackId: number,
  bitrate: number,
): DownloadRecord {
  const existing = db
    .select()
    .from(offlineTracks)
    .where(
      and(
        eq(offlineTracks.userId, userId),
        eq(offlineTracks.lidarrTrackId, trackId),
        eq(offlineTracks.deviceId, deviceId),
      ),
    )
    .get();

  if (existing) {
    return rowToRecord(existing);
  }

  const id = randomUUID();
  const now = new Date().toISOString();
  db.insert(offlineTracks)
    .values({
      id,
      userId,
      lidarrTrackId: trackId,
      deviceId,
      bitrate,
      status: "pending",
      requestedAt: now,
    })
    .run();

  return {
    id,
    lidarrTrackId: trackId,
    deviceId,
    bitrate,
    filePath: null,
    fileSize: null,
    status: "pending",
    requestedAt: now,
    completedAt: null,
  };
}

/** List all downloads for a user + device. */
export function listDownloads(
  userId: string,
  deviceId: string,
): DownloadRecord[] {
  const rows = db
    .select()
    .from(offlineTracks)
    .where(
      and(
        eq(offlineTracks.userId, userId),
        eq(offlineTracks.deviceId, deviceId),
      ),
    )
    .all();
  return rows.map(rowToRecord);
}

/** Get a single download record, verifying ownership. */
export function getDownload(id: string, userId: string): DownloadRecord {
  const row = db
    .select()
    .from(offlineTracks)
    .where(eq(offlineTracks.id, id))
    .get();
  if (!row || row.userId !== userId) {
    throw createError(404, "NOT_FOUND", "Download not found");
  }
  return rowToRecord(row);
}

/** Delete a download record and its associated file. */
export function deleteDownload(id: string, userId: string): void {
  const row = db
    .select()
    .from(offlineTracks)
    .where(eq(offlineTracks.id, id))
    .get();
  if (!row || row.userId !== userId) {
    throw createError(404, "NOT_FOUND", "Download not found");
  }

  if (row.filePath) {
    try {
      unlinkSync(row.filePath);
    } catch {
      // File may already be gone; ignore.
    }
  }

  db.delete(offlineTracks).where(eq(offlineTracks.id, id)).run();
}

/** Mark a download as complete (file has been served and saved by the client). */
export function markDownloadComplete(id: string): void {
  db.update(offlineTracks)
    .set({ status: "completed", completedAt: new Date().toISOString() })
    .where(eq(offlineTracks.id, id))
    .run();
}

function transcodeToFile(
  sourcePath: string,
  bitrate: number,
  outputPath: string,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const cmd = ffmpeg(sourcePath)
      .noVideo()
      .audioCodec("libmp3lame")
      .audioBitrate(bitrate)
      .output(outputPath)
      .on("end", () => {
        unregisterFfmpegCommand(cmd);
        resolve();
      })
      .on("error", (err: Error) => {
        unregisterFfmpegCommand(cmd);
        try {
          unlinkSync(outputPath);
        } catch {
          /* ignore partial file */
        }
        reject(err);
      });

    registerFfmpegCommand(cmd);
    cmd.run();
  });
}

/**
 * Pick one pending download, transcode it, and update the DB.
 * Exported so tests can call it directly without relying on setInterval timing.
 */
export async function processOnePendingDownload(): Promise<void> {
  const pending = db
    .select()
    .from(offlineTracks)
    .where(eq(offlineTracks.status, "pending"))
    .orderBy(asc(offlineTracks.requestedAt))
    .limit(1)
    .get();

  if (!pending) return;

  logger.info(
    { id: pending.id, trackId: pending.lidarrTrackId },
    "Processing pending download",
  );

  db.update(offlineTracks)
    .set({ status: "downloading" })
    .where(eq(offlineTracks.id, pending.id))
    .run();

  try {
    const { sourcePath } = await resolveFilePath(pending.lidarrTrackId);
    const outputDir = path.join(env.OFFLINE_STORAGE_PATH, pending.userId);
    mkdirSync(outputDir, { recursive: true });
    const outputPath = getOfflineFilePath(
      pending.userId,
      pending.lidarrTrackId,
      pending.bitrate,
    );

    if (isPassthrough(sourcePath)) {
      await copyFile(sourcePath, outputPath);
    } else {
      await transcodeToFile(sourcePath, pending.bitrate, outputPath);
    }

    const stat = statSync(outputPath);
    const now = new Date().toISOString();
    db.update(offlineTracks)
      .set({
        status: "ready",
        filePath: outputPath,
        fileSize: stat.size,
        completedAt: now,
      })
      .where(eq(offlineTracks.id, pending.id))
      .run();

    logger.info({ id: pending.id, outputPath }, "Download processing complete");
  } catch (err) {
    logger.error({ err, id: pending.id }, "Download processing failed");
    db.update(offlineTracks)
      .set({ status: "failed", completedAt: new Date().toISOString() })
      .where(eq(offlineTracks.id, pending.id))
      .run();
  }
}

/**
 * Reset any rows stuck in "downloading" status back to "pending" so they are
 * retried after a server crash or ungraceful shutdown.
 * Call this once at startup, after migrations, before starting the worker.
 */
export function resetStuckDownloads(): void {
  const result = db
    .update(offlineTracks)
    .set({ status: "pending" })
    .where(eq(offlineTracks.status, "downloading"))
    .run();
  if (result.changes > 0) {
    logger.warn(
      { count: result.changes },
      "Reset stuck downloading rows to pending",
    );
  }
}

/** Start the background worker that polls for pending downloads every 10 seconds. */
export function startDownloadWorker(): void {
  const INTERVAL = 10 * 1000;

  setInterval(() => {
    processOnePendingDownload().catch((err) => {
      logger.error({ err }, "Download worker error");
    });
  }, INTERVAL);

  logger.info("Download worker started");
}
