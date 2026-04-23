import { z } from "zod";
import fs from "fs";
import path from "path";

// Load .env from the project root (backend/) if vars aren't already set.
// Compiled output lands in backend/dist, so __dirname/../.env = backend/.env.
try {
  const envFilePath = path.join(__dirname, "..", ".env");
  const lines = fs.readFileSync(envFilePath, "utf8").split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eqIdx = trimmed.indexOf("=");
    if (eqIdx === -1) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    const raw = trimmed.slice(eqIdx + 1).trim();
    const value = raw.replace(/^(['"])(.*)\1$/, "$2");
    if (key && !(key in process.env)) {
      process.env[key] = value;
    }
  }
} catch {
  // No .env file — rely on process.env being pre-populated
}

const envSchema = z.object({
  PORT: z.coerce.number().default(3000),
  NODE_ENV: z.enum(["production", "development", "test"]).default("production"),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  JWT_ACCESS_EXPIRY: z.string().default("15m"),
  JWT_REFRESH_EXPIRY: z.string().default("30d"),
  LIDARR_URL: z
    .string()
    .url()
    .transform((url) => url.replace(/\/+$/, "")),
  LIDARR_API_KEY: z.string().min(1),
  MUSIC_LIBRARY_PATH: z.string().min(1),
  OFFLINE_STORAGE_PATH: z.string().default("./data/offline"),
  DB_PATH: z.string().default("./data/bimusic.db"),
  PM2_LOG_PATH: z.string().optional(),
  ADMIN_USERNAME: z.string().default("admin"),
  ADMIN_PASSWORD: z.string().min(8),
  HLS_CACHE_DIR: z.string().default("./data/hls"),
  HLS_SEGMENT_SECONDS: z.coerce.number().int().positive().default(6),
});

const result = envSchema.safeParse(process.env);

if (!result.success) {
  const formatted = result.error.issues
    .map((issue) => `  - ${issue.path.join(".")}: ${issue.message}`)
    .join("\n");
  console.error(`Environment validation failed:\n${formatted}`);
  process.exit(1);
}

export const env = result.data;
export type Env = typeof env;
