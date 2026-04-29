// tests/setup.ts sets env vars before this file loads (via vitest setupFiles)
import { vi, describe, it, expect, beforeAll, afterEach } from 'vitest';
import request from 'supertest';
import nock from 'nock';
import fs from 'fs';
import path from 'path';
import os from 'os';
import type { Express } from 'express';

// --- fluent-ffmpeg mock ---
// Hoisted so the mock factory can reference them before imports are resolved.
const mockState = vi.hoisted(() => ({
  callCount: 0,
  delayMs: 0,
}));

vi.mock('fluent-ffmpeg', () => ({
  default: vi.fn((_src: string) => {
    mockState.callCount++;
    let outputPath = '';
    const callbacks: Record<string, (...args: unknown[]) => void> = {};

    const chain = {
      noVideo: () => chain,
      audioCodec: (_codec: string) => chain,
      audioBitrate: (_bitrate: number) => chain,
      format: (_fmt: string) => chain,
      kill: (_signal: string) => {},
      output: (p: string) => {
        outputPath = p;
        return chain;
      },
      on: (event: string, cb: (...args: unknown[]) => void) => {
        callbacks[event] = cb;
        return chain;
      },
      // New streaming path: pipe() without a destination returns a PassThrough.
      pipe: () => {
        const { PassThrough } = require('stream');
        const pt = new PassThrough();
        setTimeout(() => {
          try {
            pt.push(Buffer.alloc(10 * 1024)); // 10 KB fake MP3 data
            pt.push(null);                    // signal EOF
            callbacks['end']?.();
          } catch (err) {
            callbacks['error']?.(err as Error);
            pt.destroy(err as Error);
          }
        }, mockState.delayMs);
        return pt;
      },
      // Old blocking path: write file to disk then fire 'end'.
      run: () => {
        setTimeout(() => {
          try {
            fs.mkdirSync(path.dirname(outputPath), { recursive: true });
            fs.writeFileSync(outputPath, Buffer.alloc(10 * 1024)); // 10 KB fake MP3
            callbacks['end']?.();
          } catch (err) {
            callbacks['error']?.(err as Error);
          }
        }, mockState.delayMs);
      },
    };
    return chain;
  }),
}));

import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/db/migrate.js';
import { bootstrapAdminIfNeeded } from '../../src/services/userService.js';
import { initTempDir, resetLidarrRootCache } from '../../src/services/streamService.js';
import { resetLidarrMetadataCache } from '../../src/services/lidarrClient.js';

const LIDARR = 'http://localhost:8686';

// 50 KB buffer — large enough to exercise Range slicing.
const FAKE_AUDIO = Buffer.alloc(50 * 1024, 0xab);

let app: Express;
let token: string;
let fixtureDir: string;

function makeTrack(trackId: number, trackFileId: number) {
  return {
    id: trackId,
    artistId: 1,
    albumId: 1,
    trackFileId,
    foreignTrackId: null,
    trackNumber: '1',
    absoluteTrackNumber: 1,
    title: 'Test Track',
    duration: 240000,
    hasFile: true,
    explicit: false,
    mediumNumber: 1,
    trackFile: null,
    artist: {
      id: 1,
      artistName: 'Artist',
      foreignArtistId: null,
      overview: null,
      artistType: null,
      status: 'continuing',
      ended: false,
      images: null,
      path: null,
      monitored: true,
      genres: null,
      sortName: null,
      ratings: { votes: 0, value: 0 },
    },
  };
}

function makeTrackFile(trackFileId: number, filePath: string) {
  return {
    id: trackFileId,
    artistId: 1,
    albumId: 1,
    path: filePath,
    size: FAKE_AUDIO.length,
    dateAdded: new Date().toISOString(),
    quality: { quality: { id: 1, name: 'MP3-320' } },
  };
}

