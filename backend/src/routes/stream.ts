import { Router, Request, Response, NextFunction } from "express";
import { authenticate } from "../middleware/auth.js";
import {
  resolveFilePath,
  isPassthrough,
  ensureTranscoded,
  serveFile,
} from "../services/streamService.js";

const router = Router();

const VALID_BITRATES = new Set([128, 320]);

router.get(
  "/:trackId",
  authenticate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const trackId = parseInt(req.params["trackId"] as string, 10);
      if (isNaN(trackId)) {
        res
          .status(400)
          .json({
            error: { code: "BAD_REQUEST", message: "Invalid track ID" },
          });
        return;
      }

      const bitrateRaw = req.query["bitrate"];
      let bitrate = 320;
      if (bitrateRaw !== undefined) {
        const bitrateStr =
          typeof bitrateRaw === "string" ? bitrateRaw : String(bitrateRaw);
        const parsed = parseInt(bitrateStr, 10);
        if (isNaN(parsed) || !VALID_BITRATES.has(parsed)) {
          res.status(400).json({
            error: {
              code: "BAD_REQUEST",
              message: "Invalid bitrate. Must be 128 or 320",
            },
          });
          return;
        }
        bitrate = parsed;
      }

      const sourcePath = await resolveFilePath(trackId);

      let filePath: string;
      if (isPassthrough(sourcePath)) {
        filePath = sourcePath;
      } else {
        filePath = await ensureTranscoded(sourcePath, bitrate);
      }

      serveFile(filePath, req, res);
    } catch (err) {
      next(err);
    }
  },
);

export default router;
