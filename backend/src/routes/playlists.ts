import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import * as playlistService from '../services/playlistService.js';
import * as libraryService from '../services/libraryService.js';
import { authenticate } from '../middleware/auth.js';
import { createError } from '../middleware/errorHandler.js';

const router = Router();
router.use(authenticate);

const createPlaylistSchema = z.object({
  name: z.string().min(1),
});

const updatePlaylistSchema = z.object({
  name: z.string().min(1),
});

const addTracksSchema = z.object({
  trackIds: z.array(z.number().int().positive()).min(1),
  position: z.number().int().min(0).optional(),
});

const reorderTracksSchema = z.object({
  trackIds: z.array(z.number().int().positive()).min(1),
});

router.get('/', (req: Request, res: Response) => {
  const list = playlistService.listPlaylists(req.user!.userId);
  res.json(list);
});

router.post('/', (req: Request, res: Response, next: NextFunction) => {
  const parsed = createPlaylistSchema.safeParse(req.body);
  if (!parsed.success) {
    next(createError(400, 'VALIDATION_ERROR', 'name is required'));
    return;
  }
  try {
    const playlist = playlistService.createPlaylist(req.user!.userId, parsed.data.name);
    res.status(201).json(playlist);
  } catch (err) {
    next(err);
  }
});

router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const playlist = playlistService.getPlaylist(req.params['id'] as string, req.user!.userId);
    // Enrich each playlist track with full Track data from Lidarr.
    // Use allSettled so a deleted/missing track doesn't break the whole response.
    const results = await Promise.allSettled(
      playlist.tracks.map(t => libraryService.getTrack(t.lidarrTrackId)),
    );
    const tracks = results
      .filter((r): r is PromiseFulfilledResult<Awaited<ReturnType<typeof libraryService.getTrack>>> =>
        r.status === 'fulfilled',
      )
      .map(r => r.value);
    res.json({ id: playlist.id, name: playlist.name, tracks });
  } catch (err) {
    next(err);
  }
});

router.put('/:id', (req: Request, res: Response, next: NextFunction) => {
  const parsed = updatePlaylistSchema.safeParse(req.body);
  if (!parsed.success) {
    next(createError(400, 'VALIDATION_ERROR', 'name is required'));
    return;
  }
  try {
    const playlist = playlistService.updatePlaylist(req.params['id'] as string, req.user!.userId, parsed.data.name);
    res.json(playlist);
  } catch (err) {
    next(err);
  }
});

router.delete('/:id', (req: Request, res: Response, next: NextFunction) => {
  try {
    playlistService.deletePlaylist(req.params['id'] as string, req.user!.userId);
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

router.post('/:id/tracks', (req: Request, res: Response, next: NextFunction) => {
  const parsed = addTracksSchema.safeParse(req.body);
  if (!parsed.success) {
    next(createError(400, 'VALIDATION_ERROR', 'trackIds (non-empty array of integers) is required'));
    return;
  }
  try {
    const added = playlistService.addTracks(
      req.params['id'] as string,
      req.user!.userId,
      parsed.data.trackIds,
      parsed.data.position,
    );
    res.json({ added });
  } catch (err) {
    next(err);
  }
});

router.delete('/:id/tracks/:trackId', (req: Request, res: Response, next: NextFunction) => {
  const lidarrTrackId = parseInt(req.params['trackId'] as string, 10);
  if (isNaN(lidarrTrackId)) {
    next(createError(400, 'VALIDATION_ERROR', 'trackId must be a number'));
    return;
  }
  try {
    playlistService.removeTrack(req.params['id'] as string, req.user!.userId, lidarrTrackId);
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

router.put('/:id/tracks/reorder', (req: Request, res: Response, next: NextFunction) => {
  const parsed = reorderTracksSchema.safeParse(req.body);
  if (!parsed.success) {
    next(createError(400, 'VALIDATION_ERROR', 'trackIds (non-empty array of integers) is required'));
    return;
  }
  try {
    playlistService.reorderTracks(req.params['id'] as string, req.user!.userId, parsed.data.trackIds);
    res.status(200).send();
  } catch (err) {
    next(err);
  }
});

export default router;
