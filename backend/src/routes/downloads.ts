import { Router, Request, Response } from 'express';

const router = Router();

router.all('/{*path}', (_req: Request, res: Response) => {
  res.status(501).json({ error: { code: 'NOT_IMPLEMENTED', message: 'Not implemented' } });
});

export default router;
