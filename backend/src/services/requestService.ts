import { randomUUID } from "crypto";
import { eq } from "drizzle-orm";
import { db } from "../db/connection.js";
import { requests } from "../db/schema.js";
import * as lidarrClient from "./lidarrClient.js";
import type { MusicRequest } from "../types/api.js";

type RequestRow = typeof requests.$inferSelect;

function toDto(r: RequestRow): MusicRequest {
  return {
    id: r.id,
    type: r.type,
    lidarrId: r.lidarrId,
    name: r.name,
    status: r.status,
    requestedAt: r.requestedAt,
    resolvedAt: r.resolvedAt,
  };
}

export function createRequest(
  userId: string,
  type: string,
  lidarrId: number,
  name: string,
): MusicRequest {
  const id = randomUUID();
  const requestedAt = new Date().toISOString();
  db.insert(requests)
    .values({ id, userId, type, lidarrId, name, status: "pending", requestedAt })
    .run();
  return {
    id,
    type,
    lidarrId,
    name,
    status: "pending",
    requestedAt,
    resolvedAt: null,
  };
}

export async function listRequests(userId: string): Promise<MusicRequest[]> {
  const rows = db
    .select()
    .from(requests)
    .where(eq(requests.userId, userId))
    .all();
  const pending = rows.filter((r) => r.status !== "available");

  if (pending.length === 0) {
    return rows.map(toDto);
  }

  // Fetch queue once — best-effort; errors are swallowed
  const queueAlbumIds = new Set<number>();
  const queueArtistIds = new Set<number>();
  try {
    const queue = await lidarrClient.getQueue();
    for (const item of queue.records) {
      if (item.albumId != null) queueAlbumIds.add(item.albumId);
      if (item.artistId != null) queueArtistIds.add(item.artistId);
    }
  } catch {
    // queue check is best-effort; proceed without it
  }

  for (const row of pending) {
    let newStatus = row.status;
    try {
      if (row.type === "artist") {
        const artist = await lidarrClient.getArtist(row.lidarrId);
        if ((artist.statistics?.trackFileCount ?? 0) > 0) {
          newStatus = "available";
        } else if (queueArtistIds.has(row.lidarrId)) {
          newStatus = "downloading";
        }
      } else if (row.type === "album") {
        const album = await lidarrClient.getAlbum(row.lidarrId);
        if ((album.statistics?.trackFileCount ?? 0) > 0) {
          newStatus = "available";
        } else if (queueAlbumIds.has(row.lidarrId)) {
          newStatus = "downloading";
        }
      }
    } catch {
      // status check is best-effort; leave as-is
    }

    if (newStatus !== row.status) {
      const resolvedAt =
        newStatus === "available" ? new Date().toISOString() : null;
      db.update(requests)
        .set({ status: newStatus, resolvedAt })
        .where(eq(requests.id, row.id))
        .run();
      row.status = newStatus;
      row.resolvedAt = resolvedAt;
    }
  }

  return rows.map(toDto);
}
