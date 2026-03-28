import { Router, Request, Response, NextFunction } from "express";
import { z } from "zod";
import * as userService from "../services/userService.js";
import { authenticate, requireAdmin } from "../middleware/auth.js";
import { createError } from "../middleware/errorHandler.js";

const router = Router();
router.use(authenticate, requireAdmin);

const createUserSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(8),
  isAdmin: z.boolean().optional().default(false),
});

router.get("/", (_req: Request, res: Response) => {
  res.json(userService.listUsers());
});

router.post("/", async (req: Request, res: Response, next: NextFunction) => {
  const parsed = createUserSchema.safeParse(req.body);
  if (!parsed.success) {
    next(createError(400, "VALIDATION_ERROR", "Invalid request body"));
    return;
  }
  try {
    const user = await userService.createUser(
      parsed.data.username,
      parsed.data.password,
      parsed.data.isAdmin,
    );
    res.status(201).json(user);
  } catch (err) {
    next(err);
  }
});

router.delete("/:id", (req: Request, res: Response) => {
  userService.deleteUser(req.params["id"] as string);
  res.status(204).send();
});

export default router;
