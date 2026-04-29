import { describe, it, expect, beforeEach, vi } from "vitest";

vi.mock("../../config/env.js", () => ({
  env: {
    PORT: 3001,
    NODE_ENV: "test" as const,
    JWT_ACCESS_SECRET: "test-access-secret-at-least-32-chars-long",
    JWT_REFRESH_SECRET: "test-refresh-secret-at-least-32-chars-long",
    JWT_ACCESS_EXPIRY: "15m",
    JWT_REFRESH_EXPIRY: "30d",
    DB_PATH: ":memory:",
    LIDARR_URL: "http://localhost:8686",
    LIDARR_API_KEY: "test",
    MUSIC_LIBRARY_PATH: "/music",
    OFFLINE_STORAGE_PATH: "./data/offline",
    ADMIN_USERNAME: "admin",
    ADMIN_PASSWORD: "adminpassword123",
    TEMP_DIR: "/tmp/bimusic",
  },
}));

vi.mock("../../utils/logger.js", () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    child: vi.fn(() => ({
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
      debug: vi.fn(),
    })),
  },
}));

vi.mock("../../db/connection.js", async () => {
  const BetterSqlite3 = (await import("better-sqlite3")).default;
  const { drizzle } = await import("drizzle-orm/better-sqlite3");
  const schemaModule = await import("../../db/schema.js");

  const sqlite = new BetterSqlite3(":memory:");
  sqlite.pragma("foreign_keys = OFF");
  sqlite.exec(`
    CREATE TABLE users (
      id TEXT PRIMARY KEY NOT NULL,
      username TEXT NOT NULL UNIQUE,
      displayName TEXT NOT NULL,
      passwordHash TEXT NOT NULL,
      isAdmin INTEGER DEFAULT 0 NOT NULL,
      createdAt TEXT NOT NULL
    );
    CREATE TABLE offline_tracks (
      id TEXT PRIMARY KEY NOT NULL,
      userId TEXT NOT NULL,
      lidarrTrackId INTEGER NOT NULL,
      deviceId TEXT NOT NULL,
      bitrate INTEGER NOT NULL DEFAULT 320,
      filePath TEXT,
      fileSize INTEGER,
      status TEXT NOT NULL DEFAULT 'pending',
      requestedAt TEXT NOT NULL,
      completedAt TEXT,
      UNIQUE(userId, lidarrTrackId, deviceId)
    );
  `);

  return { db: drizzle(sqlite, { schema: schemaModule.schema }), sqlite };
});

const mockFfmpegFactory = vi.hoisted(() => vi.fn());

const mockFfmpegCmd = vi.hoisted(() => ({
  noVideo: vi.fn().mockReturnThis(),
  audioCodec: vi.fn().mockReturnThis(),
  audioBitrate: vi.fn().mockReturnThis(),
  output: vi.fn().mockReturnThis(),
  on: vi.fn().mockImplementation(function (
    this: unknown,
    event: string,
    cb: (...args: unknown[]) => void,
  ) {
    if (event === "end") setTimeout(() => cb(), 0);
    return this;
  }),
  run: vi.fn(),
  kill: vi.fn(),
}));

vi.mock("fluent-ffmpeg", () => ({
  default: mockFfmpegFactory.mockImplementation(() => mockFfmpegCmd),
}));

vi.mock("../streamService.js", () => ({
  resolveFilePath: vi.fn(),
  isPassthrough: vi.fn(() => false),
  registerFfmpegCommand: vi.fn(),
  unregisterFfmpegCommand: vi.fn(),
}));

