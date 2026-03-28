import { Router, Request, Response, NextFunction } from 'express';
import { authenticate } from '../middleware/auth.js';
import * as libraryService from '../services/libraryService.js';

const router = Router();

router.use(authenticate);

router.get('/', async (req: Request, res: Response, next: NextFunction) => {
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
