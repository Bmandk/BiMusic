// tests/setup.ts sets env vars before this file loads (via vitest setupFiles)
import { beforeAll, afterEach, describe, it, expect } from 'vitest';
import request from 'supertest';
import nock from 'nock';
import type { Express } from 'express';
import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/db/migrate.js';
import { bootstrapAdminIfNeeded } from '../../src/services/userService.js';

const LIDARR = 'http://localhost:8686';

let app: Express;
let token: string;

const stubArtist = {
  id: 42,
  artistName: 'The Beatles',
  foreignArtistId: 'fab4-1234',
  overview: 'Legendary band',
  artistType: 'Group',
  status: 'ended',
  ended: true,
  images: [{ url: '/MediaCover/artist/42/poster.jpg', coverType: 'poster', extension: '.jpg', remoteUrl: null }],
  path: '/music/the-beatles',
  monitored: true,
  genres: ['Rock'],
  sortName: 'beatles',
  ratings: { votes: 500, value: 9.5 },
  statistics: { trackFileCount: 0 },
};

const stubAlbum = {
  id: 99,
  title: 'Abbey Road',
  disambiguation: null,
  overview: null,
  artistId: 42,
  foreignAlbumId: 'abbey-road-mbid',
  monitored: true,
  duration: 2700000,
  albumType: 'Album',
  releaseDate: '1969-09-26',
  artist: stubArtist,
  images: [],
  genres: ['Rock'],
  ratings: { votes: 200, value: 9.8 },
  remoteCover: null,
  statistics: { trackFileCount: 0 },
};

const stubCommand = {
  id: 1,
  name: 'ArtistSearch',
  commandName: 'ArtistSearch',
  status: 'queued',
  queued: new Date().toISOString(),
  started: null,
  ended: null,
};

beforeAll(async () => {
  nock.disableNetConnect();
  nock.enableNetConnect('127.0.0.1');

  runMigrations();
  await bootstrapAdminIfNeeded();
  app = createApp();

  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: 'adminpassword123' });
  token = res.body.accessToken as string;
});

afterEach(() => {
  nock.cleanAll();
});

describe('GET /api/requests/search', () => {
  it('returns artists and albums from Lidarr lookup', async () => {
    nock(LIDARR).get('/api/v1/artist/lookup').query({ term: 'beatles' }).reply(200, [stubArtist]);
    nock(LIDARR).get('/api/v1/album/lookup').query({ term: 'beatles' }).reply(200, [stubAlbum]);

    const res = await request(app)
      .get('/api/requests/search?term=beatles')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.artists)).toBe(true);
    expect(Array.isArray(res.body.albums)).toBe(true);
    expect(res.body.artists[0]).toMatchObject({ id: 42, artistName: 'The Beatles' });
    expect(res.body.albums[0]).toMatchObject({ id: 99, title: 'Abbey Road' });
  });

  it('returns 400 when term is missing', async () => {
    const res = await request(app)
      .get('/api/requests/search')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 401 without auth', async () => {
    const res = await request(app).get('/api/requests/search?term=beatles');
    expect(res.status).toBe(401);
  });
});

describe('POST /api/requests/artist', () => {
  it('adds artist to Lidarr, triggers ArtistSearch, and creates a request record', async () => {
    nock(LIDARR).post('/api/v1/artist').reply(201, stubArtist);
    nock(LIDARR).post('/api/v1/command').reply(201, stubCommand);

    const res = await request(app)
      .post('/api/requests/artist')
      .set('Authorization', `Bearer ${token}`)
      .send({
        foreignArtistId: 'fab4-1234',
        artistName: 'The Beatles',
        qualityProfileId: 1,
        metadataProfileId: 1,
        rootFolderPath: '/music',
      });

    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({
      type: 'artist',
      lidarrId: 42,
      status: 'pending',
    });
    expect(typeof res.body.id).toBe('string');
    expect(typeof res.body.requestedAt).toBe('string');
    expect(res.body.resolvedAt).toBeNull();
  });

  it('returns 400 when required fields are missing', async () => {
    const res = await request(app)
      .post('/api/requests/artist')
      .set('Authorization', `Bearer ${token}`)
      .send({ artistName: 'Bad Request' });

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });
});

