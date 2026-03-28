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
  id: 1,
  artistName: 'Test Artist',
  foreignArtistId: 'abc123',
  overview: 'An overview',
  artistType: 'Person',
  status: 'continuing',
  ended: false,
  images: [{ url: '/MediaCover/artist/1/poster.jpg', coverType: 'poster', extension: '.jpg', remoteUrl: null }],
  path: '/music/test-artist',
  monitored: true,
  genres: ['Rock'],
  sortName: 'test artist',
  ratings: { votes: 100, value: 4.5 },
};

const stubAlbum = {
  id: 10,
  title: 'Test Album',
  disambiguation: null,
  overview: 'Album overview',
  artistId: 1,
  foreignAlbumId: 'alb456',
  monitored: true,
  duration: 3600000,
  albumType: 'Album',
  releaseDate: '2023-06-01',
  artist: stubArtist,
  images: [{ url: '/MediaCover/album/10/cover.jpg', coverType: 'cover', extension: '.jpg', remoteUrl: null }],
  genres: ['Rock'],
  ratings: { votes: 50, value: 7.5 },
  remoteCover: null,
};

const stubTrack = {
  id: 100,
  artistId: 1,
  albumId: 10,
  trackFileId: 200,
  foreignTrackId: 'trk789',
  trackNumber: '1',
  absoluteTrackNumber: 1,
  title: 'Test Track',
  duration: 240000,
  hasFile: true,
  explicit: false,
  mediumNumber: 1,
  trackFile: null,
  artist: stubArtist,
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

describe('GET /api/library/artists', () => {
  it('returns a shaped artist array with albumCount', async () => {
    nock(LIDARR).get('/api/v1/artist').reply(200, [stubArtist]);
    nock(LIDARR).get('/api/v1/album').reply(200, [stubAlbum]);

    const res = await request(app)
      .get('/api/library/artists')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body).toHaveLength(1);
    expect(res.body[0]).toMatchObject({
      id: 1,
      name: 'Test Artist',
      overview: 'An overview',
      albumCount: 1,
    });
    expect(res.body[0].imageUrl).toContain('/api/library/artists/1/image');
  });

  it('returns 401 without a token', async () => {
    const res = await request(app).get('/api/library/artists');
    expect(res.status).toBe(401);
  });
});

describe('GET /api/library/artists/:id', () => {
  it('returns a single artist with imageUrl pointing to the BiMusic proxy', async () => {
    nock(LIDARR).get('/api/v1/artist/1').reply(200, stubArtist);
    nock(LIDARR).get('/api/v1/album').query({ artistId: '1' }).reply(200, [stubAlbum]);

    const res = await request(app)
      .get('/api/library/artists/1')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.id).toBe(1);
    expect(res.body.name).toBe('Test Artist');
    expect(res.body.albumCount).toBe(1);
    expect(res.body.imageUrl).toMatch(/\/api\/library\/artists\/1\/image$/);
  });

  it('returns 404 when Lidarr reports the artist as not found', async () => {
    nock(LIDARR).get('/api/v1/artist/999').reply(404);
    nock(LIDARR).get('/api/v1/album').query({ artistId: '999' }).reply(200, []);

    const res = await request(app)
      .get('/api/library/artists/999')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(404);
  });
});

describe('GET /api/library/artists/:id/albums', () => {
  it('returns shaped albums for the artist', async () => {
    nock(LIDARR).get('/api/v1/album').query({ artistId: '1' }).reply(200, [stubAlbum]);

    const res = await request(app)
      .get('/api/library/artists/1/albums')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
    expect(res.body[0]).toMatchObject({
      id: 10,
      title: 'Test Album',
      artistId: 1,
      artistName: 'Test Artist',
      releaseDate: '2023-06-01',
    });
    expect(res.body[0].imageUrl).toContain('/api/library/albums/10/image');
  });
});

describe('GET /api/library/albums/:id', () => {
  it('returns a shaped album with trackCount', async () => {
    nock(LIDARR).get('/api/v1/album/10').reply(200, stubAlbum);
    nock(LIDARR).get('/api/v1/track').query({ albumId: '10' }).reply(200, [stubTrack]);

    const res = await request(app)
      .get('/api/library/albums/10')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      id: 10,
      title: 'Test Album',
      artistId: 1,
      trackCount: 1,
      duration: 3600000,
    });
  });
});

describe('GET /api/library/albums/:id/tracks', () => {
  it('returns shaped tracks with streamUrl', async () => {
    nock(LIDARR).get('/api/v1/track').query({ albumId: '10' }).reply(200, [stubTrack]);

    const res = await request(app)
      .get('/api/library/albums/10/tracks')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
    expect(res.body[0]).toMatchObject({
      id: 100,
      title: 'Test Track',
      trackNumber: '1',
      duration: 240000,
      albumId: 10,
      artistId: 1,
      hasFile: true,
    });
    expect(res.body[0].streamUrl).toContain('/api/stream/100');
  });
});

describe('GET /api/library/tracks/:id', () => {
  it('returns a single shaped track', async () => {
    nock(LIDARR).get('/api/v1/track/100').reply(200, stubTrack);

    const res = await request(app)
      .get('/api/library/tracks/100')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.id).toBe(100);
    expect(res.body.streamUrl).toContain('/api/stream/100');
  });
});

describe('GET /api/library/artists/:id/image', () => {
  it('proxies the artist image stream with the correct Content-Type', async () => {
    nock(LIDARR).get('/api/v1/artist/1').reply(200, stubArtist);
    nock(LIDARR)
      .get('/api/v1/mediacover/artist/1/poster.jpg')
      .reply(200, Buffer.from('fake-image'), { 'Content-Type': 'image/jpeg' });

    const res = await request(app)
      .get('/api/library/artists/1/image')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/image\/jpeg/);
  });
});

describe('GET /api/library/albums/:id/image', () => {
  it('proxies the album cover stream with the correct Content-Type', async () => {
    nock(LIDARR).get('/api/v1/album/10').reply(200, stubAlbum);
    nock(LIDARR)
      .get('/api/v1/mediacover/album/10/cover.jpg')
      .reply(200, Buffer.from('fake-cover'), { 'Content-Type': 'image/jpeg' });

    const res = await request(app)
      .get('/api/library/albums/10/image')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/image\/jpeg/);
  });
});

describe('GET /api/search', () => {
  it('returns artists and albums grouped from Lidarr search results', async () => {
    const searchResult = { id: 1, foreignId: 'f1', artist: stubArtist, album: stubAlbum };
    nock(LIDARR).get('/api/v1/search').query({ term: 'test' }).reply(200, [searchResult]);

    const res = await request(app)
      .get('/api/search?term=test')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.artists).toHaveLength(1);
    expect(res.body.artists[0].id).toBe(1);
    expect(res.body.albums).toHaveLength(1);
    expect(res.body.albums[0].id).toBe(10);
  });

  it('returns 400 when term is missing', async () => {
    const res = await request(app)
      .get('/api/search')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });
});
