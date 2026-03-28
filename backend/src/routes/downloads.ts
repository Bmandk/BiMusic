import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { authenticate } from '../middleware/auth.js';
import {
  requestDownload,
  listDownloads,
  getDownload,
  deleteDownload,
  markDownloadComplete,
} from '../services/downloadService.js';
import { serveFile } from '../services/streamService.js';
import { createError } from '../middleware/errorHandler.js';

const router = Router();

const requestDownloadSchema = z.object({
  trackId: z.number().int().positive(),
  deviceId: z.string().min(1),
  bitrate: z.union([z.literal(128), z.literal(320)]).default(320),
});

/** POST /api/downloads — request a download */
router.post(
  '/',
  authenticate,
  (req: Request, res: Response, next: NextFunction): void => {
    const parsed = requestDownloadSchema.safeParse(req.body);
    if (!parsed.success) {
      next(createError(400, 'VALIDATION_ERROR', parsed.error.issues.map((i) => i.message).join(', ')));
      return;
    }

    const { trackId, deviceId, bitrate } = parsed.data;
    const userId = req.user!.userId;

    const record = requestDownload(userId, deviceId, trackId, bitrate);
    res.status(201).json(record);
  },
);

/** GET /api/downloads?deviceId= — list downloads for user+device */
router.get(
  '/',
  authenticate,
  (req: Request, res: Response, next: NextFunction): void => {
    const deviceId = req.query['deviceId'];
    if (typeof deviceId !== 'string' || deviceId.length === 0) {
      next(createError(400, 'VALIDATION_ERROR', 'deviceId query parameter is required'));
      return;
    }

    const records = listDownloads(req.user!.userId, deviceId);
    res.json(records);
  },
);

/** GET /api/downloads/:id/file — serve the downloaded file */
router.get(
  '/:id/file',
  authenticate,
  (req: Request, res: Response, next: NextFunction): void => {
    const id = req.params['id'] as string;

    let record;
    try {
      record = getDownload(id, req.user!.userId);
    } catch (err) {
      next(err);
      return;
    }

    if (record.status !== 'ready' && record.status !== 'complete') {
      next(createError(409, 'NOT_READY', `Download is not ready (status: ${record.status})`));
      return;
    }

    if (!record.filePath) {
      next(createError(500, 'INTERNAL_ERROR', 'Download file path is missing'));
      return;
    }

    const filename = `${record.lidarrTrackId}-${record.bitrate}.mp3`;
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

    markDownloadComplete(id);

    serveFile(record.filePath, req, res);
  },
);

/** DELETE /api/downloads/:id — delete a download record and its file */
router.delete(
  '/:id',
  authenticate,
  (req: Request, res: Response, next: NextFunction): void => {
    const id = req.params['id'] as string;

    try {
      deleteDownload(id, req.user!.userId);
    } catch (err) {
      next(err);
      return;
    }

    res.status(204).end();
  },
);

export default router;
