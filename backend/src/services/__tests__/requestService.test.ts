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
    CREATE TABLE requests (
      id TEXT PRIMARY KEY NOT NULL,
      userId TEXT NOT NULL,
      type TEXT NOT NULL,
      lidarrId INTEGER NOT NULL,
      name TEXT NOT NULL DEFAULT '',
      coverUrl TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      requestedAt TEXT NOT NULL,
      resolvedAt TEXT
    );
  `);

  return { db: drizzle(sqlite, { schema: schemaModule.schema }), sqlite };
});

vi.mock("../lidarrClient.js", () => ({
  getArtist: vi.fn(),
  getAlbum: vi.fn(),
  getQueue: vi.fn(),
}));

import * as lidarrClient from "../lidarrClient.js";
import { db } from "../../db/connection.js";
import { requests } from "../../db/schema.js";
import { createRequest, listRequests } from "../requestService.js";

const TEST_USER_ID = "user-test-1";

beforeEach(() => {
  db.delete(requests).run();
  vi.clearAllMocks();
});

describe("createRequest", () => {
  it("creates an artist request and returns a DTO", () => {
    const result = createRequest(TEST_USER_ID, "artist", 42, "The Beatles");

    expect(result.id).toBeDefined();
    expect(result.type).toBe("artist");
    expect(result.lidarrId).toBe(42);
    expect(result.name).toBe("The Beatles");
    expect(result.status).toBe("pending");
    expect(result.requestedAt).toBeDefined();
    expect(result.resolvedAt).toBeNull();
  });

  it("creates an album request", () => {
    const result = createRequest(TEST_USER_ID, "album", 99, "Abbey Road");
    expect(result.type).toBe("album");
    expect(result.lidarrId).toBe(99);
    expect(result.name).toBe("Abbey Road");
  });

  it("persists the request to the database", () => {
    createRequest(TEST_USER_ID, "artist", 1, "Artist One");
    const rows = db.select().from(requests).all();
    expect(rows).toHaveLength(1);
    expect(rows[0]?.userId).toBe(TEST_USER_ID);
    expect(rows[0]?.name).toBe("Artist One");
  });

  it("each call returns a unique id", () => {
    const r1 = createRequest(TEST_USER_ID, "artist", 1, "Artist A");
    const r2 = createRequest(TEST_USER_ID, "artist", 2, "Artist B");
    expect(r1.id).not.toBe(r2.id);
  });
});

describe("listRequests", () => {
  it("returns empty array when user has no requests", async () => {
    const result = await listRequests(TEST_USER_ID);
    expect(result).toEqual([]);
  });

  it("returns all requests for user when all are already available (no Lidarr calls)", async () => {
    // Insert an already-available request directly
    db.insert(requests)
      .values({
        id: "req-1",
        userId: TEST_USER_ID,
        type: "artist",
        lidarrId: 1,
        name: "Artist One",
        status: "available",
        requestedAt: new Date().toISOString(),
        resolvedAt: new Date().toISOString(),
      })
      .run();

    const result = await listRequests(TEST_USER_ID);
    expect(result).toHaveLength(1);
    expect(result[0]?.status).toBe("available");
    // No Lidarr calls needed since all requests are already available
    expect(lidarrClient.getQueue).not.toHaveBeenCalled();
  });

  it("polls Lidarr for pending artist requests and marks available when trackFileCount > 0", async () => {
    createRequest(TEST_USER_ID, "artist", 10, "Artist Ten");
    vi.mocked(lidarrClient.getQueue).mockResolvedValue({
      totalRecords: 0,
      records: [],
    } as never);
    vi.mocked(lidarrClient.getArtist).mockResolvedValue({
      id: 10,
      artistName: "Artist",
      statistics: { trackFileCount: 5 },
    } as never);

    const result = await listRequests(TEST_USER_ID);
    expect(result[0]?.status).toBe("available");
    expect(result[0]?.resolvedAt).toBeDefined();
  });

  it("marks artist as downloading when in queue", async () => {
    createRequest(TEST_USER_ID, "artist", 10, "Artist Ten");
    vi.mocked(lidarrClient.getQueue).mockResolvedValue({
      totalRecords: 1,
      records: [{ artistId: 10, albumId: null }],
    } as never);
    vi.mocked(lidarrClient.getArtist).mockResolvedValue({
      id: 10,
      artistName: "Artist",
      statistics: { trackFileCount: 0 },
    } as never);

    const result = await listRequests(TEST_USER_ID);
    expect(result[0]?.status).toBe("downloading");
  });

  it("polls Lidarr for pending album requests and marks available when trackFileCount > 0", async () => {
    createRequest(TEST_USER_ID, "album", 20, "Album Twenty");
    vi.mocked(lidarrClient.getQueue).mockResolvedValue({
      totalRecords: 0,
      records: [],
    } as never);
    vi.mocked(lidarrClient.getAlbum).mockResolvedValue({
      id: 20,
      title: "Album",
      statistics: { trackFileCount: 3 },
    } as never);

    const result = await listRequests(TEST_USER_ID);
    expect(result[0]?.status).toBe("available");
  });

  it("marks album as downloading when in queue", async () => {
    createRequest(TEST_USER_ID, "album", 20, "Album Twenty");
    vi.mocked(lidarrClient.getQueue).mockResolvedValue({
      totalRecords: 1,
      records: [{ albumId: 20, artistId: null }],
    } as never);
    vi.mocked(lidarrClient.getAlbum).mockResolvedValue({
      id: 20,
      title: "Album",
      statistics: { trackFileCount: 0 },
    } as never);

    const result = await listRequests(TEST_USER_ID);
    expect(result[0]?.status).toBe("downloading");
  });

  it("swallows queue fetch errors and proceeds with pending status", async () => {
    createRequest(TEST_USER_ID, "artist", 10, "Artist Ten");
    vi.mocked(lidarrClient.getQueue).mockRejectedValue(
      new Error("Queue unavailable"),
    );
    vi.mocked(lidarrClient.getArtist).mockResolvedValue({
      id: 10,
      artistName: "Artist",
      statistics: { trackFileCount: 0 },
    } as never);

    const result = await listRequests(TEST_USER_ID);
    // Should not throw; status stays pending since not in queue and no files
    expect(result[0]?.status).toBe("pending");
  });

  it("swallows individual status check errors and leaves request as pending", async () => {
    createRequest(TEST_USER_ID, "artist", 10, "Artist Ten");
    vi.mocked(lidarrClient.getQueue).mockResolvedValue({
      totalRecords: 0,
      records: [],
    } as never);
    vi.mocked(lidarrClient.getArtist).mockRejectedValue(
      new Error("Lidarr down"),
    );

    const result = await listRequests(TEST_USER_ID);
    expect(result[0]?.status).toBe("pending");
  });

  it("leaves request pending when trackFileCount is 0 and not in queue", async () => {
    createRequest(TEST_USER_ID, "artist", 10, "Artist Ten");
    vi.mocked(lidarrClient.getQueue).mockResolvedValue({
      totalRecords: 0,
      records: [],
    } as never);
    vi.mocked(lidarrClient.getArtist).mockResolvedValue({
      id: 10,
      artistName: "Artist",
      statistics: { trackFileCount: 0 },
    } as never);

    const result = await listRequests(TEST_USER_ID);
    expect(result[0]?.status).toBe("pending");
  });

  it("handles statistics being undefined/null gracefully", async () => {
    createRequest(TEST_USER_ID, "artist", 10, "Artist Ten");
    vi.mocked(lidarrClient.getQueue).mockResolvedValue({
      totalRecords: 0,
      records: [],
    } as never);
    vi.mocked(lidarrClient.getArtist).mockResolvedValue({
      id: 10,
      artistName: "Artist",
      statistics: undefined,
    } as never);

    const result = await listRequests(TEST_USER_ID);
    expect(result[0]?.status).toBe("pending"); // null coalescing defaults to 0
  });

  it("handles mix of available and pending requests", async () => {
    db.insert(requests)
      .values({
        id: "req-available",
        userId: TEST_USER_ID,
        type: "artist",
        lidarrId: 1,
        name: "Artist One",
        status: "available",
        requestedAt: new Date().toISOString(),
        resolvedAt: new Date().toISOString(),
      })
      .run();
    createRequest(TEST_USER_ID, "artist", 2, "Artist Two");

    vi.mocked(lidarrClient.getQueue).mockResolvedValue({
      totalRecords: 0,
      records: [],
    } as never);
    vi.mocked(lidarrClient.getArtist).mockResolvedValue({
      id: 2,
      artistName: "Artist 2",
      statistics: { trackFileCount: 0 },
    } as never);

    const result = await listRequests(TEST_USER_ID);
    expect(result).toHaveLength(2);
    const statuses = result.map((r) => r.status);
    expect(statuses).toContain("available");
    expect(statuses).toContain("pending");
  });

  it("only returns requests for the specified user", async () => {
    createRequest(TEST_USER_ID, "artist", 1, "Artist One");
    createRequest("other-user", "artist", 2, "Artist Two");

    vi.mocked(lidarrClient.getQueue).mockResolvedValue({
      totalRecords: 0,
      records: [],
    } as never);
    vi.mocked(lidarrClient.getArtist).mockResolvedValue({
      id: 1,
      artistName: "Artist",
      statistics: { trackFileCount: 0 },
    } as never);

    const result = await listRequests(TEST_USER_ID);
    expect(result).toHaveLength(1);
  });
});
