// tests/setup.ts sets env vars before this file loads (via vitest setupFiles)
import { beforeAll, describe, it, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/db/migrate.js';
import { bootstrapAdminIfNeeded } from '../../src/services/userService.js';

let app: Express;
let adminToken: string;

const ADMIN = { username: 'admin', password: 'adminpassword123' };

beforeAll(async () => {
  runMigrations();
  await bootstrapAdminIfNeeded();
  app = createApp();

  const res = await request(app).post('/api/auth/login').send(ADMIN);
  adminToken = res.body.accessToken as string;
});

describe('GET /api/users', () => {
  it('returns the user list for admin', async () => {
    const res = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${adminToken}`);

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThanOrEqual(1);
    expect(res.body[0]).toHaveProperty('username');
    expect(res.body[0]).not.toHaveProperty('passwordHash');
  });

  it('returns 401 without token', async () => {
    const res = await request(app).get('/api/users');
    expect(res.status).toBe(401);
  });
});

describe('POST /api/users', () => {
  it('creates a new user and returns 201', async () => {
    const res = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ username: 'newuser', password: 'newpassword1', isAdmin: false });

    expect(res.status).toBe(201);
    expect(res.body.username).toBe('newuser');
    expect(res.body.isAdmin).toBeFalsy();
    expect(res.body).not.toHaveProperty('passwordHash');
  });

  it('returns 400 for missing password', async () => {
    const res = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ username: 'baduser' });

    expect(res.status).toBe(400);
  });

  it('returns 400 for short password', async () => {
    const res = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ username: 'baduser2', password: 'short' });

    expect(res.status).toBe(400);
  });

  it('returns 401 without token', async () => {
    const res = await request(app)
      .post('/api/users')
      .send({ username: 'sneaky', password: 'password123' });

    expect(res.status).toBe(401);
  });
});

describe('DELETE /api/users/:id', () => {
  it('deletes a user and returns 204', async () => {
    // Create a user to delete
    const createRes = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ username: 'todelete', password: 'deletepassword1' });
    expect(createRes.status).toBe(201);
    const userId = createRes.body.id as string;

    const deleteRes = await request(app)
      .delete(`/api/users/${userId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(deleteRes.status).toBe(204);

    // Confirm the user is gone from the list
    const listRes = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${adminToken}`);
    const usernames = (listRes.body as { username: string }[]).map((u) => u.username);
    expect(usernames).not.toContain('todelete');
  });

  it('returns 401 without token', async () => {
    const res = await request(app).delete('/api/users/nonexistent-id');
    expect(res.status).toBe(401);
  });
});
