import './config/env.js'; // validate env before anything else
import { env } from './config/env.js';
import { logger } from './utils/logger.js';
import { createApp } from './app.js';
import { runMigrations } from './db/migrate.js';
import { bootstrapAdminIfNeeded } from './services/userService.js';
import { initTempDir, startTempFileCleanup } from './services/streamService.js';
import { startDownloadWorker } from './services/downloadService.js';

function startServer(): Promise<void> {
  return new Promise((resolve) => {
    const app = createApp();

    const server = app.listen(env.PORT, () => {
      logger.info({ port: env.PORT, env: env.NODE_ENV }, 'Server started');
      resolve();
    });

    function shutdown(signal: string) {
      logger.info({ signal }, 'Shutting down gracefully');
      server.close(() => {
        logger.info('HTTP server closed');
        process.exit(0);
      });
    }

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
  });
}

async function main() {
  runMigrations();
  await bootstrapAdminIfNeeded();
  initTempDir();
  startTempFileCleanup();
  startDownloadWorker();
  await startServer();
}

main().catch((err) => {
  logger.error({ err }, 'Fatal startup error');
  process.exit(1);
});
