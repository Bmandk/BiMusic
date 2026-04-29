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
    MUSIC_LIBRARY_PATH: "/c/test-music",
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

vi.mock("../lidarrClient.js", () => ({
  getTrack: vi.fn(),
  getTrackFile: vi.fn(),
  getRootFolders: vi.fn(),
}));

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
  default: vi.fn(() => mockFfmpegCmd),
}));

const mockReadStream = { pipe: vi.fn(), on: vi.fn() };

vi.mock("fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("fs")>();
  return {
    ...actual,
    mkdirSync: vi.fn(),
    readdirSync: vi.fn(),
    statSync: vi.fn(() => ({ size: 1000, mtimeMs: Date.now() - 1000 })),
    existsSync: vi.fn(() => false),
    unlinkSync: vi.fn(),
    createReadStream: vi.fn(() => mockReadStream),
  };
});

vi.mock("fs/promises", () => ({
  access: vi.fn().mockResolvedValue(undefined),
  constants: { R_OK: 4 },
}));

import type { FfmpegCommand } from "fluent-ffmpeg";
import * as lidarrClient from "../lidarrClient.js";
import * as fs from "fs";
import * as fsp from "fs/promises";
import {
  resetLidarrRootCache,
  registerFfmpegCommand,
  unregisterFfmpegCommand,
  killAllActiveTranscodes,
  initTempDir,
  resolveFilePath,
  getTempFilePath,
  isPassthrough,
  ensureTranscoded,
  serveFile,
} from "../streamService.js";

beforeEach(() => {
  resetLidarrRootCache();
  vi.clearAllMocks();

  // Reset existsSync to return false (no cached transcode)
  vi.mocked(fs.existsSync).mockReturnValue(false);

  // Reset ffmpeg mock to default success behavior
  mockFfmpegCmd.on.mockImplementation(function (
    this: unknown,
    event: string,
    cb: (...args: unknown[]) => void,
  ) {
    if (event === "end") setTimeout(() => cb(), 0);
    return this;
  });

  vi.mocked(fsp.access).mockResolvedValue(undefined);
  vi.mocked(fs.readdirSync).mockReturnValue([]);
});

describe("registerFfmpegCommand / unregisterFfmpegCommand / killAllActiveTranscodes", () => {
  it("tracks and kills registered commands", () => {
    const kill = vi.fn();
    const cmd = { kill } as unknown as FfmpegCommand;
    registerFfmpegCommand(cmd);
    killAllActiveTranscodes();
    expect(kill).toHaveBeenCalledWith("SIGTERM");
  });

  it("does not kill unregistered commands", () => {
    const kill1 = vi.fn();
    const kill2 = vi.fn();
    const cmd1 = { kill: kill1 } as unknown as FfmpegCommand;
    const cmd2 = { kill: kill2 } as unknown as FfmpegCommand;
    registerFfmpegCommand(cmd1);
    registerFfmpegCommand(cmd2);
    unregisterFfmpegCommand(cmd1);
    killAllActiveTranscodes();
    expect(kill1).not.toHaveBeenCalled();
    expect(kill2).toHaveBeenCalled();
  });

  it("killAllActiveTranscodes clears the set (no double-kill)", () => {
    const kill = vi.fn();
    const cmd = { kill } as unknown as FfmpegCommand;
    registerFfmpegCommand(cmd);
    killAllActiveTranscodes();
    killAllActiveTranscodes(); // second call: set is now empty
    expect(kill).toHaveBeenCalledTimes(1);
  });

  it("swallows errors thrown by cmd.kill", () => {
    const badCmd = {
      kill: vi.fn(() => {
        throw new Error("kill failed");
      }),
    } as unknown as FfmpegCommand;
    registerFfmpegCommand(badCmd);
    expect(() => killAllActiveTranscodes()).not.toThrow();
  });
});

