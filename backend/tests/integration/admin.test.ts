// tests/setup.ts sets env vars before this file loads (via vitest setupFiles)
// LOG_PATH is set to './logs' in setup.ts; this test creates and removes app.log there.
import { beforeAll, afterAll, describe, it, expect } from 'vitest';
import request from 'supertest';
import fs from 'fs';
import path from 'path';
import type { Express } from 'express';
import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/db/migrate.js';
import { bootstrapAdminIfNeeded } from '../../src/services/userService.js';

let app: Express;
let adminToken: string;
let userToken: string;

/** Absolute path of the log file the admin route will read (matches LOG_PATH from setup.ts). */
const LOG_DIR = path.resolve('./logs');
const LOG_FILE = path.join(LOG_DIR, 'app.log');

const ADMIN = { username: 'admin', password: 'adminpassword123' };

beforeAll(async () => {
  // Create a deterministic app.log so the admin endpoint always returns 200
  fs.mkdirSync(LOG_DIR, { recursive: true });
  const fakeLogLine = JSON.stringify({ level: 30, time: Date.now(), msg: 'test log entry' });
  fs.writeFileSync(LOG_FILE, fakeLogLine + '\n');

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

afterAll(() => {
  // Remove the app.log created by this test suite
  if (fs.existsSync(LOG_FILE)) {
    fs.rmSync(LOG_FILE);
  }
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
    // Temporarily remove app.log to exercise the 404 branch
    fs.rmSync(LOG_FILE);
    try {
      const res = await request(app)
        .get('/api/admin/logs')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(res.status).toBe(404);
      expect(res.body.error.code).toBe('NOT_FOUND');
    } finally {
      // Restore so subsequent tests (or re-runs) still find the file
      const fakeLogLine = JSON.stringify({ level: 30, time: Date.now(), msg: 'test log entry' });
      fs.writeFileSync(LOG_FILE, fakeLogLine + '\n');
    }
  });
});
