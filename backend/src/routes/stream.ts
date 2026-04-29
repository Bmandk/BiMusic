import { Router, Request, Response, NextFunction } from "express";
import { authenticate } from "../middleware/auth.js";
import { createError } from "../middleware/errorHandler.js";
import {
  resolveFilePath,
  isPassthrough,
  streamTranscoded,
  serveFile,
} from "../services/streamService.js";

const router = Router();

const VALID_BITRATES = new Set([128, 320]);

router.get(
  "/:trackId",
  authenticate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const trackIdRaw = req.params["trackId"] as string;
      if (!/^\d+$/.test(trackIdRaw)) {
        throw createError(400, "BAD_REQUEST", "Invalid track ID");
      }
      const trackId = parseInt(trackIdRaw, 10);

      const bitrateRaw = req.query["bitrate"];
      let bitrate = 320;
      if (bitrateRaw !== undefined) {
        const bitrateStr =
          typeof bitrateRaw === "string" ? bitrateRaw : String(bitrateRaw);
        if (
          !/^\d+$/.test(bitrateStr) ||
          !VALID_BITRATES.has(parseInt(bitrateStr, 10))
        ) {
          throw createError(
            400,
            "BAD_REQUEST",
            "Invalid bitrate. Must be 128 or 320",
          );
        }
        bitrate = parseInt(bitrateStr, 10);
      }

      const sourcePath = await resolveFilePath(trackId);

      if (isPassthrough(sourcePath)) {
        serveFile(sourcePath, req, res);
      } else {
        await streamTranscoded(sourcePath, bitrate, req, res);
      }
    } catch (err) {
      next(err);
    }
  },
);

export default router;
