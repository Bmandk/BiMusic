import { describe, it, expect, beforeEach, vi } from 'vitest';

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
    API_BASE_URL: 'http://localhost:3000',
  },
}));

vi.mock('../../utils/logger.js', () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    child: vi.fn(() => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() })),
  },
}));

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
  `);

  return { db: drizzle(sqlite, { schema: schemaModule.schema }), sqlite };
});

import { db } from '../../db/connection.js';
import { users } from '../../db/schema.js';
import * as userService from '../userService.js';

beforeEach(() => {
  db.delete(users).run();
});

describe('userService', () => {
  describe('createUser', () => {
    it('creates a user and returns public fields (no passwordHash)', async () => {
      const user = await userService.createUser('alice', 'password123', false);
      expect(user).toBeDefined();
      expect(user.username).toBe('alice');
      expect(user.isAdmin).toBe(0);
      expect(user).not.toHaveProperty('passwordHash');
    });

    it('creates an admin user when isAdmin is true', async () => {
      const user = await userService.createUser('bob', 'password123', true);
      expect(user.isAdmin).toBe(1);
    });

    it('defaults isAdmin to false when omitted', async () => {
      const user = await userService.createUser('charlie', 'password123');
      expect(user.isAdmin).toBe(0);
    });
  });

  describe('listUsers', () => {
    it('returns all created users', async () => {
      await userService.createUser('alice', 'pass1');
      await userService.createUser('bob', 'pass2', true);
      const all = userService.listUsers();
      expect(Array.isArray(all)).toBe(true);
      const usernames = all.map((u) => u.username);
      expect(usernames).toContain('alice');
      expect(usernames).toContain('bob');
    });

    it('does not include passwordHash in results', async () => {
      await userService.createUser('alice', 'pass1');
      const all = userService.listUsers();
      for (const u of all) {
        expect(u).not.toHaveProperty('passwordHash');
      }
    });

    it('returns empty array when no users exist', () => {
      const all = userService.listUsers();
      expect(all).toHaveLength(0);
    });
  });

  describe('getUser', () => {
    it('returns the user by id', async () => {
      const created = await userService.createUser('dave', 'password123');
      const found = userService.getUser(created.id);
      expect(found).toBeDefined();
      expect(found!.username).toBe('dave');
    });

    it('returns undefined for unknown id', () => {
      const found = userService.getUser('00000000000000000000000000000000');
      expect(found).toBeUndefined();
    });
  });

  describe('deleteUser', () => {
    it('removes the user from the list', async () => {
      const user = await userService.createUser('eve', 'password123');
      userService.deleteUser(user.id);
      const all = userService.listUsers();
      expect(all.map((u) => u.username)).not.toContain('eve');
    });

    it('is a no-op for an id that does not exist', () => {
      expect(() => userService.deleteUser('nonexistent-id')).not.toThrow();
    });
  });

  describe('bootstrapAdminIfNeeded', () => {
    it('creates admin user when no users exist', async () => {
      await userService.bootstrapAdminIfNeeded();
      const all = userService.listUsers();
      expect(all).toHaveLength(1);
      expect(all[0].username).toBe('admin');
      expect(all[0].isAdmin).toBe(1);
    });

    it('does not insert a duplicate when users already exist', async () => {
      await userService.createUser('existing', 'password123');
      const before = userService.listUsers().length;
      await userService.bootstrapAdminIfNeeded();
      const after = userService.listUsers().length;
      expect(after).toBe(before);
    });
  });
});
