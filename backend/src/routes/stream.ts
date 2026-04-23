import { Router, Request, Response, NextFunction } from "express";
import { stat } from "fs/promises";
import rateLimit from "express-rate-limit";
import { authenticate } from "../middleware/auth.js";
import { createError } from "../middleware/errorHandler.js";
import { resolveFilePath, serveFile } from "../services/trackFileResolver.js";
import {
  computeTrackKey,
  buildPlaylist,
  ensureSegment,
} from "../services/hlsService.js";
import { env } from "../config/env.js";
import { logger } from "../utils/logger.js";

const router = Router();

// 300 requests per minute per IP — generous for normal HLS scrubbing (40 segs × 7 concurrent tracks)
// but still blocks automated abuse.
const streamLimiter = rateLimit({
  windowMs: 60_000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: { code: "TOO_MANY_REQUESTS", message: "Rate limit exceeded" },
  },
});

router.use(streamLimiter);

const VALID_BITRATES = new Set([128, 320]);

function parseBitrate(raw: unknown): number | null {
  if (raw === undefined) return 320;
  const s = typeof raw === "string" ? raw : String(raw);
  const n = parseInt(s, 10);
  return VALID_BITRATES.has(n) ? n : null;
}

/** Extract the bearer token from the request: ?token= query param takes precedence,
 *  falling back to the Authorization header so callers that authenticated via header
 *  still get working segment URIs embedded in the playlist. */
function extractToken(req: Request): string {
  if (typeof req.query["token"] === "string" && req.query["token"]) {
    return req.query["token"];
  }
  const auth = req.headers.authorization;
  if (auth?.startsWith("Bearer ")) {
    return auth.slice(7);
  }
  return "";
}

async function handlePlaylist(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  try {
    const trackId = parseInt(req.params["trackId"] as string, 10);
    if (isNaN(trackId)) {
      next(createError(400, "BAD_REQUEST", "Invalid track ID"));
      return;
    }

    const bitrate = parseBitrate(req.query["bitrate"]);
    if (bitrate === null) {
      next(
        createError(400, "BAD_REQUEST", "Invalid bitrate. Must be 128 or 320"),
      );
      return;
    }

    const token = extractToken(req);

    const startSegmentRaw = req.query["startSegment"];
    const startSegment =
      startSegmentRaw === undefined ? 0 : parseInt(String(startSegmentRaw), 10);
    if (isNaN(startSegment) || startSegment < 0) {
      next(createError(400, "BAD_REQUEST", "Invalid startSegment"));
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
      next(createError(400, "BAD_REQUEST", "startSegment out of range"));
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
        next(createError(400, "BAD_REQUEST", "Invalid track ID"));
        return;
      }

      const segmentIndex = parseInt(req.params["index"] as string, 10);
      if (isNaN(segmentIndex) || segmentIndex < 0) {
        next(createError(400, "BAD_REQUEST", "Invalid segment index"));
        return;
      }

      const bitrate = parseBitrate(req.query["bitrate"]);
      if (bitrate === null) {
        next(
          createError(
            400,
            "BAD_REQUEST",
            "Invalid bitrate. Must be 128 or 320",
          ),
        );
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
        next(createError(400, "BAD_REQUEST", "Segment index out of range"));
        return;
      }

      let fileStat: Awaited<ReturnType<typeof stat>>;
      try {
        fileStat = await stat(sourcePath);
      } catch {
        throw createError(404, "NOT_FOUND", "Track file is not readable");
      }
      const trackKey = computeTrackKey(
        sourcePath,
        fileStat.mtimeMs,
        fileStat.size,
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
