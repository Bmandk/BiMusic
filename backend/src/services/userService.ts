import bcrypt from 'bcrypt';
import { eq } from 'drizzle-orm';
import { db } from '../db/connection.js';
import { users } from '../db/schema.js';
import { env } from '../config/env.js';
import { logger } from '../utils/logger.js';

const userPublicFields = {
  id: users.id,
  username: users.username,
  displayName: users.displayName,
  isAdmin: users.isAdmin,
  createdAt: users.createdAt,
};

export async function createUser(username: string, password: string, isAdmin = false) {
  const passwordHash = await bcrypt.hash(password, 12);
  return db
    .insert(users)
    .values({
      username,
      displayName: username,
      passwordHash,
      isAdmin: isAdmin ? 1 : 0,
    })
    .returning(userPublicFields)
    .get();
}

export function getUser(id: string) {
  return db.select(userPublicFields).from(users).where(eq(users.id, id)).get();
}

export function listUsers() {
  return db.select(userPublicFields).from(users).all();
}

export function deleteUser(id: string): void {
  db.delete(users).where(eq(users.id, id)).run();
}

export async function bootstrapAdminIfNeeded(): Promise<void> {
  const existing = db.select({ id: users.id }).from(users).limit(1).get();
  if (existing) return;
  logger.info('No users found — bootstrapping admin user');
  await createUser(env.ADMIN_USERNAME, env.ADMIN_PASSWORD, true);
  logger.info({ username: env.ADMIN_USERNAME }, 'Admin user created');
}
