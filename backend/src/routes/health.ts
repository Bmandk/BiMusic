import { Router, Request, Response } from 'express';

const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.status(503).json({ status: 'not_implemented' });
});

export default router;
