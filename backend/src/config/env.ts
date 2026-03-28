import { z } from "zod";

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
  LOG_PATH: z.string().default("./logs"),
  ADMIN_USERNAME: z.string().default("admin"),
  ADMIN_PASSWORD: z.string().min(8),
  TEMP_DIR: z.string().default("/tmp/bimusic"),
  API_BASE_URL: z.string().url().default("http://localhost:3000"),
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