describe("initTempDir", () => {
  it("creates the temp directory", () => {
    initTempDir();
    expect(fs.mkdirSync).toHaveBeenCalledWith("/tmp/bimusic", {
      recursive: true,
    });
  });

  it("deletes files found in the temp directory", () => {
    vi.mocked(fs.readdirSync).mockReturnValue([
      "file1.mp3",
      "file2.mp3",
    ] as never);
    initTempDir();
    expect(fs.unlinkSync).toHaveBeenCalledTimes(2);
  });

  it("handles readdirSync throwing without crashing", () => {
    vi.mocked(fs.readdirSync).mockImplementation(() => {
      throw new Error("Dir not found");
    });
    expect(() => initTempDir()).not.toThrow();
  });
});

describe("resolveFilePath", () => {
  it("remaps a Lidarr path to MUSIC_LIBRARY_PATH", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: 10,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: "/music/Artist/Album/track.flac",
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music/" },
    ] as never);

    const result = await resolveFilePath(1);
    // /music stripped, /c/test-music prepended
    expect(result).toContain("Artist");
    expect(result).toContain("Album");
    expect(result).toContain("track.flac");
  });

  it("throws 404 when track has no file", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: false,
      trackFileId: null,
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music" },
    ] as never);

    await expect(resolveFilePath(1)).rejects.toMatchObject({ statusCode: 404 });
  });

  it("throws 404 when trackFileId is missing", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: undefined,
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music" },
    ] as never);

    await expect(resolveFilePath(1)).rejects.toMatchObject({ statusCode: 404 });
  });

  it("throws 404 when trackFile.path is missing", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: 10,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: undefined,
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music" },
    ] as never);

    await expect(resolveFilePath(1)).rejects.toMatchObject({ statusCode: 404 });
  });

  it("throws 404 when file is not readable on disk", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: 10,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: "/music/track.flac",
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music" },
    ] as never);
    vi.mocked(fsp.access).mockRejectedValue(new Error("EACCES"));

    await expect(resolveFilePath(1)).rejects.toMatchObject({ statusCode: 404 });
  });

  it("throws 500 when Lidarr has no root folders configured", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: 10,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: "/music/track.flac",
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([]);

    await expect(resolveFilePath(1)).rejects.toMatchObject({ statusCode: 500 });
  });

  it("caches the Lidarr root path (getRootFolders called only once across multiple calls)", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: 10,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: "/music/Artist/track.flac",
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music" },
    ] as never);

    await resolveFilePath(1);
    await resolveFilePath(1);

    expect(lidarrClient.getRootFolders).toHaveBeenCalledTimes(1);
  });

  it("returns path as-is when it does not start with Lidarr root", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: 10,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: "/c/test-music/Artist/track.flac", // already remapped
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music" },
    ] as never);

    const result = await resolveFilePath(1);
    expect(result).toBe("/c/test-music/Artist/track.flac");
  });
});

describe("getTempFilePath", () => {
  it("returns a deterministic path based on source and bitrate", () => {
    const p1 = getTempFilePath("/music/track.flac", 320);
    const p2 = getTempFilePath("/music/track.flac", 320);
    expect(p1).toBe(p2);
    expect(p1).toMatch(/[/\\]tmp[/\\]bimusic/);
    expect(p1).toMatch(/\.mp3$/);
  });

  it("returns different paths for different bitrates", () => {
    const p128 = getTempFilePath("/music/track.flac", 128);
    const p320 = getTempFilePath("/music/track.flac", 320);
    expect(p128).not.toBe(p320);
  });

  it("returns different paths for different source files", () => {
    const p1 = getTempFilePath("/music/track1.flac", 320);
    const p2 = getTempFilePath("/music/track2.flac", 320);
    expect(p1).not.toBe(p2);
  });
});

