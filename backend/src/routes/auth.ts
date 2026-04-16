import { Router, Request, Response, NextFunction } from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";
import * as authService from "../services/authService.js";
import { authenticate } from "../middleware/auth.js";
import { createError } from "../middleware/errorHandler.js";

const router = Router();

const loginRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: { code: "RATE_LIMITED", message: "Too many login attempts, please try again later" } },
});

const loginSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(1),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

const logoutSchema = z.object({
  refreshToken: z.string().min(1),
});

router.post(
  "/login",
  loginRateLimiter,
  async (req: Request, res: Response, next: NextFunction) => {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) {
      next(
        createError(
          400,
          "VALIDATION_ERROR",
          "username and password are required",
        ),
      );
      return;
    }
    try {
      const tokens = await authService.login(
        parsed.data.username,
        parsed.data.password,
      );
      res.json(tokens);
    } catch (err) {
      next(err);
    }
  },
);

router.post("/refresh", (req: Request, res: Response, next: NextFunction) => {
  const parsed = refreshSchema.safeParse(req.body);
  if (!parsed.success) {
    next(createError(400, "VALIDATION_ERROR", "refreshToken is required"));
    return;
  }
  try {
    const tokens = authService.refresh(parsed.data.refreshToken);
    res.json(tokens);
  } catch (err) {
    next(err);
  }
});

router.post(
  "/logout",
  authenticate,
  (req: Request, res: Response, next: NextFunction) => {
    const parsed = logoutSchema.safeParse(req.body);
    if (!parsed.success) {
      next(createError(400, "VALIDATION_ERROR", "refreshToken is required"));
      return;
    }
    try {
      authService.logout(parsed.data.refreshToken);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  },
);

router.get("/me", authenticate, (req: Request, res: Response) => {
  res.json(req.user);
});

export default router;
