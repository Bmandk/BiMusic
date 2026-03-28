import { Router, Request, Response, NextFunction } from 'express';
import { authenticate } from '../middleware/auth.js';
import * as libraryService from '../services/libraryService.js';

const router = Router();

router.use(authenticate);

router.get('/artists', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const artists = await libraryService.getArtists();
    res.json(artists);
  } catch (err) {
    next(err);
  }
});

router.get('/artists/:id/albums', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params['id'] as string, 10);
    if (isNaN(id)) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid artist ID' } });
      return;
    }
    const albums = await libraryService.getArtistAlbums(id);
    res.json(albums);
  } catch (err) {
    next(err);
  }
});

router.get('/artists/:id/image', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params['id'] as string, 10);
    if (isNaN(id)) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid artist ID' } });
      return;
    }
    const imageRes = await libraryService.getArtistImageStream(id);
    if (imageRes.headers['content-type']) {
      res.setHeader('Content-Type', String(imageRes.headers['content-type']));
    }
    imageRes.data.pipe(res);
  } catch (err) {
    next(err);
  }
});

router.get('/artists/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params['id'] as string, 10);
    if (isNaN(id)) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid artist ID' } });
      return;
    }
    const artist = await libraryService.getArtist(id);
    res.json(artist);
  } catch (err) {
    next(err);
  }
});

router.get('/albums/:id/tracks', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params['id'] as string, 10);
    if (isNaN(id)) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid album ID' } });
      return;
    }
    const tracks = await libraryService.getAlbumTracks(id);
    res.json(tracks);
  } catch (err) {
    next(err);
  }
});

router.get('/albums/:id/image', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params['id'] as string, 10);
    if (isNaN(id)) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid album ID' } });
      return;
    }
    const imageRes = await libraryService.getAlbumImageStream(id);
    if (imageRes.headers['content-type']) {
      res.setHeader('Content-Type', String(imageRes.headers['content-type']));
    }
    imageRes.data.pipe(res);
  } catch (err) {
    next(err);
  }
});

router.get('/albums/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params['id'] as string, 10);
    if (isNaN(id)) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid album ID' } });
      return;
    }
    const album = await libraryService.getAlbum(id);
    res.json(album);
  } catch (err) {
    next(err);
  }
});

router.get('/tracks/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params['id'] as string, 10);
    if (isNaN(id)) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid track ID' } });
      return;
    }
    const track = await libraryService.getTrack(id);
    res.json(track);
  } catch (err) {
    next(err);
  }
});

router.get('/search', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const term = req.query['term'];
    if (typeof term !== 'string' || !term.trim()) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Missing or empty search term' } });
      return;
    }
    const results = await libraryService.search(term);
    res.json(results);
  } catch (err) {
    next(err);
  }
});

export default router;
