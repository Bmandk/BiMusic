// tests/setup.ts sets env vars before this file loads (via vitest setupFiles)
import { beforeAll, describe, it, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/db/migrate.js';
import { bootstrapAdminIfNeeded } from '../../src/services/userService.js';

let app: Express;
let adminToken: string;
let user2Token: string;

const ADMIN = { username: 'admin', password: 'adminpassword123' };

beforeAll(async () => {
  runMigrations();
  await bootstrapAdminIfNeeded();
  app = createApp();

  // Log in as admin
  const adminRes = await request(app).post('/api/auth/login').send(ADMIN);
  adminToken = adminRes.body.accessToken as string;

  // Create a second user
  await request(app)
    .post('/api/users')
    .set('Authorization', `Bearer ${adminToken}`)
    .send({ username: 'user2', password: 'user2password123', isAdmin: false });

  const user2Res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'user2', password: 'user2password123' });
  user2Token = user2Res.body.accessToken as string;
});

describe('POST /api/playlists', () => {
  it('creates a playlist and returns 201', async () => {
    const res = await request(app)
      .post('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'My Playlist' });
    expect(res.status).toBe(201);
    expect(res.body.id).toBeDefined();
    expect(res.body.name).toBe('My Playlist');
    expect(res.body.createdAt).toBeDefined();
  });

  it('returns 400 for missing name', async () => {
    const res = await request(app)
      .post('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({});
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('returns 401 without auth', async () => {
    const res = await request(app).post('/api/playlists').send({ name: 'Test' });
    expect(res.status).toBe(401);
  });
});

describe('GET /api/playlists', () => {
  it('returns only the authenticated user playlists', async () => {
    // admin creates a playlist
    await request(app)
      .post('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Admin Playlist' });

    const res = await request(app)
      .get('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    // Every returned playlist should have the expected fields
    for (const p of res.body as { id: string; name: string; trackCount: number; createdAt: string }[]) {
      expect(p.id).toBeDefined();
      expect(p.name).toBeDefined();
      expect(typeof p.trackCount).toBe('number');
      expect(p.createdAt).toBeDefined();
    }
  });

  it('user2 sees empty list initially', async () => {
    const res = await request(app)
      .get('/api/playlists')
      .set('Authorization', `Bearer ${user2Token}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });
});

describe('GET /api/playlists/:id', () => {
  let playlistId: string;

  beforeAll(async () => {
    const res = await request(app)
      .post('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Detail Test' });
    playlistId = res.body.id as string;
  });

  it('returns playlist with tracks array', async () => {
    const res = await request(app)
      .get(`/api/playlists/${playlistId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(playlistId);
    expect(res.body.name).toBe('Detail Test');
    expect(Array.isArray(res.body.tracks)).toBe(true);
  });

  it('returns 404 for nonexistent playlist', async () => {
    const res = await request(app)
      .get('/api/playlists/nonexistent-id')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(404);
  });

  it('returns 404 when another user requests the playlist', async () => {
    const res = await request(app)
      .get(`/api/playlists/${playlistId}`)
      .set('Authorization', `Bearer ${user2Token}`);
    expect(res.status).toBe(404);
  });
});

describe('PUT /api/playlists/:id', () => {
  let playlistId: string;

  beforeAll(async () => {
    const res = await request(app)
      .post('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Update Test' });
    playlistId = res.body.id as string;
  });

  it('updates playlist name', async () => {
    const res = await request(app)
      .put(`/api/playlists/${playlistId}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Updated Name' });
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(playlistId);
    expect(res.body.name).toBe('Updated Name');
    expect(res.body.updatedAt).toBeDefined();
  });

  it('returns 404 when another user tries to update', async () => {
    const res = await request(app)
      .put(`/api/playlists/${playlistId}`)
      .set('Authorization', `Bearer ${user2Token}`)
      .send({ name: 'Hacked' });
    expect(res.status).toBe(404);
  });
});

describe('Track management', () => {
  let playlistId: string;

  beforeAll(async () => {
    const res = await request(app)
      .post('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Track Test Playlist' });
    playlistId = res.body.id as string;
  });

  it('adds tracks to playlist', async () => {
    const res = await request(app)
      .post(`/api/playlists/${playlistId}/tracks`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ trackIds: [101, 102, 103] });
    expect(res.status).toBe(200);
    expect(res.body.added).toBe(3);
  });

  it('tracks appear in order after adding', async () => {
    const res = await request(app)
      .get(`/api/playlists/${playlistId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    const tracks = res.body.tracks as { lidarrTrackId: number; position: number }[];
    expect(tracks).toHaveLength(3);
    expect(tracks[0]!.lidarrTrackId).toBe(101);
    expect(tracks[1]!.lidarrTrackId).toBe(102);
    expect(tracks[2]!.lidarrTrackId).toBe(103);
    expect(tracks[0]!.position).toBe(0);
    expect(tracks[1]!.position).toBe(1);
    expect(tracks[2]!.position).toBe(2);
  });

  it('trackCount reflects added tracks', async () => {
    const res = await request(app)
      .get('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`);
    const pl = (res.body as { id: string; trackCount: number }[]).find((p) => p.id === playlistId);
    expect(pl?.trackCount).toBe(3);
  });

  it('reorders tracks', async () => {
    const res = await request(app)
      .put(`/api/playlists/${playlistId}/tracks/reorder`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ trackIds: [103, 101, 102] });
    expect(res.status).toBe(200);

    const detail = await request(app)
      .get(`/api/playlists/${playlistId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    const tracks = detail.body.tracks as { lidarrTrackId: number; position: number }[];
    expect(tracks[0]!.lidarrTrackId).toBe(103);
    expect(tracks[1]!.lidarrTrackId).toBe(101);
    expect(tracks[2]!.lidarrTrackId).toBe(102);
  });

  it('removes a track and repacks positions', async () => {
    const res = await request(app)
      .delete(`/api/playlists/${playlistId}/tracks/101`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(204);

    const detail = await request(app)
      .get(`/api/playlists/${playlistId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    const tracks = detail.body.tracks as { lidarrTrackId: number; position: number }[];
    expect(tracks).toHaveLength(2);
    expect(tracks[0]!.position).toBe(0);
    expect(tracks[1]!.position).toBe(1);
  });

  it('returns 404 when removing a track not in playlist', async () => {
    const res = await request(app)
      .delete(`/api/playlists/${playlistId}/tracks/999`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(404);
  });

  it('returns 400 for reorder with unknown track', async () => {
    const res = await request(app)
      .put(`/api/playlists/${playlistId}/tracks/reorder`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ trackIds: [103, 102, 999] });
    expect(res.status).toBe(400);
  });

  it('returns 404 when another user tries to add tracks', async () => {
    const res = await request(app)
      .post(`/api/playlists/${playlistId}/tracks`)
      .set('Authorization', `Bearer ${user2Token}`)
      .send({ trackIds: [200] });
    expect(res.status).toBe(404);
  });
});

describe('DELETE /api/playlists/:id', () => {
  it('deletes a playlist', async () => {
    const create = await request(app)
      .post('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'To Delete' });
    const id = create.body.id as string;

    const del = await request(app)
      .delete(`/api/playlists/${id}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(del.status).toBe(204);

    const get = await request(app)
      .get(`/api/playlists/${id}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(get.status).toBe(404);
  });

  it('returns 404 when another user tries to delete', async () => {
    const create = await request(app)
      .post('/api/playlists')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Protected' });
    const id = create.body.id as string;

    const del = await request(app)
      .delete(`/api/playlists/${id}`)
      .set('Authorization', `Bearer ${user2Token}`);
    expect(del.status).toBe(404);
  });
});
