import { Router, Request, Response, NextFunction } from 'express';
import { readFile } from 'fs/promises';
import { existsSync } from 'fs';
import path from 'path';
import { authenticate, requireAdmin } from '../middleware/auth.js';
import { env } from '../config/env.js';
import { createError } from '../middleware/errorHandler.js';

const router = Router();

router.use(authenticate, requireAdmin);

router.get('/logs', async (_req: Request, res: Response, next: NextFunction) => {
  const logFile = path.join(env.LOG_PATH, 'app.log');

  if (!existsSync(logFile)) {
    next(createError(404, 'NOT_FOUND', 'Log file not found (running in development mode?)'));
    return;
  }

  try {
    const content = await readFile(logFile, 'utf-8');
    const allLines = content.split('\n').filter((l) => l.trim().length > 0);
    const lines = allLines.slice(-200);
    res.json({ lines });
  } catch (err) {
    next(err);
  }
});

export default router;