function stubLidarr(trackId: number, trackFileId: number, filePath: string, times = 1) {
  // Root folder stub — needed for path remapping (cached after first call).
  // Use a path that won't match fixtureDir so remapPath returns paths as-is.
  nock(LIDARR)
    .get('/api/v1/rootfolder')
    .optionally()
    .reply(200, [{ id: 1, path: '/lidarr-root-unused' }]);
  nock(LIDARR)
    .get(`/api/v1/track/${trackId}`)
    .times(times)
    .reply(200, makeTrack(trackId, trackFileId));
  nock(LIDARR)
    .get(`/api/v1/trackfile/${trackFileId}`)
    .times(times)
    .reply(200, makeTrackFile(trackFileId, filePath));
}

beforeAll(async () => {
  runMigrations();
  await bootstrapAdminIfNeeded();
  initTempDir();
  app = createApp();

  // Create per-run fixture directory and audio files.
  // Each transcoding test uses a distinct .flac filename so the sha256 hash (path+bitrate)
  // is unique and temp files do not leak between tests.
  fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bimusic-stream-test-'));
  fs.writeFileSync(path.join(fixtureDir, 'track.mp3'), FAKE_AUDIO);
  fs.writeFileSync(path.join(fixtureDir, 'transcode.flac'), Buffer.alloc(1024));
  fs.writeFileSync(path.join(fixtureDir, 'cached.flac'), Buffer.alloc(1024));
  fs.writeFileSync(path.join(fixtureDir, 'concurrent.flac'), Buffer.alloc(1024));

  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: 'adminpassword123' });
  token = res.body.accessToken as string;
});

afterEach(() => {
  nock.cleanAll();
  mockState.callCount = 0;
  mockState.delayMs = 0;
  resetLidarrRootCache();
  resetLidarrMetadataCache();
});

describe('GET /api/stream/:trackId — auth & validation', () => {
  it('returns 401 without Authorization header', async () => {
    const res = await request(app).get('/api/stream/1');
    expect(res.status).toBe(401);
  });

  it('returns 400 for unsupported bitrate value', async () => {
    const res = await request(app)
      .get('/api/stream/1?bitrate=256')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 400 for non-numeric bitrate', async () => {
    const res = await request(app)
      .get('/api/stream/1?bitrate=high')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });
});

describe('GET /api/stream/:trackId — MP3 passthrough', () => {
  const TRACK_ID = 10;
  const FILE_ID = 100;

  it('returns 200 with Accept-Ranges: bytes header', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.mp3'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.headers['accept-ranges']).toBe('bytes');
    expect(res.headers['content-type']).toMatch(/audio\/mpeg/);
  });

  it('returns 206 for Range request', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.mp3'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}`)
      .set('Authorization', `Bearer ${token}`)
      .set('Range', 'bytes=0-1023');

    expect(res.status).toBe(206);
    expect(res.headers['content-range']).toBe(`bytes 0-1023/${FAKE_AUDIO.length}`);
    expect(res.headers['accept-ranges']).toBe('bytes');
    expect(res.body).toBeInstanceOf(Buffer);
    expect((res.body as Buffer).length).toBe(1024);
  });

  it('does not invoke ffmpeg for MP3 source', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.mp3'));

    await request(app)
      .get(`/api/stream/${TRACK_ID}`)
      .set('Authorization', `Bearer ${token}`);

    expect(mockState.callCount).toBe(0);
  });
});

