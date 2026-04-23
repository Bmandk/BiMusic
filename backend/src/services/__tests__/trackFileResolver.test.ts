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
    HLS_CACHE_DIR: "./data/hls",
    HLS_SEGMENT_SECONDS: 6,
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

const mockReadStream = { pipe: vi.fn(), on: vi.fn() };

vi.mock("fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("fs")>();
  return {
    ...actual,
    statSync: vi.fn(() => ({ size: 10000, mtimeMs: Date.now() - 1000 })),
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
  resolveFilePath,
  isPassthrough,
  serveFile,
} from "../trackFileResolver.js";

beforeEach(() => {
  resetLidarrRootCache();
  vi.clearAllMocks();
  vi.mocked(fsp.access).mockResolvedValue(undefined);
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
    killAllActiveTranscodes();
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

describe("resolveFilePath", () => {
  it("remaps a Lidarr path to MUSIC_LIBRARY_PATH and returns durationMs", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: 10,
      duration: 240000,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: "/music/Artist/Album/track.flac",
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music/" },
    ] as never);

    const result = await resolveFilePath(1);
    expect(result.sourcePath).toContain("Artist");
    expect(result.sourcePath).toContain("Album");
    expect(result.sourcePath).toContain("track.flac");
    expect(result.durationMs).toBe(240000);
  });

  it("returns durationMs: 0 when track duration is 0", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: 10,
      duration: 0,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: "/music/Artist/Album/track.flac",
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music/" },
    ] as never);

    const result = await resolveFilePath(1);
    expect(result.durationMs).toBe(0);
    expect(result.sourcePath).toContain("Artist");
  });

  it("throws 404 when track has no file", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: false,
      trackFileId: null,
      duration: 0,
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
      duration: 0,
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
      duration: 0,
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
      duration: 0,
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
      duration: 0,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: "/music/track.flac",
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([]);

    await expect(resolveFilePath(1)).rejects.toMatchObject({ statusCode: 500 });
  });

  it("caches the Lidarr root path (getRootFolders called only once)", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue({
      id: 1,
      hasFile: true,
      trackFileId: 10,
      duration: 120000,
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
      duration: 60000,
    } as never);
    vi.mocked(lidarrClient.getTrackFile).mockResolvedValue({
      id: 10,
      path: "/c/test-music/Artist/track.flac",
    } as never);
    vi.mocked(lidarrClient.getRootFolders).mockResolvedValue([
      { path: "/music" },
    ] as never);

    const result = await resolveFilePath(1);
    expect(result.sourcePath).toBe("/c/test-music/Artist/track.flac");
    expect(result.durationMs).toBe(60000);
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

  it("returns 416 when start >= fileSize (unsatisfiable)", () => {
    const req = makeReq("bytes=10000-20000");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(416);
    expect(res.setHeader).toHaveBeenCalledWith(
      "Content-Range",
      "bytes */10000",
    );
    expect(res.end).toHaveBeenCalled();
  });

  it("clamps end to fileSize-1 per RFC 7233 when start is valid but end overshoots", () => {
    const req = makeReq("bytes=9999-20000");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(206);
    expect(res.setHeader).toHaveBeenCalledWith(
      "Content-Range",
      "bytes 9999-9999/10000",
    );
    expect(res.setHeader).toHaveBeenCalledWith("Content-Length", 1);
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

    expect(res.status).toHaveBeenCalledWith(400);
  });

  it("returns 416 when start > end in Range header", () => {
    const req = makeReq("bytes=999-100");
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.status).toHaveBeenCalledWith(416);
  });

  it("sets Accept-Ranges and Content-Type headers always", () => {
    const req = makeReq(undefined);
    const res = makeMockRes();

    serveFile("/music/track.mp3", req, res as never);

    expect(res.setHeader).toHaveBeenCalledWith("Accept-Ranges", "bytes");
    expect(res.setHeader).toHaveBeenCalledWith("Content-Type", "audio/mpeg");
  });

  it("uses custom contentType when provided", () => {
    const req = makeReq(undefined);
    const res = makeMockRes();

    serveFile("/music/segment000.ts", req, res as never, {
      contentType: "video/mp2t",
    });

    expect(res.setHeader).toHaveBeenCalledWith("Content-Type", "video/mp2t");
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
