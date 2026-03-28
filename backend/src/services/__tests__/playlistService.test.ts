import { describe, it, expect, beforeEach, vi } from "vitest";

vi.mock("../../config/env.js", () => ({
  env: {
    PORT: 3001,
    NODE_ENV: "test" as const,
    JWT_ACCESS_SECRET: "test-access-secret-at-least-32-chars-long",
    JWT_REFRESH_SECRET: "test-refresh-secret-at-least-32-chars-long",
    JWT_ACCESS_EXPIRY: "15m",
    JWT_REFRESH_EXPIRY: "30d",
    DB_PATH: ":memory:",
    LOG_PATH: "./logs",
    LIDARR_URL: "http://localhost:8686",
    LIDARR_API_KEY: "test",
    MUSIC_LIBRARY_PATH: "/music",
    OFFLINE_STORAGE_PATH: "./data/offline",
    ADMIN_USERNAME: "admin",
    ADMIN_PASSWORD: "adminpassword123",
    TEMP_DIR: "/tmp/bimusic",
    API_BASE_URL: "http://localhost:3000",
  },
}));

vi.mock("../../utils/logger.js", () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    child: vi.fn(() => ({
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
      debug: vi.fn(),
    })),
  },
}));

vi.mock("../../db/connection.js", async () => {
  const BetterSqlite3 = (await import("better-sqlite3")).default;
  const { drizzle } = await import("drizzle-orm/better-sqlite3");
  const schemaModule = await import("../../db/schema.js");

  const sqlite = new BetterSqlite3(":memory:");
  sqlite.pragma("foreign_keys = OFF");
  sqlite.exec(`
    CREATE TABLE users (
      id TEXT PRIMARY KEY NOT NULL,
      username TEXT NOT NULL UNIQUE,
      displayName TEXT NOT NULL,
      passwordHash TEXT NOT NULL,
      isAdmin INTEGER DEFAULT 0 NOT NULL,
      createdAt TEXT NOT NULL
    );
    CREATE TABLE playlists (
      id TEXT PRIMARY KEY NOT NULL,
      userId TEXT NOT NULL,
      name TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL
    );
    CREATE TABLE playlist_tracks (
      id TEXT PRIMARY KEY NOT NULL,
      playlistId TEXT NOT NULL,
      lidarrTrackId INTEGER NOT NULL,
      position INTEGER NOT NULL,
      UNIQUE(playlistId, lidarrTrackId)
    );
  `);

  return { db: drizzle(sqlite, { schema: schemaModule.schema }), sqlite };
});

import { db } from "../../db/connection.js";
import { playlists, playlistTracks } from "../../db/schema.js";
import {
  listPlaylists,
  createPlaylist,
  getPlaylist,
  updatePlaylist,
  deletePlaylist,
  addTracks,
  removeTrack,
  reorderTracks,
} from "../playlistService.js";

const TEST_USER_ID = "user-1";
const OTHER_USER_ID = "user-2";

beforeEach(() => {
  db.delete(playlistTracks).run();
  db.delete(playlists).run();
});

describe("listPlaylists", () => {
  it("returns empty array when user has no playlists", () => {
    const result = listPlaylists(TEST_USER_ID);
    expect(result).toEqual([]);
  });

  it("returns playlists for the given user with track count", () => {
    const { id } = createPlaylist(TEST_USER_ID, "My Playlist");
    addTracks(id, TEST_USER_ID, [101, 102]);

    const result = listPlaylists(TEST_USER_ID);
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      id,
      name: "My Playlist",
      trackCount: 2,
    });
  });

  it("only returns playlists for the requesting user", () => {
    createPlaylist(TEST_USER_ID, "User1 Playlist");
    createPlaylist(OTHER_USER_ID, "User2 Playlist");

    const result = listPlaylists(TEST_USER_ID);
    expect(result).toHaveLength(1);
    expect(result[0]?.name).toBe("User1 Playlist");
  });

  it("returns trackCount 0 for empty playlists", () => {
    createPlaylist(TEST_USER_ID, "Empty");
    const result = listPlaylists(TEST_USER_ID);
    expect(result[0]?.trackCount).toBe(0);
  });
});

