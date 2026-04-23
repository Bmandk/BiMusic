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
            fs.mkdirSync(path.dirname(outputPath), { recursive: true });
            fs.writeFileSync(outputPath, Buffer.alloc(10 * 1024)); // 10 KB fake MP3
            callbacks['end']?.();
          } catch (err) {
            callbacks['error']?.(err as Error);
          }
        }, 0);
      },
    };
    return chain;
  }),
}));

import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/db/migrate.js';
import { bootstrapAdminIfNeeded } from '../../src/services/userService.js';
import { resetLidarrRootCache } from '../../src/services/trackFileResolver.js';
import { initHlsCacheDir } from '../../src/services/hlsService.js';
import { processOnePendingDownload } from '../../src/services/downloadService.js';

const LIDARR = 'http://localhost:8686';
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
    quality: { quality: { id: 1, name: 'FLAC' } },
  };
}

function stubLidarr(trackId: number, trackFileId: number, filePath: string) {
  nock(LIDARR)
    .get('/api/v1/rootfolder')
    .optionally()
    .reply(200, [{ id: 1, path: '/lidarr-root-unused' }]);
  nock(LIDARR)
    .get(`/api/v1/track/${trackId}`)
    .reply(200, makeTrack(trackId, trackFileId));
  nock(LIDARR)
    .get(`/api/v1/trackfile/${trackFileId}`)
    .reply(200, makeTrackFile(trackFileId, filePath));
}

beforeAll(async () => {
  runMigrations();
  await bootstrapAdminIfNeeded();
  initHlsCacheDir();
  app = createApp();

  fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bimusic-download-test-'));
  fs.writeFileSync(path.join(fixtureDir, 'track1.flac'), Buffer.alloc(1024));
  fs.writeFileSync(path.join(fixtureDir, 'track2.flac'), Buffer.alloc(1024));
  fs.writeFileSync(path.join(fixtureDir, 'track3.flac'), Buffer.alloc(1024));

  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: 'adminpassword123' });
  token = res.body.accessToken as string;
});

afterEach(() => {
  nock.cleanAll();
  mockState.callCount = 0;
  resetLidarrRootCache();
});

describe('POST /api/downloads', () => {
  it('returns 401 without auth', async () => {
    const res = await request(app)
      .post('/api/downloads')
      .send({ trackId: 1, deviceId: 'device-a', bitrate: 320 });
    expect(res.status).toBe(401);
  });

  it('returns 400 for missing trackId', async () => {
    const res = await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ deviceId: 'device-a', bitrate: 320 });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('returns 400 for invalid bitrate', async () => {
    const res = await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ trackId: 1, deviceId: 'device-a', bitrate: 256 });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('creates a download record with pending status', async () => {
    const res = await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ trackId: 101, deviceId: 'device-a', bitrate: 320 });

    expect(res.status).toBe(201);
    expect(res.body.id).toBeDefined();
    expect(res.body.lidarrTrackId).toBe(101);
    expect(res.body.deviceId).toBe('device-a');
    expect(res.body.bitrate).toBe(320);
    expect(res.body.status).toBe('pending');
    expect(res.body.requestedAt).toBeDefined();
    expect(res.body.filePath).toBeNull();
  });

  it('returns existing record if already requested', async () => {
    const first = await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ trackId: 102, deviceId: 'device-b', bitrate: 320 });
    expect(first.status).toBe(201);

    const second = await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ trackId: 102, deviceId: 'device-b', bitrate: 320 });
    expect(second.status).toBe(201);
    expect(second.body.id).toBe(first.body.id);
  });
});

describe('GET /api/downloads', () => {
  it('returns 401 without auth', async () => {
    const res = await request(app).get('/api/downloads?deviceId=device-x');
    expect(res.status).toBe(401);
  });

  it('returns 400 without deviceId', async () => {
    const res = await request(app)
      .get('/api/downloads')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('lists downloads for user and device', async () => {
    // Create a download for device-list
    await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ trackId: 201, deviceId: 'device-list', bitrate: 128 });

    const res = await request(app)
      .get('/api/downloads?deviceId=device-list')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    const record = (res.body as { lidarrTrackId: number }[]).find((r) => r.lidarrTrackId === 201);
    expect(record).toBeDefined();
  });
});