describe("isPassthrough", () => {
  it("returns true for .mp3 files", () => {
    expect(isPassthrough("/music/track.mp3")).toBe(true);
  });

  it("returns true for .MP3 files (case-insensitive)", () => {
    expect(isPassthrough("/music/TRACK.MP3")).toBe(true);
  });

  it("returns false for .flac files", () => {
    expect(isPassthrough("/music/track.flac")).toBe(false);
  });

  it("returns false for .m4a files", () => {
    expect(isPassthrough("/music/track.m4a")).toBe(false);
  });

  it("returns false for .ogg files", () => {
    expect(isPassthrough("/music/track.ogg")).toBe(false);
  });
});

describe("ensureTranscoded", () => {
  it("returns temp path when file already exists (no transcoding)", async () => {
    vi.mocked(fs.existsSync).mockReturnValue(true);

    const result = await ensureTranscoded("/music/track.flac", 320);
    const expected = getTempFilePath("/music/track.flac", 320);
    expect(result).toBe(expected);
    // ffmpeg should NOT have been called
    expect(mockFfmpegCmd.run).not.toHaveBeenCalled();
  });

  it("transcodes and returns temp path when file does not exist", async () => {
    vi.mocked(fs.existsSync).mockReturnValue(false);

    const result = await ensureTranscoded("/music/track.flac", 320);
    const expected = getTempFilePath("/music/track.flac", 320);
    expect(result).toBe(expected);
    expect(mockFfmpegCmd.run).toHaveBeenCalled();
    expect(mockFfmpegCmd.audioCodec).toHaveBeenCalledWith("libmp3lame");
    expect(mockFfmpegCmd.audioBitrate).toHaveBeenCalledWith(320);
  });

  it("throws TRANSCODE_ERROR when ffmpeg fails", async () => {
    vi.mocked(fs.existsSync).mockReturnValue(false);

    mockFfmpegCmd.on.mockImplementation(function (
      this: unknown,
      event: string,
      cb: (...args: unknown[]) => void,
    ) {
      if (event === "error")
        setTimeout(() => cb(new Error("ffmpeg crashed")), 0);
      return this;
    });

    await expect(
      ensureTranscoded("/music/track.flac", 320),
    ).rejects.toMatchObject({
      code: "TRANSCODE_ERROR",
    });
  });

  it("deduplicates concurrent transcode requests (same promise reused)", async () => {
    vi.mocked(fs.existsSync).mockReturnValue(false);

    // Both calls should share one ffmpeg invocation
    const [p1, p2] = await Promise.all([
      ensureTranscoded("/music/track.flac", 320),
      ensureTranscoded("/music/track.flac", 320),
    ]);

    expect(p1).toBe(p2);
    // ffmpeg cmd.run() should only be called once for the same key
    expect(mockFfmpegCmd.run).toHaveBeenCalledTimes(1);
  });
});

