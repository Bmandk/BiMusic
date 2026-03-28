// tests/setup.ts sets env vars before this file loads (via vitest setupFiles)
import { beforeAll, describe, it, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/db/migrate.js';

let app: Express;

beforeAll(() => {
  runMigrations();
  app = createApp();
});

describe('GET /api/health', () => {
  it('returns 200 with status ok and semver version', async () => {
    const res = await request(app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(typeof res.body.version).toBe('string');
    expect(res.body.version).toMatch(/^\d+\.\d+\.\d+/);
  });

  it('does not require authentication', async () => {
    const res = await request(app).get('/api/health');
    expect(res.status).toBe(200);
  });
});
