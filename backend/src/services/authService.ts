import { createHmac, randomBytes } from "crypto";
import jwt from "jsonwebtoken";
import ms from "ms";
import { eq, and, gt } from "drizzle-orm";
import bcrypt from "bcrypt";
import { db } from "../db/connection.js";
import { users, refreshTokens } from "../db/schema.js";
import { env } from "../config/env.js";
import { createError } from "../middleware/errorHandler.js";

export interface TokenPayload {
  userId: string;
  username: string;
  isAdmin: boolean;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export function hashRefreshToken(raw: string): string {
  return createHmac("sha256", env.JWT_REFRESH_SECRET).update(raw).digest("hex");
}

function generateRefreshToken(): string {
  return randomBytes(64).toString("hex");
}

function generateAccessToken(payload: TokenPayload): string {
  const signOpts = {
    expiresIn: env.JWT_ACCESS_EXPIRY,
    algorithm: "HS256" as const,
  };
  return jwt.sign(payload, env.JWT_ACCESS_SECRET, signOpts as jwt.SignOptions);
}

function refreshExpiresAt(): string {
  const durationMs = ms(env.JWT_REFRESH_EXPIRY as ms.StringValue);
  return new Date(Date.now() + durationMs).toISOString();
}

export async function login(
  username: string,
  password: string,
): Promise<TokenPair> {
  const user = db
    .select()
    .from(users)
    .where(eq(users.username, username))
    .get();
  if (!user) {
    throw createError(401, "UNAUTHORIZED", "Invalid credentials");
  }
  const valid = await bcrypt.compare(password, user.passwordHash);
  if (!valid) {
    throw createError(401, "UNAUTHORIZED", "Invalid credentials");
  }
  const rawRefresh = generateRefreshToken();
  const tokenHash = hashRefreshToken(rawRefresh);
  db.insert(refreshTokens)
    .values({
      userId: user.id,
      token_hash: tokenHash,
      expiresAt: refreshExpiresAt(),
    })
    .run();
  const accessToken = generateAccessToken({
    userId: user.id,
    username: user.username,
    isAdmin: user.isAdmin === 1,
  });
  return { accessToken, refreshToken: rawRefresh };
}

export function refresh(rawToken: string): TokenPair {
  const tokenHash = hashRefreshToken(rawToken);
  const now = new Date().toISOString();

  const newRaw = generateRefreshToken();
  const newHash = hashRefreshToken(newRaw);

  let user: typeof users.$inferSelect | undefined;

  db.transaction((tx) => {
    const row = tx
      .select()
      .from(refreshTokens)
      .where(
        and(
          eq(refreshTokens.token_hash, tokenHash),
          gt(refreshTokens.expiresAt, now),
        ),
      )
      .get();
    if (!row) {
      throw createError(
        401,
        "UNAUTHORIZED",
        "Invalid or expired refresh token",
      );
    }
    user = tx.select().from(users).where(eq(users.id, row.userId)).get();
    if (!user) {
      throw createError(401, "UNAUTHORIZED", "User not found");
    }
    // Rotate: delete old, insert new — all within a single transaction
    tx.delete(refreshTokens)
      .where(eq(refreshTokens.token_hash, tokenHash))
      .run();
    tx.insert(refreshTokens)
      .values({
        userId: user.id,
        token_hash: newHash,
        expiresAt: refreshExpiresAt(),
      })
      .run();
  });

  if (!user) {
    throw createError(401, "UNAUTHORIZED", "Invalid or expired refresh token");
  }

  const accessToken = generateAccessToken({
    userId: user.id,
    username: user.username,
    isAdmin: user.isAdmin === 1,
  });
  return { accessToken, refreshToken: newRaw };
}

export function logout(rawToken: string): void {
  const tokenHash = hashRefreshToken(rawToken);
  db.delete(refreshTokens).where(eq(refreshTokens.token_hash, tokenHash)).run();
}
