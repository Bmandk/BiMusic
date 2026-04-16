import { Router, Request, Response, NextFunction } from "express";
import { z } from "zod";
import { authenticate } from "../middleware/auth.js";
import * as lidarrClient from "../services/lidarrClient.js";
import { createRequest, listRequests } from "../services/requestService.js";
import { createError } from "../middleware/errorHandler.js";
import type { LidarrArtist, LidarrAlbum } from "../types/lidarr.js";

/** Safe artist projection — strips internal fields (path, statistics, etc.) */
function projectArtist(a: LidarrArtist) {
  return {
    id: a.id,
    artistName: a.artistName,
    foreignArtistId: a.foreignArtistId,
    overview: a.overview,
    images: a.images,
  };
}

/** Safe album projection — strips internal fields (statistics, etc.) */
function projectAlbum(a: LidarrAlbum) {
  return {
    id: a.id,
    title: a.title,
    foreignAlbumId: a.foreignAlbumId,
    releaseDate: a.releaseDate,
    images: a.images,
    artist: projectArtist(a.artist),
  };
}

/** Fetch the first available quality profile, metadata profile, and root folder from Lidarr. */
async function getLidarrDefaults(): Promise<{
  qualityProfileId: number;
  metadataProfileId: number;
  rootFolderPath: string;
}> {
  const [qualityProfiles, metadataProfiles, rootFolders] = await Promise.all([
    lidarrClient.getQualityProfiles(),
    lidarrClient.getMetadataProfiles(),
    lidarrClient.getRootFolders(),
  ]);
  if (!qualityProfiles.length)
    throw createError(
      502,
      "LIDARR_ERROR",
      "No quality profiles found in Lidarr",
    );
  if (!metadataProfiles.length)
    throw createError(
      502,
      "LIDARR_ERROR",
      "No metadata profiles found in Lidarr",
    );
  if (!rootFolders.length)
    throw createError(502, "LIDARR_ERROR", "No root folders found in Lidarr");
  return {
    qualityProfileId: qualityProfiles[0].id,
    metadataProfileId: metadataProfiles[0].id,
    rootFolderPath: rootFolders[0].path,
  };
}

const router = Router();

router.use(authenticate);

/** GET /api/requests/search?term= — proxy Lidarr artist + album lookup */
router.get(
  "/search",
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const term = req.query["term"];
      if (typeof term !== "string" || !term.trim()) {
        res.status(400).json({
          error: {
            code: "BAD_REQUEST",
            message: "Missing or empty search term",
          },
        });
        return;
      }
      const [artists, albums] = await Promise.all([
        lidarrClient.lookupArtist(term),
        lidarrClient.lookupAlbum(term),
      ]);
      res.json({
        artists: artists.map(projectArtist),
        albums: albums.map(projectAlbum),
      });
    } catch (err) {
      next(err);
    }
  },
);

const artistRequestSchema = z.object({
  foreignArtistId: z.string().min(1),
  artistName: z.string().min(1),
  coverUrl: z.string().url().optional().nullable(),
  qualityProfileId: z.number().int().positive().optional(),
  metadataProfileId: z.number().int().positive().optional(),
  rootFolderPath: z.string().min(1).optional(),
  monitored: z.boolean().default(true),
});

/** POST /api/requests/artist — add artist to Lidarr and create request record */
router.post(
  "/artist",
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const parsed = artistRequestSchema.safeParse(req.body);
      if (!parsed.success) {
        next(
          createError(
            400,
            "VALIDATION_ERROR",
            parsed.error.issues.map((i) => i.message).join(", "),
          ),
        );
        return;
      }

      const { foreignArtistId, artistName, coverUrl, monitored } = parsed.data;
      let { qualityProfileId, metadataProfileId, rootFolderPath } = parsed.data;

      if (
        qualityProfileId === undefined ||
        metadataProfileId === undefined ||
        rootFolderPath === undefined
      ) {
        const defaults = await getLidarrDefaults();
        qualityProfileId ??= defaults.qualityProfileId;
        metadataProfileId ??= defaults.metadataProfileId;
        rootFolderPath ??= defaults.rootFolderPath;
      }

      const artist = await lidarrClient.addArtist({
        foreignArtistId,
        artistName,
        qualityProfileId,
        metadataProfileId,
        rootFolderPath,
        monitored,
        addOptions: { searchForMissingAlbums: true },
      });

      await lidarrClient.runCommand("ArtistSearch", { artistId: artist.id });

      const record = createRequest(req.user!.userId, "artist", artist.id, artistName, coverUrl ?? null);
      res.status(201).json(record);
    } catch (err) {
      next(err);
    }
  },
);

const albumRequestSchema = z.object({
  albumId: z.number().int().positive(),
  coverUrl: z.string().url().optional().nullable(),
});

/** POST /api/requests/album — monitor album in Lidarr and create request record */
router.post(
  "/album",
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const parsed = albumRequestSchema.safeParse(req.body);
      if (!parsed.success) {
        next(
          createError(
            400,
            "VALIDATION_ERROR",
            parsed.error.issues.map((i) => i.message).join(", "),
          ),
        );
        return;
      }

      const { albumId, coverUrl } = parsed.data;

      const [album] = await Promise.all([
        lidarrClient.getAlbum(albumId),
        lidarrClient.monitorAlbum([albumId], true),
      ]);
      await lidarrClient.runCommand("AlbumSearch", { albumIds: [albumId] });

      const albumName = album.title ?? `Album #${albumId}`;
      const record = createRequest(req.user!.userId, "album", albumId, albumName, coverUrl ?? null);
      res.status(201).json(record);
    } catch (err) {
      next(err);
    }
  },
);

/** GET /api/requests — list current user's requests with live Lidarr status */
router.get("/", async (req: Request, res: Response, next: NextFunction) => {
  try {
    const records = await listRequests(req.user!.userId);
    res.json(records);
  } catch (err) {
    next(err);
  }
});

export default router;