vi.mock("fs/promises", () => ({
  copyFile: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("fs")>();
  return {
    ...actual,
    mkdirSync: vi.fn(),
    statSync: vi.fn(() => ({ size: 1024 })),
    unlinkSync: vi.fn(),
  };
});

import { eq } from "drizzle-orm";
import { db } from "../../db/connection.js";
import { offlineTracks } from "../../db/schema.js";
import * as streamService from "../streamService.js";
import * as fsPromises from "fs/promises";
import {
  requestDownload,
  listDownloads,
  getDownload,
  deleteDownload,
  markDownloadComplete,
  processOnePendingDownload,
  resetStuckDownloads,
} from "../downloadService.js";

const TEST_USER = "user-dl-1";
const TEST_DEVICE = "device-1";

beforeEach(() => {
  db.delete(offlineTracks).run();
  vi.clearAllMocks();

  // Reset ffmpeg mock to default success behavior
  mockFfmpegCmd.on.mockImplementation(function (
    this: unknown,
    event: string,
    cb: (...args: unknown[]) => void,
  ) {
    if (event === "end") setTimeout(() => cb(), 0);
    return this;
  });
});

describe("requestDownload", () => {
  it("creates a new download record", () => {
    const result = requestDownload(TEST_USER, TEST_DEVICE, 100, 320);

    expect(result.id).toBeDefined();
    expect(result.lidarrTrackId).toBe(100);
    expect(result.deviceId).toBe(TEST_DEVICE);
    expect(result.bitrate).toBe(320);
    expect(result.status).toBe("pending");
    expect(result.filePath).toBeNull();
    expect(result.fileSize).toBeNull();
    expect(result.completedAt).toBeNull();
  });

  it("returns existing record when same user/device/track combination exists", () => {
    const first = requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    const second = requestDownload(TEST_USER, TEST_DEVICE, 100, 320);

    expect(second.id).toBe(first.id);
  });

  it("creates separate records for different devices", () => {
    const r1 = requestDownload(TEST_USER, "device-a", 100, 320);
    const r2 = requestDownload(TEST_USER, "device-b", 100, 320);
    expect(r1.id).not.toBe(r2.id);
  });

  it("creates separate records for different tracks", () => {
    const r1 = requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    const r2 = requestDownload(TEST_USER, TEST_DEVICE, 101, 320);
    expect(r1.id).not.toBe(r2.id);
  });
});

describe("listDownloads", () => {
  it("returns empty array when no downloads", () => {
    const result = listDownloads(TEST_USER, TEST_DEVICE);
    expect(result).toEqual([]);
  });

  it("returns downloads for the specified user and device", () => {
    requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    requestDownload(TEST_USER, TEST_DEVICE, 101, 128);

    const result = listDownloads(TEST_USER, TEST_DEVICE);
    expect(result).toHaveLength(2);
  });

  it("filters by device — does not return downloads from other devices", () => {
    requestDownload(TEST_USER, "device-a", 100, 320);
    requestDownload(TEST_USER, "device-b", 101, 320);

    const result = listDownloads(TEST_USER, "device-a");
    expect(result).toHaveLength(1);
    expect(result[0]?.lidarrTrackId).toBe(100);
  });

  it("does not return downloads from other users", () => {
    requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    requestDownload("other-user", TEST_DEVICE, 101, 320);

    const result = listDownloads(TEST_USER, TEST_DEVICE);
    expect(result).toHaveLength(1);
  });
});

describe("getDownload", () => {
  it("returns the download record for the owner", () => {
    const created = requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    const result = getDownload(created.id, TEST_USER);
    expect(result.id).toBe(created.id);
    expect(result.lidarrTrackId).toBe(100);
  });

  it("throws 404 when record does not exist", () => {
    expect(() => getDownload("nonexistent", TEST_USER)).toThrow();
  });

  it("throws 404 when record belongs to another user", () => {
    const created = requestDownload("other-user", TEST_DEVICE, 100, 320);
    expect(() => getDownload(created.id, TEST_USER)).toThrow();
  });
});

describe("deleteDownload", () => {
  it("removes the download record", () => {
    const created = requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    deleteDownload(created.id, TEST_USER);

    expect(() => getDownload(created.id, TEST_USER)).toThrow();
  });

  it("throws 404 when record does not exist", () => {
    expect(() => deleteDownload("nonexistent", TEST_USER)).toThrow();
  });

  it("throws 404 when record belongs to another user", () => {
    const created = requestDownload("other-user", TEST_DEVICE, 100, 320);
    expect(() => deleteDownload(created.id, TEST_USER)).toThrow();
  });

  it("attempts to unlink file when filePath is set", async () => {
    const { unlinkSync } = await import("fs");
    const created = requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    // Manually update filePath in DB
    db.update(offlineTracks)
      .set({ filePath: "/some/path/file.mp3" })
      .where(eq(offlineTracks.id, created.id))
      .run();

    deleteDownload(created.id, TEST_USER);
    expect(unlinkSync).toHaveBeenCalled();
  });

  it("succeeds even if unlinkSync throws (file already gone)", async () => {
    const { unlinkSync } = await import("fs");
    vi.mocked(unlinkSync).mockImplementationOnce(() => {
      throw new Error("ENOENT");
    });

    const created = requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    db.update(offlineTracks)
      .set({ filePath: "/missing/file.mp3" })
      .where(eq(offlineTracks.id, created.id))
      .run();

    // Should not throw
    expect(() => deleteDownload(created.id, TEST_USER)).not.toThrow();
  });
});

describe("markDownloadComplete", () => {
  it("updates status to 'completed' and sets completedAt", () => {
    requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    const before = listDownloads(TEST_USER, TEST_DEVICE);
    expect(before[0]?.status).toBe("pending");

    markDownloadComplete(before[0].id);

    const after = listDownloads(TEST_USER, TEST_DEVICE);
    expect(after[0]?.status).toBe("completed");
    expect(after[0]?.completedAt).toBeDefined();
  });
});

describe("resetStuckDownloads", () => {
  it("resets all 'downloading' rows back to 'pending'", () => {
    // Insert one row directly as 'downloading'
    db.insert(offlineTracks)
      .values({
        id: "stuck-id",
        userId: TEST_USER,
        lidarrTrackId: 999,
        deviceId: TEST_DEVICE,
        bitrate: 320,
        status: "downloading",
        requestedAt: new Date().toISOString(),
      })
      .run();

    resetStuckDownloads();

    const row = db
      .select()
      .from(offlineTracks)
      .where(eq(offlineTracks.id, "stuck-id"))
      .get();
    expect(row?.status).toBe("pending");
  });

  it("does not affect rows in other statuses", () => {
    requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    const [row] = listDownloads(TEST_USER, TEST_DEVICE);

    // Mark it ready
    db.update(offlineTracks)
      .set({ status: "ready" })
      .where(eq(offlineTracks.id, row.id))
      .run();

    resetStuckDownloads();

    const after = db
      .select()
      .from(offlineTracks)
      .where(eq(offlineTracks.id, row.id))
      .get();
    expect(after?.status).toBe("ready");
  });

  it("is a no-op when there are no stuck rows", () => {
    // Should not throw even when table is empty
    expect(() => resetStuckDownloads()).not.toThrow();
  });
});

describe("processOnePendingDownload", () => {
  it("does nothing when there are no pending downloads", async () => {
    await processOnePendingDownload();
    expect(streamService.resolveFilePath).not.toHaveBeenCalled();
  });

  it("transcodes a pending download and marks it ready", async () => {
    vi.mocked(streamService.resolveFilePath).mockResolvedValue(
      "/music/track.flac",
    );

    const created = requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    await processOnePendingDownload();

    const all = listDownloads(TEST_USER, TEST_DEVICE);
    expect(all[0]?.status).toBe("ready");
    expect(all[0]?.filePath).toBeDefined();
    expect(all[0]?.fileSize).toBe(1024);
    expect(all[0]?.completedAt).toBeDefined();
    expect(created.id).toBe(all[0]?.id);
  });

  it("marks download as failed when resolveFilePath throws", async () => {
    vi.mocked(streamService.resolveFilePath).mockRejectedValue(
      new Error("Track not found"),
    );

    requestDownload(TEST_USER, TEST_DEVICE, 999, 320);
    await processOnePendingDownload();

    const all = listDownloads(TEST_USER, TEST_DEVICE);
    expect(all[0]?.status).toBe("failed");
    expect(all[0]?.completedAt).toBeDefined();
  });

  it("marks download as failed when ffmpeg errors", async () => {
    vi.mocked(streamService.resolveFilePath).mockResolvedValue(
      "/music/track.flac",
    );

    // Make ffmpeg call the error callback instead of end
    mockFfmpegCmd.on.mockImplementation(function (
      this: unknown,
      event: string,
      cb: (...args: unknown[]) => void,
    ) {
      if (event === "error") setTimeout(() => cb(new Error("ffmpeg error")), 0);
      return this;
    });

    requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    await processOnePendingDownload();

    const all = listDownloads(TEST_USER, TEST_DEVICE);
    expect(all[0]?.status).toBe("failed");
  });

  it("processes the oldest pending download first", async () => {
    vi.mocked(streamService.resolveFilePath).mockResolvedValue(
      "/music/track.flac",
    );

    // Insert with specific requestedAt values
    const earlier = new Date(Date.now() - 10000).toISOString();
    const later = new Date().toISOString();

    db.insert(offlineTracks)
      .values({
        id: "old-id",
        userId: TEST_USER,
        lidarrTrackId: 1,
        deviceId: TEST_DEVICE,
        bitrate: 320,
        status: "pending",
        requestedAt: earlier,
      })
      .run();

    db.insert(offlineTracks)
      .values({
        id: "new-id",
        userId: TEST_USER,
        lidarrTrackId: 2,
        deviceId: "device-2",
        bitrate: 320,
        status: "pending",
        requestedAt: later,
      })
      .run();

    await processOnePendingDownload();

    // Only one should have been processed
    const all = db.select().from(offlineTracks).all();
    const processed = all.filter((r) => r.status === "ready");
    const stillPending = all.filter((r) => r.status === "pending");
    expect(processed).toHaveLength(1);
    expect(stillPending).toHaveLength(1);
    // The older one should have been processed
    expect(processed[0]?.id).toBe("old-id");
  });

  it("calls registerFfmpegCommand and unregisterFfmpegCommand", async () => {
    vi.mocked(streamService.resolveFilePath).mockResolvedValue(
      "/music/track.flac",
    );

    requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    await processOnePendingDownload();

    expect(streamService.registerFfmpegCommand).toHaveBeenCalled();
    expect(streamService.unregisterFfmpegCommand).toHaveBeenCalled();
  });

  it("copies MP3 source directly without transcoding (passthrough)", async () => {
    vi.mocked(streamService.resolveFilePath).mockResolvedValue(
      "/music/track.mp3",
    );
    vi.mocked(streamService.isPassthrough).mockReturnValue(true);

    requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    await processOnePendingDownload();

    // copyFile should have been used instead of ffmpeg
    expect(fsPromises.copyFile).toHaveBeenCalledWith(
      "/music/track.mp3",
      expect.stringContaining("100-320.mp3"),
    );
    // ffmpeg should NOT have been invoked
    expect(mockFfmpegFactory).not.toHaveBeenCalled();

    // Record should still be marked ready
    const all = listDownloads(TEST_USER, TEST_DEVICE);
    expect(all[0]?.status).toBe("ready");
    expect(all[0]?.filePath).toBeDefined();
  });

  it("transcodes non-MP3 source via ffmpeg", async () => {
    vi.mocked(streamService.resolveFilePath).mockResolvedValue(
      "/music/track.flac",
    );
    vi.mocked(streamService.isPassthrough).mockReturnValue(false);

    requestDownload(TEST_USER, TEST_DEVICE, 100, 320);
    await processOnePendingDownload();

    // ffmpeg should have been invoked for non-MP3
    expect(streamService.registerFfmpegCommand).toHaveBeenCalled();
    // copyFile should NOT have been used
    expect(fsPromises.copyFile).not.toHaveBeenCalled();

    const all = listDownloads(TEST_USER, TEST_DEVICE);
    expect(all[0]?.status).toBe("ready");
  });
});
