import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock env before any module that reads it loads
vi.mock('../../config/env.js', () => ({
  env: {
    PORT: 3001,
    NODE_ENV: 'test' as const,
    JWT_ACCESS_SECRET: 'test-access-secret-at-least-32-chars-long',
    JWT_REFRESH_SECRET: 'test-refresh-secret-at-least-32-chars-long',
    JWT_ACCESS_EXPIRY: '15m',
    JWT_REFRESH_EXPIRY: '30d',
    DB_PATH: ':memory:',
    LOG_PATH: './logs',
    LIDARR_URL: 'http://localhost:8686',
    LIDARR_API_KEY: 'test',
    MUSIC_LIBRARY_PATH: '/music',
    OFFLINE_STORAGE_PATH: './data/offline',
    ADMIN_USERNAME: 'admin',
    ADMIN_PASSWORD: 'adminpassword123',
    TEMP_DIR: '/tmp/bimusic',
  },
}));

// Mock logger to silence output in tests
vi.mock('../../utils/logger.js', () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    child: vi.fn(() => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() })),
  },
}));

// Mock the DB connection with an in-memory SQLite instance
vi.mock('../../db/connection.js', async () => {
  const BetterSqlite3 = (await import('better-sqlite3')).default;
  const { drizzle } = await import('drizzle-orm/better-sqlite3');
  const schemaModule = await import('../../db/schema.js');

  const sqlite = new BetterSqlite3(':memory:');
  sqlite.pragma('foreign_keys = ON');
  sqlite.exec(`
    CREATE TABLE users (
      id TEXT PRIMARY KEY NOT NULL,
      username TEXT NOT NULL UNIQUE,
      displayName TEXT NOT NULL,
      passwordHash TEXT NOT NULL,
      isAdmin INTEGER DEFAULT 0 NOT NULL,
      createdAt TEXT NOT NULL
    );
    CREATE TABLE refresh_tokens (
      id TEXT PRIMARY KEY NOT NULL,
      userId TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token_hash TEXT NOT NULL UNIQUE,
      expiresAt TEXT NOT NULL,
      createdAt TEXT NOT NULL
    );
  `);

  return { db: drizzle(sqlite, { schema: schemaModule.schema }), sqlite };
});

import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import { db } from '../../db/connection.js';
import { users, refreshTokens } from '../../db/schema.js';
import { login, refresh, logout, hashRefreshToken } from '../authService.js';

async function seedUser(username: string, password: string, isAdmin = false) {
  const passwordHash = await bcrypt.hash(password, 1); // cost 1 for speed in tests
  return db
    .insert(users)
    .values({ username, displayName: username, passwordHash, isAdmin: isAdmin ? 1 : 0 })
    .returning()
    .get();
}

beforeEach(() => {
  // Clear tables between tests
  db.delete(refreshTokens).run();
  db.delete(users).run();
});

describe('login', () => {
  it('returns access and refresh tokens for correct credentials', async () => {
    await seedUser('alice', 'correctpassword');
    const tokens = await login('alice', 'correctpassword');
    expect(tokens.accessToken).toBeDefined();
    expect(tokens.refreshToken).toBeDefined();
    // access token should be a valid JWT
    const payload = jwt.decode(tokens.accessToken) as Record<string, unknown>;
    expect(payload['username']).toBe('alice');
    expect(payload['isAdmin']).toBe(false);
  });

  it('throws UNAUTHORIZED for wrong password', async () => {
    await seedUser('alice', 'correctpassword');
    await expect(login('alice', 'wrongpassword')).rejects.toMatchObject({
      code: 'UNAUTHORIZED',
    });
  });

  it('throws UNAUTHORIZED for unknown user', async () => {
    await expect(login('nobody', 'password')).rejects.toMatchObject({
      code: 'UNAUTHORIZED',
    });
  });

  it('stores a refresh token hash in the DB', async () => {
    await seedUser('alice', 'correctpassword');
    const { refreshToken } = await login('alice', 'correctpassword');
    const hash = hashRefreshToken(refreshToken);
    const row = db.select().from(refreshTokens).get();
    expect(row?.token_hash).toBe(hash);
  });
});

describe('refresh', () => {
  it('rotates tokens correctly — returns new pair, old token is invalidated', async () => {
    await seedUser('alice', 'correctpassword');
    const { refreshToken: original } = await login('alice', 'correctpassword');
    const newTokens = refresh(original);
    expect(newTokens.accessToken).toBeDefined();
    expect(newTokens.refreshToken).toBeDefined();
    expect(newTokens.refreshToken).not.toBe(original);
    // original token should no longer work
    expect(() => refresh(original)).toThrowError();
  });

  it('throws UNAUTHORIZED for an already-used token (rotation prevents reuse)', async () => {
    await seedUser('alice', 'correctpassword');
    const { refreshToken } = await login('alice', 'correctpassword');
    refresh(refreshToken); // use once
    let err1: unknown;
    try { refresh(refreshToken); } catch (e) { err1 = e; }
    expect(err1).toMatchObject({ code: 'UNAUTHORIZED' });
  });

  it('throws UNAUTHORIZED for an expired token', async () => {
    await seedUser('alice', 'correctpassword');
    // Insert a token that expired in the past
    const user = db.select().from(users).get()!;
    const rawToken = 'expired-token-value';
    const tokenHash = hashRefreshToken(rawToken);
    db.insert(refreshTokens).values({
      userId: user.id,
      token_hash: tokenHash,
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    }).run();
    let err2: unknown;
    try { refresh(rawToken); } catch (e) { err2 = e; }
    expect(err2).toMatchObject({ code: 'UNAUTHORIZED' });
  });

  it('throws UNAUTHORIZED for a completely unknown token', () => {
    let err3: unknown;
    try { refresh('totally-unknown-token'); } catch (e) { err3 = e; }
    expect(err3).toMatchObject({ code: 'UNAUTHORIZED' });
  });
});

describe('logout', () => {
  it('removes the refresh token row', async () => {
    await seedUser('alice', 'correctpassword');
    const { refreshToken } = await login('alice', 'correctpassword');
    logout(refreshToken);
    const row = db.select().from(refreshTokens).get();
    expect(row).toBeUndefined();
  });

  it('subsequent refresh after logout returns UNAUTHORIZED', async () => {
    await seedUser('alice', 'correctpassword');
    const { refreshToken } = await login('alice', 'correctpassword');
    logout(refreshToken);
    let err4: unknown;
    try { refresh(refreshToken); } catch (e) { err4 = e; }
    expect(err4).toMatchObject({ code: 'UNAUTHORIZED' });
  });
});
