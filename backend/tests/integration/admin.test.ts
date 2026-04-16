// tests/setup.ts sets env vars before this file loads (via vitest setupFiles).
// This suite writes a temporary log file and points PM2_LOG_PATH at it for the
// happy-path test, then clears it to exercise the 404 branches.
import { beforeAll, afterAll, describe, it, expect } from 'vitest';
import request from 'supertest';
import fs from 'fs';
import path from 'path';
import os from 'os';
import type { Express } from 'express';

let app: Express;
let adminToken: string;
let userToken: string;

const LOG_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'bimusic-admin-log-'));
const LOG_FILE = path.join(LOG_DIR, 'pm2-out.log');

const ADMIN = { username: 'admin', password: 'adminpassword123' };

beforeAll(async () => {
  // Point the admin route at our fixture log before env/app modules load.
  process.env['PM2_LOG_PATH'] = LOG_FILE;

  const fakeLogLine = JSON.stringify({ level: 30, time: Date.now(), msg: 'test log entry' });
  fs.writeFileSync(LOG_FILE, fakeLogLine + '\n');

  const { createApp } = await import('../../src/app.js');
  const { runMigrations } = await import('../../src/db/migrate.js');
  const { bootstrapAdminIfNeeded } = await import('../../src/services/userService.js');

  runMigrations();
  await bootstrapAdminIfNeeded();
  app = createApp();

  const adminRes = await request(app).post('/api/auth/login').send(ADMIN);
  adminToken = adminRes.body.accessToken as string;

  await request(app)
    .post('/api/users')
    .set('Authorization', `Bearer ${adminToken}`)
    .send({ username: 'regularuser', password: 'regularpassword1', isAdmin: false });

  const userRes = await request(app)
    .post('/api/auth/login')
    .send({ username: 'regularuser', password: 'regularpassword1' });
  userToken = userRes.body.accessToken as string;
});

afterAll(() => {
  if (fs.existsSync(LOG_FILE)) fs.rmSync(LOG_FILE);
  fs.rmdirSync(LOG_DIR);
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

  it('returns 200 with log lines array for admin when log file exists', async () => {
    const res = await request(app)
      .get('/api/admin/logs')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.lines)).toBe(true);
    expect(res.body.lines.length).toBeGreaterThan(0);
  });

  it('returns 404 for admin when log file does not exist', async () => {
    fs.rmSync(LOG_FILE);
    try {
      const res = await request(app)
        .get('/api/admin/logs')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(res.status).toBe(404);
      expect(res.body.error.code).toBe('NOT_FOUND');
    } finally {
      const fakeLogLine = JSON.stringify({ level: 30, time: Date.now(), msg: 'test log entry' });
      fs.writeFileSync(LOG_FILE, fakeLogLine + '\n');
    }
  });
});