describe("createPlaylist", () => {
  it("creates a playlist and returns id, name, createdAt", () => {
    const result = createPlaylist(TEST_USER_ID, "Rock Classics");
    expect(result.id).toBeDefined();
    expect(result.name).toBe("Rock Classics");
    expect(result.createdAt).toBeDefined();
  });

  it("creates multiple playlists independently", () => {
    const p1 = createPlaylist(TEST_USER_ID, "Playlist A");
    const p2 = createPlaylist(TEST_USER_ID, "Playlist B");
    expect(p1.id).not.toBe(p2.id);

    const all = listPlaylists(TEST_USER_ID);
    expect(all).toHaveLength(2);
  });
});

describe("getPlaylist", () => {
  it("returns playlist with ordered tracks", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Ordered");
    addTracks(id, TEST_USER_ID, [10, 20, 30]);

    const result = getPlaylist(id, TEST_USER_ID);
    expect(result.id).toBe(id);
    expect(result.name).toBe("Ordered");
    expect(result.tracks).toHaveLength(3);
    expect(result.tracks.map((t) => t.lidarrTrackId)).toEqual([10, 20, 30]);
  });

  it("throws 404 when playlist does not exist", () => {
    expect(() => getPlaylist("nonexistent", TEST_USER_ID)).toThrow();
  });

  it("throws 404 when playlist belongs to another user", () => {
    const { id } = createPlaylist(OTHER_USER_ID, "Other's Playlist");
    expect(() => getPlaylist(id, TEST_USER_ID)).toThrow();
  });

  it("returns empty tracks array for new playlist", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Empty");
    const result = getPlaylist(id, TEST_USER_ID);
    expect(result.tracks).toEqual([]);
  });
});

describe("updatePlaylist", () => {
  it("updates the playlist name", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Old Name");
    const result = updatePlaylist(id, TEST_USER_ID, "New Name");
    expect(result.name).toBe("New Name");
    expect(result.id).toBe(id);
    expect(result.updatedAt).toBeDefined();
  });

  it("throws 404 when playlist does not exist", () => {
    expect(() => updatePlaylist("nonexistent", TEST_USER_ID, "Name")).toThrow();
  });

  it("throws 404 when playlist belongs to another user", () => {
    const { id } = createPlaylist(OTHER_USER_ID, "Other");
    expect(() => updatePlaylist(id, TEST_USER_ID, "Hijacked")).toThrow();
  });
});

describe("deletePlaylist", () => {
  it("deletes the playlist", () => {
    const { id } = createPlaylist(TEST_USER_ID, "To Delete");
    deletePlaylist(id, TEST_USER_ID);
    expect(listPlaylists(TEST_USER_ID)).toHaveLength(0);
  });

  it("throws 404 when playlist does not exist", () => {
    expect(() => deletePlaylist("nonexistent", TEST_USER_ID)).toThrow();
  });

  it("throws 404 when playlist belongs to another user", () => {
    const { id } = createPlaylist(OTHER_USER_ID, "Other");
    expect(() => deletePlaylist(id, TEST_USER_ID)).toThrow();
  });
});

