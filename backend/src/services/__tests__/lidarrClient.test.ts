import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import nock from "nock";

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
    LIDARR_API_KEY: "test-api-key",
    MUSIC_LIBRARY_PATH: "/music",
    OFFLINE_STORAGE_PATH: "./data/offline",
    ADMIN_USERNAME: "admin",
    ADMIN_PASSWORD: "adminpassword123",
    TEMP_DIR: "/tmp/bimusic",
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

const BASE = "http://localhost:8686";
const API_KEY = "test-api-key";

// Minimal stubs matching only the fields our types require
const stubArtist = {
  id: 1,
  artistName: "Test Artist",
  foreignArtistId: "abc123",
  overview: "An overview",
  artistType: "Person",
  status: "ended",
  ended: true,
  images: [
    {
      url: "/image.jpg",
      coverType: "poster",
      extension: ".jpg",
      remoteUrl: null,
    },
  ],
  path: "/music/artist",
  monitored: true,
  genres: ["Rock"],
  sortName: "test artist",
  ratings: { votes: 100, value: 4.5 },
};

const stubAlbum = {
  id: 10,
  title: "Test Album",
  disambiguation: null,
  overview: "Album overview",
  artistId: 1,
  foreignAlbumId: "alb456",
  monitored: true,
  duration: 3600,
  albumType: "Studio",
  releaseDate: "2020-01-01",
  artist: stubArtist,
  images: [],
  genres: ["Rock"],
  ratings: { votes: 50, value: 4.0 },
  remoteCover: null,
};

const stubTrackFile = {
  id: 100,
  artistId: 1,
  albumId: 10,
  path: "/music/track.flac",
  size: 50000000,
  dateAdded: "2021-01-01T00:00:00Z",
  quality: { quality: { id: 1, name: "FLAC" } },
};

const stubTrack = {
  id: 5,
  artistId: 1,
  albumId: 10,
  trackFileId: 100,
  foreignTrackId: "trk789",
  trackNumber: "1",
  absoluteTrackNumber: 1,
  title: "Test Track",
  duration: 180,
  hasFile: true,
  explicit: false,
  mediumNumber: 1,
  trackFile: stubTrackFile,
  artist: stubArtist,
};

const stubCommand = {
  id: 200,
  name: "RefreshArtist",
  commandName: "RefreshArtist",
  status: "queued",
  queued: "2021-01-01T00:00:00Z",
  started: null,
  ended: null,
};

