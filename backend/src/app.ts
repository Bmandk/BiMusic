import express, { Request, Response, NextFunction } from 'express';
import { randomUUID } from 'crypto';
import { logger } from './utils/logger.js';
import { notFoundHandler, errorHandler } from './middleware/errorHandler.js';
import healthRouter from './routes/health.js';
import authRouter from './routes/auth.js';
import libraryRouter from './routes/library.js';
import streamRouter from './routes/stream.js';
import downloadsRouter from './routes/downloads.js';
import searchRouter from './routes/search.js';
import adminRouter from './routes/admin.js';
import usersRouter from './routes/users.js';
import playlistsRouter from './routes/playlists.js';

export function createApp() {
  const app = express();

  app.use(express.json());

  // Attach request ID
  app.use((_req: Request, res: Response, next: NextFunction) => {
    const requestId = randomUUID();
    res.locals['requestId'] = requestId;
    res.setHeader('X-Request-Id', requestId);
    next();
  });

  // Request logger
  app.use((req: Request, res: Response, next: NextFunction) => {
    const start = Date.now();
    res.on('finish', () => {
      const duration = Date.now() - start;
      const requestId = res.locals['requestId'] as string | undefined;
      const log = logger.child({ requestId });
      if (duration > 5000) {
        log.warn({ method: req.method, path: req.path, status: res.statusCode, duration }, 'Slow request');
      } else {
        log.info({ method: req.method, path: req.path, status: res.statusCode, duration }, 'Request');
      }
    });
    next();
  });

  // Routes
  app.use('/api/health', healthRouter);
  app.use('/api/auth', authRouter);
  app.use('/api/library', libraryRouter);
  app.use('/api/stream', streamRouter);
  app.use('/api/downloads', downloadsRouter);
  app.use('/api/search', searchRouter);
  app.use('/api/admin', adminRouter);
  app.use('/api/users', usersRouter);
  app.use('/api/playlists', playlistsRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