describe('GET /api/stream/:trackId — FLAC transcode', () => {
  const TRACK_ID = 20;
  const FILE_ID = 200;

  it('transcodes FLAC and returns 206 for Range request', async () => {
    // Uses transcode.flac — unique path so cached result doesn't collide with other tests.
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'transcode.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}?bitrate=128`)
      .set('Authorization', `Bearer ${token}`)
      .set('Range', 'bytes=0-511');

    expect(res.status).toBe(206);
    expect(res.headers['content-range']).toMatch(/^bytes 0-511\//);
    expect(mockState.callCount).toBe(1);
  });

  it('serves cached transcode without re-running ffmpeg on second request', async () => {
    // Uses cached.flac — unique path so this test's temp file doesn't collide with others.
    const flacPath = path.join(fixtureDir, 'cached.flac');

    // First request — transcodes.
    stubLidarr(TRACK_ID, FILE_ID, flacPath);
    await request(app)
      .get(`/api/stream/${TRACK_ID}?bitrate=320`)
      .set('Authorization', `Bearer ${token}`);
    expect(mockState.callCount).toBe(1);

    // Second request — should reuse cached temp file.
    stubLidarr(TRACK_ID, FILE_ID, flacPath);
    await request(app)
      .get(`/api/stream/${TRACK_ID}?bitrate=320`)
      .set('Authorization', `Bearer ${token}`);
    expect(mockState.callCount).toBe(1); // still 1
  });
});

describe('GET /api/stream/:trackId — concurrent deduplication', () => {
  const TRACK_ID = 30;
  const FILE_ID = 300;

  it('spawns only one ffmpeg process for concurrent requests to the same track', async () => {
    mockState.delayMs = 50; // slow transcode so both requests overlap

    // Uses concurrent.flac — unique path so cached result doesn't collide with other tests.
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'concurrent.flac'), 2);

    const [res1, res2] = await Promise.all([
      request(app)
        .get(`/api/stream/${TRACK_ID}?bitrate=128`)
        .set('Authorization', `Bearer ${token}`),
      request(app)
        .get(`/api/stream/${TRACK_ID}?bitrate=128`)
        .set('Authorization', `Bearer ${token}`),
    ]);

    expect(res1.status).toBe(200);
    expect(res2.status).toBe(200);
    expect(mockState.callCount).toBe(1);
  });
});

describe('GET /api/stream/:trackId — streamTranscoded fast-path', () => {
  const TRACK_ID = 40;
  const FILE_ID = 400;

  it('streams transcoded output to the client immediately (200, no Content-Length)', async () => {
    fs.writeFileSync(path.join(fixtureDir, 'stream-fast.flac'), Buffer.alloc(512));
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'stream-fast.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}?bitrate=128`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/audio\/mpeg/);
    expect(res.headers['accept-ranges']).toBe('none');
    // No Content-Length header for streaming response.
    expect(res.headers['content-length']).toBeUndefined();
    expect(mockState.callCount).toBe(1);
  });

  it('serves from disk cache on second request without re-running ffmpeg', async () => {
    fs.writeFileSync(path.join(fixtureDir, 'stream-cached2.flac'), Buffer.alloc(512));
    const flacPath = path.join(fixtureDir, 'stream-cached2.flac');

    stubLidarr(TRACK_ID, FILE_ID, flacPath);
    await request(app)
      .get(`/api/stream/${TRACK_ID}?bitrate=128`)
      .set('Authorization', `Bearer ${token}`);
    expect(mockState.callCount).toBe(1);

    // Second request — temp file now exists on disk.
    stubLidarr(TRACK_ID, FILE_ID, flacPath);
    const res2 = await request(app)
      .get(`/api/stream/${TRACK_ID}?bitrate=128`)
      .set('Authorization', `Bearer ${token}`);

    expect(res2.status).toBe(200);
    expect(mockState.callCount).toBe(1); // no new ffmpeg invocation
  });

  it('falls back to blocking ensureTranscoded path for non-trivial Range header', async () => {
    fs.writeFileSync(path.join(fixtureDir, 'stream-range.flac'), Buffer.alloc(512));
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'stream-range.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}?bitrate=128`)
      .set('Authorization', `Bearer ${token}`)
      .set('Range', 'bytes=100-511');

    // Blocking path writes the file then serves with Range support.
    expect(res.status).toBe(206);
    expect(res.headers['content-range']).toMatch(/^bytes 100-511\//);
    expect(mockState.callCount).toBe(1);
  });

  it('uses the streaming fast-path for open bytes=0- Range (libmpv probe)', async () => {
    fs.writeFileSync(path.join(fixtureDir, 'stream-probe.flac'), Buffer.alloc(512));
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'stream-probe.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}?bitrate=128`)
      .set('Authorization', `Bearer ${token}`)
      .set('Range', 'bytes=0-');

    expect(res.status).toBe(200);
    expect(res.headers['accept-ranges']).toBe('none');
    expect(mockState.callCount).toBe(1);
  });
});
