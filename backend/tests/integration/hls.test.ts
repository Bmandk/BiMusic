// tests/setup.ts sets env vars before this file loads (via vitest setupFiles)
import { vi, describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
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
  default: vi.fn((_src?: string) => {
    mockState.callCount++;
    let outputPath = '';
    const callbacks: Record<string, (...args: unknown[]) => void> = {};

    const chain = {
      input: (_p: string) => chain,
      seekInput: (_n: number) => chain,
      noVideo: () => chain,
      audioCodec: (_c: string) => chain,
      audioBitrate: (_b: number) => chain,
      duration: (_d: number) => chain,
      outputOptions: (_opts: string[]) => chain,
      format: (_f: string) => chain,
      kill: (_signal: string) => {},
      output: (p: string) => {
        outputPath = p;
        return chain;
      },
      on: (event: string, cb: (...args: unknown[]) => void) => {
        callbacks[event] = cb;
        return chain;
      },
      run: () => {
        setTimeout(() => {
          try {
            // Write a fake .ts payload to the .part path, then fire end.
            fs.mkdirSync(path.dirname(outputPath), { recursive: true });
            fs.writeFileSync(outputPath, Buffer.alloc(512, 0xaa)); // fake TS bytes
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
import { initHlsCacheDir } from '../../src/services/hlsService.js';
import { resetLidarrRootCache } from '../../src/services/trackFileResolver.js';
import { resetLidarrMetadataCache } from '../../src/services/lidarrClient.js';

const LIDARR = 'http://localhost:8686';

// Track duration: 240 seconds = 240000 ms
// Segment length: 6 s
// Expected segments: ceil(240000 / 6000) = 40
const TRACK_DURATION_MS = 240000;
const SEGMENT_COUNT = 40;

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
    duration: TRACK_DURATION_MS,
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
    size: 1024,
    dateAdded: new Date().toISOString(),
    quality: { quality: { id: 1, name: 'FLAC' } },
  };
}

function stubLidarr(
  trackId: number,
  trackFileId: number,
  filePath: string,
  times = 1,
) {
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
  initHlsCacheDir();
  app = createApp();

  fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bimusic-hls-test-'));
  fs.writeFileSync(path.join(fixtureDir, 'track.flac'), Buffer.alloc(1024));
  fs.writeFileSync(path.join(fixtureDir, 'track2.flac'), Buffer.alloc(1024));
  fs.writeFileSync(path.join(fixtureDir, 'track3.flac'), Buffer.alloc(1024));

  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: 'adminpassword123' });
  token = res.body.accessToken as string;
});

afterAll(() => {
  try {
    fs.rmSync(fixtureDir, { recursive: true, force: true });
  } catch { /* ignore */ }
});

afterEach(() => {
  nock.cleanAll();
  mockState.callCount = 0;
  mockState.delayMs = 0;
  resetLidarrRootCache();
  resetLidarrMetadataCache();
});

// ────────────────────────────────────────────────────
// Auth & validation
// ────────────────────────────────────────────────────

describe('GET /api/stream/:id/playlist — auth & validation', () => {
  it('returns 401 without Authorization header', async () => {
    const res = await request(app).get('/api/stream/1/playlist');
    expect(res.status).toBe(401);
  });

  it('returns 400 for invalid bitrate', async () => {
    const res = await request(app)
      .get('/api/stream/1/playlist?bitrate=256')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 400 for non-numeric bitrate', async () => {
    const res = await request(app)
      .get('/api/stream/1/playlist?bitrate=high')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('GET /api/stream/:id/playlist.m3u8 — auth & validation', () => {
  it('returns 401 without Authorization header', async () => {
    const res = await request(app).get('/api/stream/1/playlist.m3u8');
    expect(res.status).toBe(401);
  });

  it('returns 400 for invalid bitrate', async () => {
    const res = await request(app)
      .get('/api/stream/1/playlist.m3u8?bitrate=256')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });
});

describe('GET /api/stream/:id/segment/:index — auth & validation', () => {
  it('returns 401 without Authorization header', async () => {
    const res = await request(app).get('/api/stream/1/segment/000');
    expect(res.status).toBe(401);
  });

  it('returns 400 for invalid bitrate', async () => {
    const flacPath = path.join(fixtureDir, 'track.flac');
    stubLidarr(1, 11, flacPath);
    const res = await request(app)
      .get('/api/stream/1/segment/000?bitrate=256')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

// ────────────────────────────────────────────────────
// Playlist happy path
// ────────────────────────────────────────────────────

describe('GET /api/stream/:id/playlist — happy path', () => {
  const TRACK_ID = 10;
  const FILE_ID = 100;

  it('returns 200 with correct Content-Type', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/playlist?bitrate=128&token=mytoken`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/application\/vnd\.apple\.mpegurl/);
  });

  it('returns a valid HLS playlist with #EXTM3U and #EXT-X-ENDLIST', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/playlist?bitrate=128&token=mytoken`)
      .set('Authorization', `Bearer ${token}`);

    const body = res.text;
    expect(body).toMatch(/^#EXTM3U/);
    expect(body).toContain('#EXT-X-ENDLIST');
  });

  it(`emits ${SEGMENT_COUNT} segments for a ${TRACK_DURATION_MS / 1000}s track`, async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/playlist?bitrate=128&token=mytoken`)
      .set('Authorization', `Bearer ${token}`);

    const extinf = (res.text.match(/#EXTINF:/g) ?? []).length;
    expect(extinf).toBe(SEGMENT_COUNT);
  });

  it('embeds the query token into segment URIs', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/playlist?bitrate=128&token=secretjwt`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.text).toContain('token=secretjwt');
  });

  it('sets Cache-Control: no-store', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/playlist?bitrate=128&token=mytoken`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.headers['cache-control']).toBe('no-store');
  });
});

// ────────────────────────────────────────────────────
// playlist.m3u8 alias (ExoPlayer / Android HLS detection)
// ────────────────────────────────────────────────────

describe('GET /api/stream/:id/playlist.m3u8 — happy path', () => {
  const TRACK_ID = 11;
  const FILE_ID = 111;

  it('returns 200 with correct Content-Type', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/playlist.m3u8?bitrate=128&token=mytoken`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/application\/vnd\.apple\.mpegurl/);
  });

  it('returns a valid HLS playlist', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/playlist.m3u8?bitrate=128&token=mytoken`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.text).toMatch(/^#EXTM3U/);
    expect(res.text).toContain('#EXT-X-ENDLIST');
  });
});

// ────────────────────────────────────────────────────
// Segment happy path
// ────────────────────────────────────────────────────

describe('GET /api/stream/:id/segment/:index — happy path', () => {
  const TRACK_ID = 20;
  const FILE_ID = 200;

  it('returns 200 with Content-Type: audio/mpeg', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track2.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/segment/000?bitrate=128`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/audio\/mpeg/);
  });

  it('returns non-empty body (fake MP3 payload from mock ffmpeg)', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track2.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/segment/000?bitrate=128`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.body).toBeInstanceOf(Buffer);
    expect((res.body as Buffer).length).toBeGreaterThan(0);
  });

  it('serves from cache on second request without re-running ffmpeg', async () => {
    const flacPath = path.join(fixtureDir, 'track3.flac');

    stubLidarr(TRACK_ID, FILE_ID, flacPath);
    await request(app)
      .get(`/api/stream/${TRACK_ID}/segment/000?bitrate=320`)
      .set('Authorization', `Bearer ${token}`);
    expect(mockState.callCount).toBe(1);

    stubLidarr(TRACK_ID, FILE_ID, flacPath);
    const res2 = await request(app)
      .get(`/api/stream/${TRACK_ID}/segment/000?bitrate=320`)
      .set('Authorization', `Bearer ${token}`);

    expect(res2.status).toBe(200);
    expect(mockState.callCount).toBe(1); // no new ffmpeg invocation
  });
});

// ────────────────────────────────────────────────────
// Segment index validation
// ────────────────────────────────────────────────────

describe('GET /api/stream/:id/segment/:index — index validation', () => {
  const TRACK_ID = 30;
  const FILE_ID = 300;

  it('returns 400 when segment index >= segmentCount', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.flac'));

    // segmentCount = ceil(240000 / 6000) = 40; index 40 is out-of-range
    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/segment/040?bitrate=128`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 400 for a very large index', async () => {
    stubLidarr(TRACK_ID, FILE_ID, path.join(fixtureDir, 'track.flac'));

    const res = await request(app)
      .get(`/api/stream/${TRACK_ID}/segment/999?bitrate=128`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(400);
  });
});

