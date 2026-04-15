import "./config/env.js"; // validate env before anything else
import { env } from "./config/env.js";
import { logger } from "./utils/logger.js";
import { createApp } from "./app.js";
import { runMigrations } from "./db/migrate.js";
import { bootstrapAdminIfNeeded } from "./services/userService.js";
import {
  initTempDir,
  startTempFileCleanup,
  killAllActiveTranscodes,
} from "./services/streamService.js";
import {
  startDownloadWorker,
  resetStuckDownloads,
} from "./services/downloadService.js";

process.on("unhandledRejection", (reason) => {
  logger.error({ reason }, "Unhandled promise rejection");
});

process.on("uncaughtException", (err) => {
  logger.error({ err }, "Uncaught exception");
  process.exit(1);
});

function startServer(): Promise<void> {
  return new Promise((resolve) => {
    const app = createApp();

    const server = app.listen(env.PORT, () => {
      logger.info({ port: env.PORT, env: env.NODE_ENV }, "Server started");
      resolve();
    });

    function shutdown(signal: string) {
      logger.info({ signal }, "Shutting down gracefully");

      // Force exit after 5 s if in-flight requests don't drain
      const forceKillTimer = setTimeout(() => {
        logger.warn("Graceful shutdown timed out, forcing exit");
        killAllActiveTranscodes();
        process.exit(1);
      }, 5000);
      forceKillTimer.unref();

      // Stop accepting new connections; wait for in-flight requests to finish
      server.close(() => {
        logger.info("HTTP server closed");
        killAllActiveTranscodes();
        logger.flush(() => process.exit(0));
      });
    }

    process.on("SIGTERM", () => shutdown("SIGTERM"));
    process.on("SIGINT", () => shutdown("SIGINT"));
  });
}

async function main() {
  runMigrations();
  await bootstrapAdminIfNeeded();
  initTempDir();
  startTempFileCleanup();
  resetStuckDownloads();
  startDownloadWorker();
  await startServer();
}

main().catch((err) => {
  logger.error({ err }, "Fatal startup error");
  process.exit(1);
});