describe('POST /api/requests/album', () => {
  it('monitors album in Lidarr, triggers AlbumSearch, and creates a request record', async () => {
    nock(LIDARR).put('/api/v1/album/monitor').reply(200, {});
    nock(LIDARR).post('/api/v1/command').reply(201, { ...stubCommand, name: 'AlbumSearch' });

    const res = await request(app)
      .post('/api/requests/album')
      .set('Authorization', `Bearer ${token}`)
      .send({ albumId: 99 });

    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({
      type: 'album',
      lidarrId: 99,
      status: 'pending',
    });
    expect(typeof res.body.id).toBe('string');
  });

  it('returns 400 when albumId is missing', async () => {
    const res = await request(app)
      .post('/api/requests/album')
      .set('Authorization', `Bearer ${token}`)
      .send({});

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });
});

describe('GET /api/requests', () => {
  it('returns empty array when no requests exist for a fresh user', async () => {
    // Create a fresh user via admin endpoint to get a clean slate
    await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${token}`)
      .send({ username: 'freshuser', password: 'freshpassword123' });

    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ username: 'freshuser', password: 'freshpassword123' });
    const freshToken = loginRes.body.accessToken as string;

    nock(LIDARR).get('/api/v1/queue').reply(200, []);

    const res = await request(app)
      .get('/api/requests')
      .set('Authorization', `Bearer ${freshToken}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  it('returns pending requests and updates status to available when trackFileCount > 0', async () => {
    // First create an artist request
    nock(LIDARR).post('/api/v1/artist').reply(201, stubArtist);
    nock(LIDARR).post('/api/v1/command').reply(201, stubCommand);

    await request(app)
      .post('/api/requests/artist')
      .set('Authorization', `Bearer ${token}`)
      .send({
        foreignArtistId: 'fab4-1234',
        artistName: 'The Beatles',
        qualityProfileId: 1,
        metadataProfileId: 1,
        rootFolderPath: '/music',
      });

    // Now GET /requests — Lidarr reports trackFileCount > 0
    nock(LIDARR).get('/api/v1/queue').reply(200, []);
    nock(LIDARR)
      .get('/api/v1/artist/42')
      .reply(200, { ...stubArtist, statistics: { trackFileCount: 5 } });

    const res = await request(app)
      .get('/api/requests')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    const artistRequest = res.body.find((r: { type: string; lidarrId: number }) => r.type === 'artist' && r.lidarrId === 42);
    expect(artistRequest).toBeDefined();
    expect(artistRequest.status).toBe('available');
    expect(typeof artistRequest.resolvedAt).toBe('string');
  });

  it('updates status to downloading when album is in Lidarr queue', async () => {
    // Create an album request
    nock(LIDARR).put('/api/v1/album/monitor').reply(200, {});
    nock(LIDARR).post('/api/v1/command').reply(201, { ...stubCommand, name: 'AlbumSearch' });

    await request(app)
      .post('/api/requests/album')
      .set('Authorization', `Bearer ${token}`)
      .send({ albumId: 77 });

    // GET /requests — album is in queue but trackFileCount is 0
    nock(LIDARR)
      .get('/api/v1/queue')
      .reply(200, [{ id: 5, artistId: 42, albumId: 77, title: 'Downloading', size: 1000, sizeleft: 500, status: 'downloading', trackedDownloadStatus: 'ok', errorMessage: null }]);
    nock(LIDARR)
      .get('/api/v1/album/77')
      .reply(200, { ...stubAlbum, id: 77, statistics: { trackFileCount: 0 } });

    const res = await request(app)
      .get('/api/requests')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    const albumRequest = res.body.find((r: { type: string; lidarrId: number }) => r.type === 'album' && r.lidarrId === 77);
    expect(albumRequest).toBeDefined();
    expect(albumRequest.status).toBe('downloading');
  });
});
