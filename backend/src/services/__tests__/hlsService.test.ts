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
    HLS_CACHE_DIR: "/tmp/hls-test",
    HLS_SEGMENT_SECONDS: 6,
  },
}));

vi.mock("../../utils/logger.js", () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  },
}));

vi.mock("../trackFileResolver.js", () => ({
  registerFfmpegCommand: vi.fn(),
  unregisterFfmpegCommand: vi.fn(),
}));

const mockFfmpegCmd = vi.hoisted(() => ({
  input: vi.fn().mockReturnThis(),
  seekInput: vi.fn().mockReturnThis(),
  noVideo: vi.fn().mockReturnThis(),
  audioCodec: vi.fn().mockReturnThis(),
  audioBitrate: vi.fn().mockReturnThis(),
  duration: vi.fn().mockReturnThis(),
  outputOptions: vi.fn().mockReturnThis(),
  format: vi.fn().mockReturnThis(),
  output: vi.fn().mockReturnThis(),
  on: vi.fn().mockImplementation(function (
    this: Record<string, unknown>,
    event: string,
    cb: (...args: unknown[]) => void,
  ) {
    if (event === "end") {
      this["_endCb"] = cb;
    }
    return this;
  }),
  run: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    const endCb = this["_endCb"] as (() => void) | undefined;
    // renameSync is mocked (vi.fn), so we just need to fire the end callback.
    setTimeout(() => endCb?.(), 0);
  }),
  kill: vi.fn(),
}));

vi.mock("fluent-ffmpeg", () => ({
  default: vi.fn(() => mockFfmpegCmd),
}));

vi.mock("fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("fs")>();
  return {
    ...actual,
    existsSync: vi.fn(() => false),
    mkdirSync: vi.fn(),
    renameSync: vi.fn(),
    unlinkSync: vi.fn(),
  };
});

import * as fs from "fs";
import {
  computeTrackKey,
  buildPlaylist,
  ensureSegment,
  generateSegment,
} from "../hlsService.js";

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(fs.existsSync).mockReturnValue(false);
  mockFfmpegCmd.on.mockImplementation(function (
    this: Record<string, unknown>,
    event: string,
    cb: (...args: unknown[]) => void,
  ) {
    if (event === "end") this["_endCb"] = cb;
    return this;
  });
  mockFfmpegCmd.run.mockImplementation(function (
    this: Record<string, unknown>,
  ) {
    const endCb = this["_endCb"] as (() => void) | undefined;
    setTimeout(() => endCb?.(), 0);
  });
});

describe("computeTrackKey", () => {
  it("returns a deterministic hex string for the same inputs", () => {
    const k1 = computeTrackKey("/music/track.flac", 1700000000000, 50000, 320);
    const k2 = computeTrackKey("/music/track.flac", 1700000000000, 50000, 320);
    expect(k1).toBe(k2);
    expect(k1).toMatch(/^[0-9a-f]{64}$/);
  });

  it("differs for different bitrates", () => {
    const k128 = computeTrackKey(
      "/music/track.flac",
      1700000000000,
      50000,
      128,
    );
    const k320 = computeTrackKey(
      "/music/track.flac",
      1700000000000,
      50000,
      320,
    );
    expect(k128).not.toBe(k320);
  });

  it("differs for different source paths", () => {
    const k1 = computeTrackKey("/music/track1.flac", 1700000000000, 50000, 320);
    const k2 = computeTrackKey("/music/track2.flac", 1700000000000, 50000, 320);
    expect(k1).not.toBe(k2);
  });

  it("differs when mtime changes (source file replaced)", () => {
    const k1 = computeTrackKey("/music/track.flac", 1700000000000, 50000, 320);
    const k2 = computeTrackKey("/music/track.flac", 1700000001000, 50000, 320);
    expect(k1).not.toBe(k2);
  });
});