describe("lidarrClient", () => {
  beforeEach(() => {
    nock.cleanAll();
  });

  afterEach(() => {
    nock.cleanAll();
  });

  describe("getArtists", () => {
    it("returns artist list from GET /artist", async () => {
      nock(BASE)
        .get("/api/v1/artist")
        .matchHeader("X-Api-Key", API_KEY)
        .reply(200, [stubArtist]);

      const { getArtists } = await import("../lidarrClient.js");
      const result = await getArtists();

      expect(result).toHaveLength(1);
      expect(result[0].id).toBe(1);
      expect(result[0].artistName).toBe("Test Artist");
    });
  });

  describe("getArtist", () => {
    it("returns single artist from GET /artist/:id", async () => {
      nock(BASE)
        .get("/api/v1/artist/1")
        .matchHeader("X-Api-Key", API_KEY)
        .reply(200, stubArtist);

      const { getArtist } = await import("../lidarrClient.js");
      const result = await getArtist(1);

      expect(result.id).toBe(1);
      expect(result.foreignArtistId).toBe("abc123");
    });

    it("throws 404 AppError when Lidarr returns 404", async () => {
      nock(BASE).get("/api/v1/artist/999").reply(404, { message: "Not Found" });

      const { getArtist } = await import("../lidarrClient.js");

      await expect(getArtist(999)).rejects.toMatchObject({
        statusCode: 404,
        code: "NOT_FOUND",
      });
    });

    it("throws 502 AppError when Lidarr returns 500", async () => {
      nock(BASE)
        .get("/api/v1/artist/1")
        .reply(500, { message: "Internal Error" });

      const { getArtist } = await import("../lidarrClient.js");

      await expect(getArtist(1)).rejects.toMatchObject({
        statusCode: 502,
        code: "LIDARR_ERROR",
      });
    });
  });

  describe("lookupArtist", () => {
    it("sends term as query param to GET /artist/lookup", async () => {
      nock(BASE)
        .get("/api/v1/artist/lookup")
        .query({ term: "Beatles" })
        .reply(200, [stubArtist]);

      const { lookupArtist } = await import("../lidarrClient.js");
      const result = await lookupArtist("Beatles");

      expect(result[0].artistName).toBe("Test Artist");
    });
  });

  describe("addArtist", () => {
    it("POSTs payload to /artist and returns created artist", async () => {
      const payload = { foreignArtistId: "abc123", qualityProfileId: 1 };
      nock(BASE).post("/api/v1/artist", payload).reply(201, stubArtist);

      const { addArtist } = await import("../lidarrClient.js");
      const result = await addArtist(payload);

      expect(result.id).toBe(1);
    });
  });

  describe("getAlbums", () => {
    it("returns albums list from GET /album without filter", async () => {
      nock(BASE).get("/api/v1/album").reply(200, [stubAlbum]);

      const { getAlbums } = await import("../lidarrClient.js");
      const result = await getAlbums();

      expect(result).toHaveLength(1);
      expect(result[0].title).toBe("Test Album");
    });

    it("sends artistId as query param when provided", async () => {
      nock(BASE)
        .get("/api/v1/album")
        .query({ artistId: "1" })
        .reply(200, [stubAlbum]);

      const { getAlbums } = await import("../lidarrClient.js");
      const result = await getAlbums(1);

      expect(result[0].artistId).toBe(1);
    });
  });

  describe("getAlbum", () => {
    it("returns single album from GET /album/:id", async () => {
      nock(BASE).get("/api/v1/album/10").reply(200, stubAlbum);

      const { getAlbum } = await import("../lidarrClient.js");
      const result = await getAlbum(10);

      expect(result.id).toBe(10);
      expect(result.duration).toBe(3600);
    });
  });

  describe("lookupAlbum", () => {
    it("sends term as query param to GET /album/lookup", async () => {
      nock(BASE)
        .get("/api/v1/album/lookup")
        .query({ term: "Abbey Road" })
        .reply(200, [stubAlbum]);

      const { lookupAlbum } = await import("../lidarrClient.js");
      const result = await lookupAlbum("Abbey Road");

      expect(result[0].title).toBe("Test Album");
    });
  });

  describe("monitorAlbum", () => {
    it("PUTs to /album/monitor with ids and monitored flag", async () => {
      nock(BASE)
        .put("/api/v1/album/monitor", { albumIds: [10, 11], monitored: true })
        .reply(202);

      const { monitorAlbum } = await import("../lidarrClient.js");
      await expect(monitorAlbum([10, 11], true)).resolves.toBeUndefined();
    });
  });

  describe("getTracks", () => {
    it("returns tracks from GET /track without filter", async () => {
      nock(BASE).get("/api/v1/track").reply(200, [stubTrack]);

      const { getTracks } = await import("../lidarrClient.js");
      const result = await getTracks();

      expect(result[0].title).toBe("Test Track");
    });

    it("sends albumId query param when provided", async () => {
      nock(BASE)
        .get("/api/v1/track")
        .query({ albumId: "10" })
        .reply(200, [stubTrack]);

      const { getTracks } = await import("../lidarrClient.js");
      const result = await getTracks(10);

      expect(result[0].albumId).toBe(10);
    });
  });

  describe("getTrack", () => {
    it("returns single track from GET /track/:id", async () => {
      nock(BASE).get("/api/v1/track/5").reply(200, stubTrack);

      const { getTrack } = await import("../lidarrClient.js");
      const result = await getTrack(5);

      expect(result.id).toBe(5);
      expect(result.duration).toBe(180);
    });
  });

  describe("getTrackFile", () => {
    it("returns track file from GET /trackfile/:id", async () => {
      nock(BASE).get("/api/v1/trackfile/100").reply(200, stubTrackFile);

      const { getTrackFile } = await import("../lidarrClient.js");
      const result = await getTrackFile(100);

      expect(result.id).toBe(100);
      expect(result.path).toBe("/music/track.flac");
    });
  });

  describe("getTrackFiles", () => {
    it("sends albumId query param to GET /trackfile", async () => {
      nock(BASE)
        .get("/api/v1/trackfile")
        .query({ albumId: "10" })
        .reply(200, [stubTrackFile]);

      const { getTrackFiles } = await import("../lidarrClient.js");
      const result = await getTrackFiles(10);

      expect(result).toHaveLength(1);
      expect(result[0].albumId).toBe(10);
    });
  });

  describe("search", () => {
    it("sends term as query param to GET /search", async () => {
      const stubResult = {
        id: 1,
        foreignId: "abc",
        artist: stubArtist,
        album: stubAlbum,
      };
      nock(BASE)
        .get("/api/v1/search")
        .query({ term: "rock" })
        .reply(200, [stubResult]);

      const { search } = await import("../lidarrClient.js");
      const result = await search("rock");

      expect(result[0].artist.artistName).toBe("Test Artist");
    });
  });

  describe("getArtistCover", () => {
    it("streams response from GET /mediacover/artist/:id/:filename", async () => {
      nock(BASE)
        .get("/api/v1/mediacover/artist/1/poster.jpg")
        .reply(200, Buffer.from("fake-image-data"), {
          "content-type": "image/jpeg",
        });

      const { getArtistCover } = await import("../lidarrClient.js");
      const res = await getArtistCover(1, "poster.jpg");

      expect(res.status).toBe(200);
      expect(res.headers["content-type"]).toBe("image/jpeg");
    });
  });

  describe("getAlbumCover", () => {
    it("streams response from GET /mediacover/album/:id/:filename", async () => {
      nock(BASE)
        .get("/api/v1/mediacover/album/10/cover.jpg")
        .reply(200, Buffer.from("fake-cover-data"), {
          "content-type": "image/jpeg",
        });

      const { getAlbumCover } = await import("../lidarrClient.js");
      const res = await getAlbumCover(10, "cover.jpg");

      expect(res.status).toBe(200);
      expect(res.headers["content-type"]).toBe("image/jpeg");
    });
  });

  describe("runCommand", () => {
    it("POSTs to /command with name and returns command resource", async () => {
      nock(BASE)
        .post("/api/v1/command", { name: "RefreshArtist" })
        .reply(201, stubCommand);

      const { runCommand } = await import("../lidarrClient.js");
      const result = await runCommand("RefreshArtist");

      expect(result.id).toBe(200);
      expect(result.status).toBe("queued");
    });

    it("merges optional body fields into command POST payload", async () => {
      nock(BASE)
        .post("/api/v1/command", { name: "RefreshArtist", artistId: 1 })
        .reply(201, stubCommand);

      const { runCommand } = await import("../lidarrClient.js");
      const result = await runCommand("RefreshArtist", { artistId: 1 });

      expect(result.commandName).toBe("RefreshArtist");
    });
  });
});