describe('DELETE /api/downloads/:id', () => {
  it('returns 401 without auth', async () => {
    const res = await request(app).delete('/api/downloads/some-id');
    expect(res.status).toBe(401);
  });

  it('returns 404 for non-existent id', async () => {
    const res = await request(app)
      .delete('/api/downloads/nonexistent-id')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('deletes a download record and returns 204', async () => {
    const createRes = await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ trackId: 301, deviceId: 'device-del', bitrate: 320 });
    expect(createRes.status).toBe(201);
    const id = createRes.body.id as string;

    const delRes = await request(app)
      .delete(`/api/downloads/${id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(delRes.status).toBe(204);

    // Should no longer appear in list
    const listRes = await request(app)
      .get('/api/downloads?deviceId=device-del')
      .set('Authorization', `Bearer ${token}`);
    const ids = (listRes.body as { id: string }[]).map((r) => r.id);
    expect(ids).not.toContain(id);
  });
});

describe('Background worker + GET /api/downloads/:id/file', () => {
  it('processes a pending download and serves the file', async () => {
    const TRACK_ID = 401;
    const TRACK_FILE_ID = 4001;
    const filePath = path.join(fixtureDir, 'track1.flac');

    // Request the download
    const createRes = await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ trackId: TRACK_ID, deviceId: 'device-worker', bitrate: 320 });
    expect(createRes.status).toBe(201);
    const id = createRes.body.id as string;
    expect(createRes.body.status).toBe('pending');

    // Stub pre-existing pending records from earlier tests (101, 102, 201) to 404 so
    // the worker drains them quickly before reaching track 401.
    nock(LIDARR).get('/api/v1/track/101').reply(404, { message: 'Not Found' });
    nock(LIDARR).get('/api/v1/track/102').reply(404, { message: 'Not Found' });
    nock(LIDARR).get('/api/v1/track/201').reply(404, { message: 'Not Found' });

    // Stub Lidarr for the worker to resolve the file path for track 401
    stubLidarr(TRACK_ID, TRACK_FILE_ID, filePath);

    // Process all 4 pending records: 3 pre-existing fail, ours (401) succeeds
    await processOnePendingDownload(); // 101 → 404 → failed
    await processOnePendingDownload(); // 102 → 404 → failed
    await processOnePendingDownload(); // 201 → 404 → failed
    await processOnePendingDownload(); // 401 → transcoded → ready

    expect(mockState.callCount).toBe(1);

    // Serve the file
    const fileRes = await request(app)
      .get(`/api/downloads/${id}/file`)
      .set('Authorization', `Bearer ${token}`);

    expect(fileRes.status).toBe(200);
    expect(fileRes.headers['content-disposition']).toContain('attachment');
    expect(fileRes.headers['content-disposition']).toContain(`${TRACK_ID}-320.mp3`);
  });

  it('returns 409 when file is not yet ready', async () => {
    const createRes = await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ trackId: 402, deviceId: 'device-notready', bitrate: 320 });
    expect(createRes.status).toBe(201);
    const id = createRes.body.id as string;

    // Don't run the worker — status remains 'pending'
    const fileRes = await request(app)
      .get(`/api/downloads/${id}/file`)
      .set('Authorization', `Bearer ${token}`);

    expect(fileRes.status).toBe(409);
    expect(fileRes.body.error.code).toBe('NOT_READY');
  });

  it('returns 404 for another user trying to fetch the file', async () => {
    // Create a second user
    await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${token}`)
      .send({ username: 'dluser2', password: 'dluser2password', isAdmin: false });
    const user2Res = await request(app)
      .post('/api/auth/login')
      .send({ username: 'dluser2', password: 'dluser2password' });
    const user2Token = user2Res.body.accessToken as string;

    // Create download as admin
    const createRes = await request(app)
      .post('/api/downloads')
      .set('Authorization', `Bearer ${token}`)
      .send({ trackId: 501, deviceId: 'device-owner', bitrate: 320 });
    expect(createRes.status).toBe(201);
    const id = createRes.body.id as string;

    // Try to fetch as user2
    const fileRes = await request(app)
      .get(`/api/downloads/${id}/file`)
      .set('Authorization', `Bearer user2Token`);
    // user2Token is not a valid JWT string — should get 401
    expect(fileRes.status).toBe(401);

    // Use a valid but different user token
    const fileRes2 = await request(app)
      .get(`/api/downloads/${id}/file`)
      .set('Authorization', `Bearer ${user2Token}`);
    expect(fileRes2.status).toBe(404);
  });
});
