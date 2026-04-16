import { randomUUID } from "crypto";
import { eq, and, gte, sql, asc, count } from "drizzle-orm";
import { db } from "../db/connection.js";
import { playlists, playlistTracks } from "../db/schema.js";
import { createError } from "../middleware/errorHandler.js";

export interface PlaylistSummary {
  id: string;
  name: string;
  trackCount: number;
  createdAt: string;
}

export interface PlaylistDetail {
  id: string;
  name: string;
  tracks: { lidarrTrackId: number; position: number }[];
}

function assertOwnership(
  playlist: { userId: string } | undefined,
  userId: string,
): asserts playlist is { userId: string } & Record<string, unknown> {
  if (!playlist || playlist.userId !== userId) {
    throw createError(404, "NOT_FOUND", "Playlist not found");
  }
}

export function listPlaylists(userId: string): PlaylistSummary[] {
  const rows = db
    .select({
      id: playlists.id,
      name: playlists.name,
      createdAt: playlists.createdAt,
      trackCount: count(playlistTracks.id),
    })
    .from(playlists)
    .leftJoin(playlistTracks, eq(playlistTracks.playlistId, playlists.id))
    .where(eq(playlists.userId, userId))
    .groupBy(playlists.id)
    .all();
  return rows.map((p) => ({
    id: p.id,
    name: p.name,
    trackCount: Number(p.trackCount),
    createdAt: p.createdAt,
  }));
}

export function createPlaylist(
  userId: string,
  name: string,
): { id: string; name: string; createdAt: string } {
  const id = randomUUID();
  const now = new Date().toISOString();
  db.insert(playlists)
    .values({ id, userId, name, createdAt: now, updatedAt: now })
    .run();
  return { id, name, createdAt: now };
}

export function getPlaylist(id: string, userId: string): PlaylistDetail {
  const playlist = db
    .select()
    .from(playlists)
    .where(eq(playlists.id, id))
    .get();
  assertOwnership(playlist, userId);

  const tracks = db
    .select({
      lidarrTrackId: playlistTracks.lidarrTrackId,
      position: playlistTracks.position,
    })
    .from(playlistTracks)
    .where(eq(playlistTracks.playlistId, id))
    .orderBy(asc(playlistTracks.position))
    .all();

  return { id: playlist.id, name: playlist.name, tracks };
}

export function updatePlaylist(
  id: string,
  userId: string,
  name: string,
): { id: string; name: string; updatedAt: string } {
  const playlist = db
    .select()
    .from(playlists)
    .where(eq(playlists.id, id))
    .get();
  assertOwnership(playlist, userId);

  const updatedAt = new Date().toISOString();
  db.update(playlists)
    .set({ name, updatedAt })
    .where(eq(playlists.id, id))
    .run();
  return { id, name, updatedAt };
}

export function deletePlaylist(id: string, userId: string): void {
  const playlist = db
    .select()
    .from(playlists)
    .where(eq(playlists.id, id))
    .get();
  assertOwnership(playlist, userId);
  db.delete(playlists).where(eq(playlists.id, id)).run();
}

export function addTracks(
  playlistId: string,
  userId: string,
  trackIds: number[],
  insertPosition?: number,
): number {
  const playlist = db
    .select()
    .from(playlists)
    .where(eq(playlists.id, playlistId))
    .get();
  assertOwnership(playlist, userId);

  const maxRow = db
    .select({ max: sql<number | null>`max(${playlistTracks.position})` })
    .from(playlistTracks)
    .where(eq(playlistTracks.playlistId, playlistId))
    .get();
  const currentMax = maxRow?.max ?? -1;

  let startPosition: number;
  if (insertPosition !== undefined) {
    db.update(playlistTracks)
      .set({ position: sql`${playlistTracks.position} + ${trackIds.length}` })
      .where(
        and(
          eq(playlistTracks.playlistId, playlistId),
          gte(playlistTracks.position, insertPosition),
        ),
      )
      .run();
    startPosition = insertPosition;
  } else {
    startPosition = currentMax + 1;
  }

  let added = 0;
  for (let i = 0; i < trackIds.length; i++) {
    const trackId = trackIds[i];
    if (trackId === undefined) continue;
    try {
      db.insert(playlistTracks)
        .values({
          id: randomUUID(),
          playlistId,
          lidarrTrackId: trackId,
          position: startPosition + i,
        })
        .run();
      added++;
    } catch {
      // Skip duplicate tracks (unique constraint violation)
    }
  }
  return added;
}

export function removeTrack(
  playlistId: string,
  userId: string,
  lidarrTrackId: number,
): void {
  const playlist = db
    .select()
    .from(playlists)
    .where(eq(playlists.id, playlistId))
    .get();
  assertOwnership(playlist, userId);

  const track = db
    .select()
    .from(playlistTracks)
    .where(
      and(
        eq(playlistTracks.playlistId, playlistId),
        eq(playlistTracks.lidarrTrackId, lidarrTrackId),
      ),
    )
    .get();

  if (!track) {
    throw createError(404, "NOT_FOUND", "Track not found in playlist");
  }

  const { position } = track;
  db.delete(playlistTracks)
    .where(
      and(
        eq(playlistTracks.playlistId, playlistId),
        eq(playlistTracks.lidarrTrackId, lidarrTrackId),
      ),
    )
    .run();

  // Repack: shift all tracks after the deleted position down by 1
  db.update(playlistTracks)
    .set({ position: sql`${playlistTracks.position} - 1` })
    .where(
      and(
        eq(playlistTracks.playlistId, playlistId),
        gte(playlistTracks.position, position),
      ),
    )
    .run();
}

export function reorderTracks(
  playlistId: string,
  userId: string,
  orderedTrackIds: number[],
): void {
  const playlist = db
    .select()
    .from(playlists)
    .where(eq(playlists.id, playlistId))
    .get();
  assertOwnership(playlist, userId);

  const existing = db
    .select({ lidarrTrackId: playlistTracks.lidarrTrackId })
    .from(playlistTracks)
    .where(eq(playlistTracks.playlistId, playlistId))
    .all();

  const existingSet = new Set(existing.map((t) => t.lidarrTrackId));
  for (const id of orderedTrackIds) {
    if (!existingSet.has(id)) {
      throw createError(
        400,
        "VALIDATION_ERROR",
        `Track ${id} is not in this playlist`,
      );
    }
  }

  db.transaction((tx) => {
    for (let i = 0; i < orderedTrackIds.length; i++) {
      const trackId = orderedTrackIds[i];
      if (trackId === undefined) continue;
      tx.update(playlistTracks)
        .set({ position: i })
        .where(
          and(
            eq(playlistTracks.playlistId, playlistId),
            eq(playlistTracks.lidarrTrackId, trackId),
          ),
        )
        .run();
    }
  });
}
