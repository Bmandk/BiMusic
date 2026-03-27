// tests/setup.ts sets env vars before this file loads (via vitest setupFiles)
import { beforeAll, describe, it, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/db/migrate.js';
import { bootstrapAdminIfNeeded } from '../../src/services/userService.js';

let app: Express;

beforeAll(async () => {
  runMigrations();
  await bootstrapAdminIfNeeded();
  app = createApp();
});

const ADMIN = { username: 'admin', password: 'adminpassword123' };

async function loginAs(creds: { username: string; password: string }) {
  const res = await request(app).post('/api/auth/login').send(creds);
  return res;
}

describe('POST /api/auth/login', () => {
  it('returns 200 with access + refresh tokens for valid credentials', async () => {
    const res = await loginAs(ADMIN);
    expect(res.status).toBe(200);
    expect(res.body.accessToken).toBeDefined();
    expect(res.body.refreshToken).toBeDefined();
  });

  it('returns 401 for wrong password', async () => {
    const res = await loginAs({ username: 'admin', password: 'wrongpassword' });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHORIZED');
  });

  it('returns 400 for missing body fields', async () => {
    const res = await request(app).post('/api/auth/login').send({ username: 'admin' });
    expect(res.status).toBe(400);
  });
});

describe('GET /api/auth/me', () => {
  it('returns 200 with user payload for valid access token', async () => {
    const { body } = await loginAs(ADMIN);
    const res = await request(app)
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${body.accessToken}`);
    expect(res.status).toBe(200);
    expect(res.body.username).toBe('admin');
    expect(res.body.isAdmin).toBe(true);
  });

  it('returns 401 for missing token', async () => {
    const res = await request(app).get('/api/auth/me');
    expect(res.status).toBe(401);
  });

  it('returns 401 for invalid token', async () => {
    const res = await request(app)
      .get('/api/auth/me')
      .set('Authorization', 'Bearer invalid.token.here');
    expect(res.status).toBe(401);
  });
});

describe('POST /api/auth/refresh', () => {
  it('returns new token pair and old refresh token is invalidated', async () => {
    const { body: loginBody } = await loginAs(ADMIN);
    const original = loginBody.refreshToken;

    const res = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken: original });
    expect(res.status).toBe(200);
    expect(res.body.accessToken).toBeDefined();
    expect(res.body.refreshToken).not.toBe(original);

    // Original token should now be rejected
    const reuse = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken: original });
    expect(reuse.status).toBe(401);
  });

  it('returns 401 for unknown refresh token', async () => {
    const res = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken: 'not-a-real-token' });
    expect(res.status).toBe(401);
  });
});

describe('POST /api/auth/logout', () => {
  it('returns 204 and subsequent refresh with same token returns 401', async () => {
    const { body: loginBody } = await loginAs(ADMIN);
    const { accessToken, refreshToken } = loginBody;

    const logoutRes = await request(app)
      .post('/api/auth/logout')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ refreshToken });
    expect(logoutRes.status).toBe(204);

    const refreshRes = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken });
    expect(refreshRes.status).toBe(401);
  });

  it('returns 401 without Authorization header', async () => {
    const res = await request(app)
      .post('/api/auth/logout')
      .send({ refreshToken: 'some-token' });
    expect(res.status).toBe(401);
  });
});
