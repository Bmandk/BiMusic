import { describe, it, expect } from 'vitest';
import { z } from 'zod';

// Re-define the schema here so we can test it without side effects
// (the real env.ts calls process.exit on failure, which we can't do in tests)
const envSchema = z.object({
  PORT: z.coerce.number().default(3000),
  NODE_ENV: z.enum(['production', 'development', 'test']).default('production'),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  JWT_ACCESS_EXPIRY: z.string().default('15m'),
  JWT_REFRESH_EXPIRY: z.string().default('30d'),
  LIDARR_URL: z.string().url(),
  LIDARR_API_KEY: z.string().min(1),
  MUSIC_LIBRARY_PATH: z.string().min(1),
  OFFLINE_STORAGE_PATH: z.string().default('./data/offline'),
  DB_PATH: z.string().default('./data/bimusic.db'),
  LOG_PATH: z.string().default('./logs'),
  ADMIN_USERNAME: z.string().default('admin'),
  ADMIN_PASSWORD: z.string().min(8),
  TEMP_DIR: z.string().default('/tmp/bimusic'),
});

const VALID_ENV = {
  JWT_ACCESS_SECRET: 'a'.repeat(32),
  JWT_REFRESH_SECRET: 'b'.repeat(32),
  LIDARR_URL: 'http://localhost:8686',
  LIDARR_API_KEY: 'test-key',
  MUSIC_LIBRARY_PATH: '/music',
  ADMIN_PASSWORD: 'securepassword',
};

describe('env schema', () => {
  it('parses a valid env successfully', () => {
    const result = envSchema.safeParse(VALID_ENV);
    expect(result.success).toBe(true);
  });

  it('applies defaults for optional fields', () => {
    const result = envSchema.safeParse(VALID_ENV);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.PORT).toBe(3000);
    expect(result.data.NODE_ENV).toBe('production');
    expect(result.data.JWT_ACCESS_EXPIRY).toBe('15m');
    expect(result.data.DB_PATH).toBe('./data/bimusic.db');
  });

  it('rejects missing JWT_ACCESS_SECRET', () => {
    const result = envSchema.safeParse({ ...VALID_ENV, JWT_ACCESS_SECRET: undefined });
    expect(result.success).toBe(false);
    if (result.success) return;
    const paths = result.error.issues.map((i) => i.path[0]);
    expect(paths).toContain('JWT_ACCESS_SECRET');
  });

  it('rejects JWT_ACCESS_SECRET shorter than 32 chars', () => {
    const result = envSchema.safeParse({ ...VALID_ENV, JWT_ACCESS_SECRET: 'short' });
    expect(result.success).toBe(false);
    if (result.success) return;
    const issue = result.error.issues.find((i) => i.path[0] === 'JWT_ACCESS_SECRET');
    expect(issue).toBeDefined();
  });

  it('rejects missing LIDARR_URL', () => {
    const result = envSchema.safeParse({ ...VALID_ENV, LIDARR_URL: undefined });
    expect(result.success).toBe(false);
  });

  it('rejects invalid LIDARR_URL', () => {
    const result = envSchema.safeParse({ ...VALID_ENV, LIDARR_URL: 'not-a-url' });
    expect(result.success).toBe(false);
    if (result.success) return;
    const issue = result.error.issues.find((i) => i.path[0] === 'LIDARR_URL');
    expect(issue).toBeDefined();
  });

  it('rejects ADMIN_PASSWORD shorter than 8 chars', () => {
    const result = envSchema.safeParse({ ...VALID_ENV, ADMIN_PASSWORD: 'short' });
    expect(result.success).toBe(false);
    if (result.success) return;
    const issue = result.error.issues.find((i) => i.path[0] === 'ADMIN_PASSWORD');
    expect(issue).toBeDefined();
  });

  it('rejects invalid NODE_ENV value', () => {
    const result = envSchema.safeParse({ ...VALID_ENV, NODE_ENV: 'staging' });
    expect(result.success).toBe(false);
  });

  it('coerces PORT from string to number', () => {
    const result = envSchema.safeParse({ ...VALID_ENV, PORT: '4000' });
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.PORT).toBe(4000);
  });
});
