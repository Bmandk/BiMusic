import { migrate } from "drizzle-orm/better-sqlite3/migrator";
import { join } from "path";
import { db } from "./connection.js";
import { logger } from "../utils/logger.js";

export function runMigrations(): void {
  logger.info("Running database migrations");
  migrate(db, { migrationsFolder: join(__dirname, "migrations") });
  logger.info("Migrations complete");
}
