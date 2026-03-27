import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { createError } from './errorHandler.js';

export interface AuthUser {
  userId: string;
  username: string;
  isAdmin: boolean;
}

export function authenticate(req: Request, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    next(createError(401, 'UNAUTHORIZED', 'Missing or invalid Authorization header'));
    return;
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, env.JWT_ACCESS_SECRET, { algorithms: ['HS256'] }) as AuthUser;
    req.user = payload;
    next();
  } catch {
    next(createError(401, 'UNAUTHORIZED', 'Invalid or expired access token'));
  }
}

export function requireAdmin(req: Request, _res: Response, next: NextFunction): void {
  if (!req.user?.isAdmin) {
    next(createError(403, 'FORBIDDEN', 'Admin access required'));
    return;
  }
  next();
}
