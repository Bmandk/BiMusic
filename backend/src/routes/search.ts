import { Router, Request, Response, NextFunction } from "express";
import { authenticate } from "../middleware/auth.js";
import * as libraryService from "../services/libraryService.js";
import { logger } from "../utils/logger.js";

const router = Router();

router.use(authenticate);

router.get("/", async (req: Request, res: Response, next: NextFunction) => {
  try {
    const term = req.query["term"];
    logger.debug({ term, type: typeof term }, "search route: received request");
    if (typeof term !== "string" || !term.trim()) {
      logger.warn({ term, type: typeof term }, "search route: invalid term");
      res.status(400).json({
        error: {
          code: "BAD_REQUEST",
          message: "Missing or empty search term",
        },
      });
      return;
    }
    logger.debug({ term }, "search route: calling libraryService.search");
    const results = await libraryService.search(term);
    logger.debug(
      {
        term,
        artistCount: results.artists.length,
        albumCount: results.albums.length,
      },
      "search route: returning results",
    );
    res.json(results);
  } catch (err) {
    logger.error(
      { term: req.query["term"], err },
      "search route: unhandled error",
    );
    next(err);
  }
});

export default router;
