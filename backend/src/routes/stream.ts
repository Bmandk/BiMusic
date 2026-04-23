import { Router, Request, Response, NextFunction } from "express";
import { statSync } from "fs";
import { authenticate } from "../middleware/auth.js";
import { resolveFilePath, serveFile } from "../services/trackFileResolver.js";
import {
  computeTrackKey,
  buildPlaylist,
  ensureSegment,
} from "../services/hlsService.js";
import { env } from "../config/env.js";
import { logger } from "../utils/logger.js";

const router = Router();

const VALID_BITRATES = new Set([128, 320]);

function parseBitrate(raw: unknown): number | null {
  if (raw === undefined) return 320;
  const s = typeof raw === "string" ? raw : String(raw);
  const n = parseInt(s, 10);
  return VALID_BITRATES.has(n) ? n : null;
}

async function handlePlaylist(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  try {
    const trackId = parseInt(req.params["trackId"] as string, 10);
    if (isNaN(trackId)) {
      res.status(400).json({
        error: { code: "BAD_REQUEST", message: "Invalid track ID" },
      });
      return;
    }

    const bitrate = parseBitrate(req.query["bitrate"]);
    if (bitrate === null) {
      res.status(400).json({
        error: {
          code: "BAD_REQUEST",
          message: "Invalid bitrate. Must be 128 or 320",
        },
      });
      return;
    }

    const token =
      typeof req.query["token"] === "string" ? req.query["token"] : "";

    const startSegmentRaw = req.query["startSegment"];
    const startSegment =
      startSegmentRaw === undefined ? 0 : parseInt(String(startSegmentRaw), 10);
    if (isNaN(startSegment) || startSegment < 0) {
      res.status(400).json({
        error: {
          code: "BAD_REQUEST",
          message: "Invalid startSegment",
        },
      });
      return;
    }

    logger.debug(
      { trackId, bitrate, hasToken: !!token, startSegment },
      "HLS playlist: request received",
    );

    const { durationMs } = await resolveFilePath(trackId);
    const segmentSeconds = env.HLS_SEGMENT_SECONDS;
    const segmentCount = Math.ceil(durationMs / (segmentSeconds * 1000));

    if (startSegment >= segmentCount) {
      res.status(400).json({
        error: {
          code: "BAD_REQUEST",
          message: "startSegment out of range",
        },
      });
      return;
    }

    logger.debug(
      {
        trackId,
        durationMs,
        segmentCount,
        segmentSeconds,
        bitrate,
        startSegment,
      },
      "HLS playlist: sending response",
    );

    const playlist = buildPlaylist(
      durationMs,
      segmentCount,
      segmentSeconds,
      bitrate,
      token,
      startSegment,
    );
    res.setHeader("Content-Type", "application/vnd.apple.mpegurl");
    res.setHeader("Cache-Control", "no-store");
    res.status(200).send(playlist);
  } catch (err) {
    next(err);
  }
}

// GET /api/stream/:trackId/playlist.m3u8 — primary endpoint (ExoPlayer on Android detects HLS from .m3u8 extension)
// GET /api/stream/:trackId/playlist — kept for backward compatibility and mpv (Windows)
router.get("/:trackId/playlist.m3u8", authenticate, handlePlaylist);
router.get("/:trackId/playlist", authenticate, handlePlaylist);

// GET /api/stream/:trackId/segment/:index
router.get(
  "/:trackId/segment/:index",
  authenticate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const trackId = parseInt(req.params["trackId"] as string, 10);
      if (isNaN(trackId)) {
        res.status(400).json({
          error: { code: "BAD_REQUEST", message: "Invalid track ID" },
        });
        return;
      }

      const segmentIndex = parseInt(req.params["index"] as string, 10);
      if (isNaN(segmentIndex) || segmentIndex < 0) {
        res.status(400).json({
          error: { code: "BAD_REQUEST", message: "Invalid segment index" },
        });
        return;
      }

      const bitrate = parseBitrate(req.query["bitrate"]);
      if (bitrate === null) {
        res.status(400).json({
          error: {
            code: "BAD_REQUEST",
            message: "Invalid bitrate. Must be 128 or 320",
          },
        });
        return;
      }

      logger.debug(
        { trackId, segmentIndex, bitrate },
        "HLS segment: request received",
      );

      const { sourcePath, durationMs } = await resolveFilePath(trackId);
      const segmentSeconds = env.HLS_SEGMENT_SECONDS;
      const segmentCount = Math.ceil(durationMs / (segmentSeconds * 1000));

      if (segmentIndex >= segmentCount) {
        res.status(400).json({
          error: { code: "BAD_REQUEST", message: "Segment index out of range" },
        });
        return;
      }

      const stat = statSync(sourcePath);
      const trackKey = computeTrackKey(
        sourcePath,
        stat.mtimeMs,
        stat.size,
        bitrate,
      );

      logger.debug(
        {
          trackId,
          segmentIndex,
          bitrate,
          sourcePath,
          trackKey: trackKey.slice(0, 8),
        },
        "HLS segment: transcoding/serving",
      );

      const segmentPath = await ensureSegment({
        sourcePath,
        trackKey,
        segmentIndex,
        bitrate,
        segmentSeconds,
      });

      logger.debug(
        { trackId, segmentIndex, segmentPath },
        "HLS segment: sending file",
      );

      serveFile(segmentPath, req, res, { contentType: "audio/mpeg" });
    } catch (err) {
      next(err);
    }
  },
);

export default router;
