import { Router, Request, Response } from 'express';
import { readFileSync } from 'fs';
import { resolve } from 'path';

function readVersion(): string {
  try {
    const pkg = JSON.parse(readFileSync(resolve(__dirname, '../../package.json'), 'utf-8')) as { version: string };
    return pkg.version;
  } catch {
    return 'unknown';
  }
}

const version = readVersion();
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.status(200).json({ status: 'ok', version });
});

export default router;