describe("addTracks", () => {
  it("appends tracks to the end of the playlist", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Test");
    const added = addTracks(id, TEST_USER_ID, [10, 20, 30]);
    expect(added).toBe(3);

    const detail = getPlaylist(id, TEST_USER_ID);
    expect(detail.tracks.map((t) => t.position)).toEqual([0, 1, 2]);
  });

  it("inserts tracks at a specific position, shifting existing ones", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Ordered");
    addTracks(id, TEST_USER_ID, [10, 20, 30]);
    addTracks(id, TEST_USER_ID, [99], 1); // insert at position 1

    const detail = getPlaylist(id, TEST_USER_ID);
    const positions = detail.tracks.map((t) => ({
      trackId: t.lidarrTrackId,
      position: t.position,
    }));
    const track99 = positions.find((p) => p.trackId === 99);
    expect(track99?.position).toBe(1);
    // Original position 1 (trackId 20) should have shifted to 2
    const track20 = positions.find((p) => p.trackId === 20);
    expect(track20?.position).toBe(2);
  });

  it("silently skips duplicate tracks", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Dedup");
    addTracks(id, TEST_USER_ID, [10]);
    const added = addTracks(id, TEST_USER_ID, [10]); // duplicate
    expect(added).toBe(0);
  });

  it("throws 404 when playlist does not exist", () => {
    expect(() => addTracks("nonexistent", TEST_USER_ID, [1])).toThrow();
  });

  it("throws 404 when playlist belongs to another user", () => {
    const { id } = createPlaylist(OTHER_USER_ID, "Other");
    expect(() => addTracks(id, TEST_USER_ID, [1])).toThrow();
  });

  it("returns 0 when track ids array is empty", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Empty Add");
    const added = addTracks(id, TEST_USER_ID, []);
    expect(added).toBe(0);
  });
});

describe("removeTrack", () => {
  it("removes a track and repacks positions", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Test");
    addTracks(id, TEST_USER_ID, [10, 20, 30]);

    removeTrack(id, TEST_USER_ID, 20); // remove middle track

    const detail = getPlaylist(id, TEST_USER_ID);
    expect(detail.tracks).toHaveLength(2);
    expect(detail.tracks.map((t) => t.lidarrTrackId)).toEqual([10, 30]);
    // positions should be repacked: 0, 1
    expect(detail.tracks.map((t) => t.position)).toEqual([0, 1]);
  });

  it("throws 404 when track is not in playlist", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Test");
    expect(() => removeTrack(id, TEST_USER_ID, 999)).toThrow();
  });

  it("throws 404 when playlist does not exist", () => {
    expect(() => removeTrack("nonexistent", TEST_USER_ID, 1)).toThrow();
  });

  it("throws 404 when playlist belongs to another user", () => {
    const { id } = createPlaylist(OTHER_USER_ID, "Other");
    expect(() => removeTrack(id, TEST_USER_ID, 1)).toThrow();
  });
});

describe("reorderTracks", () => {
  it("reorders tracks according to the provided order", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Reorder");
    addTracks(id, TEST_USER_ID, [10, 20, 30]);

    reorderTracks(id, TEST_USER_ID, [30, 10, 20]);

    const detail = getPlaylist(id, TEST_USER_ID);
    // After reorder, positions should reflect new order
    const byTrackId = Object.fromEntries(
      detail.tracks.map((t) => [t.lidarrTrackId, t.position]),
    );
    expect(byTrackId[30]).toBe(0);
    expect(byTrackId[10]).toBe(1);
    expect(byTrackId[20]).toBe(2);
  });

  it("throws 400 when a track id is not in the playlist", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Reorder");
    addTracks(id, TEST_USER_ID, [10, 20]);

    expect(() => reorderTracks(id, TEST_USER_ID, [10, 20, 999])).toThrow();
  });

  it("throws 404 when playlist does not exist", () => {
    expect(() => reorderTracks("nonexistent", TEST_USER_ID, [1, 2])).toThrow();
  });

  it("throws 404 when playlist belongs to another user", () => {
    const { id } = createPlaylist(OTHER_USER_ID, "Other");
    expect(() => reorderTracks(id, TEST_USER_ID, [1])).toThrow();
  });

  it("succeeds with an empty reorder list", () => {
    const { id } = createPlaylist(TEST_USER_ID, "Empty Reorder");
    expect(() => reorderTracks(id, TEST_USER_ID, [])).not.toThrow();
  });
});
