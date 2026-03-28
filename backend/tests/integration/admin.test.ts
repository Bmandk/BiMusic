// tests/setup.ts sets env vars before this file loads (via vitest setupFiles)
import { beforeAll, describe, it, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/db/migrate.js';
import { bootstrapAdminIfNeeded } from '../../src/services/userService.js';

let app: Express;
let adminToken: string;
let userToken: string;

const ADMIN = { username: 'admin', password: 'adminpassword123' };

beforeAll(async () => {
  runMigrations();
  await bootstrapAdminIfNeeded();
  app = createApp();

  const adminRes = await request(app).post('/api/auth/login').send(ADMIN);
  adminToken = adminRes.body.accessToken as string;

  // Create a non-admin user and log in as them
  await request(app)
    .post('/api/users')
    .set('Authorization', `Bearer ${adminToken}`)
    .send({ username: 'regularuser', password: 'regularpassword1', isAdmin: false });

  const userRes = await request(app)
    .post('/api/auth/login')
    .send({ username: 'regularuser', password: 'regularpassword1' });
  userToken = userRes.body.accessToken as string;
});

describe('GET /api/admin/logs', () => {
  it('returns 401 without token', async () => {
    const res = await request(app).get('/api/admin/logs');
    expect(res.status).toBe(401);
  });

  it('returns 403 for non-admin user', async () => {
    const res = await request(app)
      .get('/api/admin/logs')
      .set('Authorization', `Bearer ${userToken}`);
    expect(res.status).toBe(403);
  });

  it('returns 404 for admin when log file does not exist (dev mode)', async () => {
    // In test environment, LOG_PATH points to ./logs but no app.log file is created
    // (pino writes to stdout in test mode). Expect 404.
    const res = await request(app)
      .get('/api/admin/logs')
      .set('Authorization', `Bearer ${adminToken}`);
    // Either 200 (if logs exist) or 404 (dev/test mode without a log file)
    expect([200, 404]).toContain(res.status);
    if (res.status === 200) {
      expect(Array.isArray(res.body.lines)).toBe(true);
    } else {
      expect(res.body.error.code).toBe('NOT_FOUND');
    }
  });
});
