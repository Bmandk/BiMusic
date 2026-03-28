import { Request, Response, NextFunction } from "express";
import { logger } from "../utils/logger.js";
import { env } from "../config/env.js";

export interface AppError extends Error {
  statusCode?: number;
  code?: string;
}

export function createError(
  statusCode: number,
  code: string,
  message: string,
): AppError {
  const err: AppError = new Error(message);
  err.statusCode = statusCode;
  err.code = code;
  return err;
}

// 404 handler — mount before errorHandler
export function notFoundHandler(
  req: Request,
  _res: Response,
  next: NextFunction,
): void {
  next(
    createError(404, "NOT_FOUND", `Route ${req.method} ${req.path} not found`),
  );
}

// Global error handler
export function errorHandler(
  err: AppError,
  _req: Request,
  res: Response,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _next: NextFunction,
): void {
  const statusCode = err.statusCode ?? 500;
  const code = err.code ?? "INTERNAL_ERROR";

  // In production, never expose internal details for 5xx errors
  const message =
    statusCode >= 500 && env.NODE_ENV === "production"
      ? "Internal server error"
      : err.message;

  if (statusCode >= 500) {
    logger.error(
      { err, requestId: res.locals["requestId"] },
      "Unhandled error",
    );
  } else if (statusCode >= 400) {
    logger.warn(
      { code, message, requestId: res.locals["requestId"] },
      "Client error",
    );
  }

  res.status(statusCode).json({
    error: { code, message },
  });
}