describe("serveFile", () => {
  function makeMockRes() {
    const res = {
      status: vi.fn().mockReturnThis(),
      setHeader: vi.fn().mockReturnThis(),
      json: vi.fn().mockReturnThis(),
      end: vi.fn().mockReturnThis(),
    };
    return res;
  }

  function makeReq(rangeHeader?: string) {
    return {
      headers: { range: rangeHeader },
    } as never;
  }

  beforeEach(() => {
    vi.mocked(fs.statSync).mockReturnValue({
      size: 10000,
      mtimeMs: Date.now(),
    } as never);
    mockReadStream.pipe.mockClear();
    vi.mocked(fs.createReadStream).mockReturnValue(mockReadStream as never);
  });

  it("serves a full file (200) when no Range header", () => {
    const req = makeReq(undefined);
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.setHeader).toHaveBeenCalledWith("Content-Length", 10000);
    expect(res.setHeader).toHaveBeenCalledWith("Content-Type", "audio/mpeg");
    expect(fs.createReadStream).toHaveBeenCalledWith("/music/track.mp3");
    expect(mockReadStream.pipe).toHaveBeenCalledWith(res);
  });

  it("serves a partial file (206) when Range header is provided", () => {
    const req = makeReq("bytes=0-999");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(206);
    expect(res.setHeader).toHaveBeenCalledWith(
      "Content-Range",
      "bytes 0-999/10000",
    );
    expect(res.setHeader).toHaveBeenCalledWith("Content-Length", 1000);
    expect(fs.createReadStream).toHaveBeenCalledWith("/music/track.mp3", {
      start: 0,
      end: 999,
    });
  });

  it("handles open-ended Range header (end omitted)", () => {
    const req = makeReq("bytes=5000-");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(206);
    expect(res.setHeader).toHaveBeenCalledWith(
      "Content-Range",
      "bytes 5000-9999/10000",
    );
  });

  it("clamps end to fileSize-1 when range end exceeds file size (RFC 7233)", () => {
    const req = makeReq("bytes=9999-20000"); // end exceeds file size — should be clamped
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(206);
    expect(res.setHeader).toHaveBeenCalledWith(
      "Content-Range",
      "bytes 9999-9999/10000",
    );
  });

  it("returns 416 when start is at or beyond file size", () => {
    const req = makeReq("bytes=10000-10999"); // start >= fileSize
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(416);
    expect(res.setHeader).toHaveBeenCalledWith(
      "Content-Range",
      "bytes */10000",
    );
    expect(res.end).toHaveBeenCalled();
  });

  it("returns 400 for malformed Range header (non-bytes unit)", () => {
    const req = makeReq("chunks=0-999");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalled();
  });

  it("returns 400 when Range header has no range part", () => {
    const req = makeReq("bytes=");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    // "bytes=" splits to ["bytes", ""] and range is "" (falsy),
    // triggering the !range check in serveFile which returns 400.
    expect(res.status).toHaveBeenCalledWith(400);
  });

  it("returns 416 when start > end in Range header", () => {
    const req = makeReq("bytes=999-100");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(416);
  });

  it("returns 416 for multi-range requests", () => {
    const req = makeReq("bytes=0-100, 200-300");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(416);
    expect(res.setHeader).toHaveBeenCalledWith(
      "Content-Range",
      "bytes */10000",
    );
    expect(res.end).toHaveBeenCalled();
  });

  it("handles suffix range (bytes=-N) returning last N bytes", () => {
    const req = makeReq("bytes=-500");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(206);
    // start = 10000 - 500 = 9500, end = 9999
    expect(res.setHeader).toHaveBeenCalledWith(
      "Content-Range",
      "bytes 9500-9999/10000",
    );
  });

  it("sets Accept-Ranges and Content-Type headers always", () => {
    const req = makeReq(undefined);
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.setHeader).toHaveBeenCalledWith("Accept-Ranges", "bytes");
    expect(res.setHeader).toHaveBeenCalledWith("Content-Type", "audio/mpeg");
  });

  it("sends 500 on read stream error when headers not yet sent", () => {
    const req = makeReq(undefined);
    const res = { ...makeMockRes(), headersSent: false, destroyed: false };
    let errorCb: ((err: Error) => void) | undefined;
    const stream = {
      pipe: vi.fn(),
      on: vi.fn((event: string, cb: (err: Error) => void) => {
        if (event === "error") errorCb = cb;
        return stream;
      }),
    };
    vi.mocked(fs.createReadStream).mockReturnValue(stream as never);

    serveFile("/music/track.mp3", req, res as never);
    errorCb?.(new Error("ENOENT"));

    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.end).toHaveBeenCalled();
  });

  it("destroys response on read stream error when headers already sent", () => {
    const req = makeReq(undefined);
    const res = {
      ...makeMockRes(),
      headersSent: true,
      destroyed: false,
      destroy: vi.fn(),
    };
    let errorCb: ((err: Error) => void) | undefined;
    const stream = {
      pipe: vi.fn(),
      on: vi.fn((event: string, cb: (err: Error) => void) => {
        if (event === "error") errorCb = cb;
        return stream;
      }),
    };
    vi.mocked(fs.createReadStream).mockReturnValue(stream as never);

    serveFile("/music/track.mp3", req, res as never);
    errorCb?.(new Error("EIO"));

    expect(res.destroy).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalledWith(500);
  });
});
