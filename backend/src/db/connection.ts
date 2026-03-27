import Database, { type Database as BetterSqliteDatabase } from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { mkdirSync } from 'fs';
import { dirname } from 'path';
import { env } from '../config/env.js';
import { schema } from './schema.js';

if (env.DB_PATH !== ':memory:') {
  mkdirSync(dirname(env.DB_PATH), { recursive: true });
}

const sqlite: BetterSqliteDatabase = new Database(env.DB_PATH);
sqlite.pragma('journal_mode = WAL');
sqlite.pragma('foreign_keys = ON');

export const db = drizzle(sqlite, { schema });
export { sqlite };