describe("buildPlaylist", () => {
  it("starts with #EXTM3U and ends with #EXT-X-ENDLIST", () => {
    const pl = buildPlaylist(24000, 4, 6, 320, "mytoken");
    expect(pl).toMatch(/^#EXTM3U\n/);
    expect(pl).toMatch(/#EXT-X-ENDLIST\n$/);
  });

  it("emits the correct number of segments", () => {
    const pl = buildPlaylist(24000, 4, 6, 320, "mytoken");
    const matches = pl.match(/#EXTINF:/g);
    expect(matches).toHaveLength(4);
  });

  it("includes EXT-X-TARGETDURATION matching segmentSeconds", () => {
    const pl = buildPlaylist(24000, 4, 6, 320, "mytoken");
    expect(pl).toContain("#EXT-X-TARGETDURATION:6");
  });

  it("includes EXT-X-PLAYLIST-TYPE:VOD", () => {
    const pl = buildPlaylist(24000, 4, 6, 320, "mytoken");
    expect(pl).toContain("#EXT-X-PLAYLIST-TYPE:VOD");
  });

  it("embeds the token in each segment URI", () => {
    const pl = buildPlaylist(24000, 4, 6, 320, "tok123");
    expect(pl).toMatch(/segment\/000\?bitrate=320&token=tok123/);
    expect(pl).toMatch(/segment\/003\?bitrate=320&token=tok123/);
  });

  it("last segment EXTINF reflects remaining duration, not full segmentSeconds", () => {
    // 25 seconds total, 6s segments → 4 full + 1 partial (1 second)
    const durationMs = 25000;
    const segmentCount = Math.ceil(durationMs / 6000); // 5
    const pl = buildPlaylist(durationMs, segmentCount, 6, 320, "tok");
    const lines = pl.split("\n");
    // Find the last EXTINF line
    const lastExtinf = [...lines]
      .reverse()
      .find((l) => l.startsWith("#EXTINF:"));
    expect(lastExtinf).toBe("#EXTINF:1.000,");
  });

  it("zero-pads segment indices to 3 digits", () => {
    const pl = buildPlaylist(6000, 1, 6, 320, "tok");
    expect(pl).toContain("segment/000");
  });
});

describe("ensureSegment cache-hit", () => {
  it("returns the cached path without invoking ffmpeg when file exists", async () => {
    vi.mocked(fs.existsSync).mockReturnValue(true);

    const result = await ensureSegment({
      sourcePath: "/music/track.flac",
      trackKey: "abc123",
      segmentIndex: 0,
      bitrate: 320,
      segmentSeconds: 6,
    });

    expect(result).toContain("segment000.mp3");
    expect(mockFfmpegCmd.run).not.toHaveBeenCalled();
  });
});

describe("generateSegment deduplication", () => {
  it("concurrent calls for the same segment share one ffmpeg invocation", async () => {
    const opts = {
      sourcePath: "/music/track.flac",
      trackKey: "dedup-key",
      segmentIndex: 5,
      bitrate: 128,
      segmentSeconds: 6,
    };

    const [p1, p2] = await Promise.all([
      ensureSegment(opts),
      ensureSegment(opts),
    ]);

    expect(p1).toBe(p2);
    expect(mockFfmpegCmd.run).toHaveBeenCalledTimes(1);
  });
});

describe("generateSegment ffmpeg invocation", () => {
  it("calls ffmpeg with correct audio codec and bitrate", async () => {
    await generateSegment({
      sourcePath: "/music/track.flac",
      trackKey: "ffmpeg-test",
      segmentIndex: 0,
      bitrate: 320,
      segmentSeconds: 6,
    });

    expect(mockFfmpegCmd.audioCodec).toHaveBeenCalledWith("libmp3lame");
    expect(mockFfmpegCmd.audioBitrate).toHaveBeenCalledWith(320);
    expect(mockFfmpegCmd.format).toHaveBeenCalledWith("mp3");
    expect(mockFfmpegCmd.seekInput).toHaveBeenCalledWith(0);
    expect(mockFfmpegCmd.duration).toHaveBeenCalledWith(6);
  });

  it("uses -ss offset = segmentIndex * segmentSeconds", async () => {
    await generateSegment({
      sourcePath: "/music/track.flac",
      trackKey: "offset-test",
      segmentIndex: 3,
      bitrate: 128,
      segmentSeconds: 6,
    });

    expect(mockFfmpegCmd.seekInput).toHaveBeenCalledWith(18); // 3 * 6
  });

  it("rejects when ffmpeg fires an error event", async () => {
    mockFfmpegCmd.on.mockImplementation(function (
      this: Record<string, unknown>,
      event: string,
      cb: (...args: unknown[]) => void,
    ) {
      if (event === "error") {
        this["_errorCb"] = cb;
      }
      return this;
    });
    mockFfmpegCmd.run.mockImplementation(function (
      this: Record<string, unknown>,
    ) {
      const errorCb = this["_errorCb"] as ((err: Error) => void) | undefined;
      setTimeout(() => errorCb?.(new Error("ffmpeg exploded")), 0);
    });

    await expect(
      generateSegment({
        sourcePath: "/music/track.flac",
        trackKey: "error-test",
        segmentIndex: 0,
        bitrate: 320,
        segmentSeconds: 6,
      }),
    ).rejects.toThrow("ffmpeg exploded");
  });
});
