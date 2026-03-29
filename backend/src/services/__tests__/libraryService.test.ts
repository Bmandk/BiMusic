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

vi.mock("../lidarrClient.js", () => ({
  getArtists: vi.fn(),
  getArtist: vi.fn(),
  getAlbums: vi.fn(),
  getAlbum: vi.fn(),
  getTracks: vi.fn(),
  getTrack: vi.fn(),
  search: vi.fn(),
  getArtistCover: vi.fn(),
  getAlbumCover: vi.fn(),
}));

import type {
  LidarrArtist,
  LidarrAlbum,
  LidarrTrack,
  LidarrSearchResult,
} from "../../types/lidarr.js";
import * as lidarrClient from "../lidarrClient.js";
import {
  getArtists,
  getArtist,
  getArtistAlbums,
  getAlbum,
  getAlbumTracks,
  getTrack,
  search,
  getArtistImageStream,
  getAlbumImageStream,
} from "../libraryService.js";

const mockArtist = {
  id: 1,
  artistName: "Test Artist",
  overview: "Bio",
  images: [{ coverType: "poster", url: "/api/mediacover/1/poster.jpg" }],
  statistics: { albumCount: 2, trackFileCount: 10 },
} as unknown as LidarrArtist;

const mockAlbum = {
  id: 10,
  title: "Test Album",
  artistId: 1,
  artist: { artistName: "Test Artist" },
  releaseDate: "2020-01-01",
  genres: ["Rock"],
  duration: 3600,
  statistics: { trackFileCount: 5 },
  images: [{ coverType: "cover", url: "/api/mediacover/10/cover.jpg" }],
} as unknown as LidarrAlbum;

const mockTrack = {
  id: 100,
  title: "Test Track",
  trackNumber: "1",
  duration: 180,
  albumId: 10,
  artistId: 1,
  hasFile: true,
  trackFileId: 200,
} as unknown as LidarrTrack;

beforeEach(() => {
  vi.clearAllMocks();
});

describe("getArtists", () => {
  it("returns shaped artists with album counts", async () => {
    vi.mocked(lidarrClient.getArtists).mockResolvedValue([mockArtist]);
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([mockAlbum]);

    const result = await getArtists();

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      id: 1,
      name: "Test Artist",
      overview: "Bio",
      imageUrl: "http://localhost:3000/api/library/artists/1/image",
      albumCount: 1,
    });
  });

  it("returns 0 album count for artists with no albums", async () => {
    const artist2 = { ...mockArtist, id: 2 };
    vi.mocked(lidarrClient.getArtists).mockResolvedValue([artist2]);
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([mockAlbum]); // album belongs to artistId: 1

    const result = await getArtists();
    expect(result[0]?.albumCount).toBe(0);
  });

  it("uses 'Unknown Artist' when artistName is missing", async () => {
    const artistNoName = {
      ...mockArtist,
      artistName: undefined as unknown as string,
    };
    vi.mocked(lidarrClient.getArtists).mockResolvedValue([artistNoName]);
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([]);

    const result = await getArtists();
    expect(result[0]?.name).toBe("Unknown Artist");
  });

  it("returns empty array when no artists", async () => {
    vi.mocked(lidarrClient.getArtists).mockResolvedValue([]);
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([]);

    const result = await getArtists();
    expect(result).toHaveLength(0);
  });
});

describe("getArtist", () => {
  it("returns a shaped single artist with album count", async () => {
    vi.mocked(lidarrClient.getArtist).mockResolvedValue(mockArtist);
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([
      mockAlbum,
      { ...mockAlbum, id: 11 },
    ]);

    const result = await getArtist(1);

    expect(result).toMatchObject({
      id: 1,
      name: "Test Artist",
      albumCount: 2,
    });
  });

  it("propagates lidarrClient errors", async () => {
    vi.mocked(lidarrClient.getArtist).mockRejectedValue(new Error("Not found"));
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([]);

    await expect(getArtist(999)).rejects.toThrow("Not found");
  });
});

describe("getArtistAlbums", () => {
  it("returns shaped albums for an artist", async () => {
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([mockAlbum]);

    const result = await getArtistAlbums(1);

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      id: 10,
      title: "Test Album",
      artistId: 1,
      artistName: "Test Artist",
      imageUrl: "http://localhost:3000/api/library/albums/10/image",
      trackCount: 0, // not fetched to avoid N+1
      genres: ["Rock"],
    });
  });

  it("uses 'Unknown Album' when title is missing", async () => {
    const albumNoTitle = {
      ...mockAlbum,
      title: undefined as unknown as string,
    };
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([albumNoTitle]);

    const result = await getArtistAlbums(1);
    expect(result[0]?.title).toBe("Unknown Album");
  });

  it("uses 'Unknown Artist' when artist.artistName is missing", async () => {
    const albumNoArtist = {
      ...mockAlbum,
      artist: undefined,
    } as unknown as LidarrAlbum;
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([albumNoArtist]);

    const result = await getArtistAlbums(1);
    expect(result[0]?.artistName).toBe("Unknown Artist");
  });

  it("returns empty array when no albums", async () => {
    vi.mocked(lidarrClient.getAlbums).mockResolvedValue([]);
    const result = await getArtistAlbums(1);
    expect(result).toHaveLength(0);
  });
});

describe("getAlbum", () => {
  it("returns a shaped album with track count", async () => {
    vi.mocked(lidarrClient.getAlbum).mockResolvedValue(mockAlbum);
    vi.mocked(lidarrClient.getTracks).mockResolvedValue([
      mockTrack,
      { ...mockTrack, id: 101 },
    ]);

    const result = await getAlbum(10);

    expect(result).toMatchObject({
      id: 10,
      title: "Test Album",
      trackCount: 2,
    });
  });

  it("uses empty array for genres when missing", async () => {
    const albumNoGenres = {
      ...mockAlbum,
      genres: undefined as unknown as string[],
    };
    vi.mocked(lidarrClient.getAlbum).mockResolvedValue(albumNoGenres);
    vi.mocked(lidarrClient.getTracks).mockResolvedValue([]);

    const result = await getAlbum(10);
    expect(result.genres).toEqual([]);
  });
});

describe("getAlbumTracks", () => {
  it("returns shaped tracks for an album", async () => {
    vi.mocked(lidarrClient.getTracks).mockResolvedValue([mockTrack]);

    const result = await getAlbumTracks(10);

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      id: 100,
      title: "Test Track",
      trackNumber: "1",
      duration: 180,
      albumId: 10,
      artistId: 1,
      hasFile: true,
      streamUrl: "http://localhost:3000/api/stream/100",
    });
  });

  it("uses 'Unknown Track' when title is missing", async () => {
    const trackNoTitle = {
      ...mockTrack,
      title: undefined as unknown as string,
    };
    vi.mocked(lidarrClient.getTracks).mockResolvedValue([trackNoTitle]);

    const result = await getAlbumTracks(10);
    expect(result[0]?.title).toBe("Unknown Track");
  });

  it("uses '0' for trackNumber when missing", async () => {
    const trackNoNumber = {
      ...mockTrack,
      trackNumber: undefined as unknown as string,
    };
    vi.mocked(lidarrClient.getTracks).mockResolvedValue([trackNoNumber]);

    const result = await getAlbumTracks(10);
    expect(result[0]?.trackNumber).toBe("0");
  });
});

describe("getTrack", () => {
  it("returns a shaped single track", async () => {
    vi.mocked(lidarrClient.getTrack).mockResolvedValue(mockTrack);

    const result = await getTrack(100);

    expect(result).toMatchObject({
      id: 100,
      title: "Test Track",
      streamUrl: "http://localhost:3000/api/stream/100",
    });
  });

  it("propagates lidarrClient errors", async () => {
    vi.mocked(lidarrClient.getTrack).mockRejectedValue(
      new Error("Track not found"),
    );
    await expect(getTrack(999)).rejects.toThrow("Track not found");
  });
});

describe("search", () => {
  it("returns artists and albums from search results", async () => {
    const searchResult = {
      artist: mockArtist,
      album: mockAlbum,
    };
    vi.mocked(lidarrClient.search).mockResolvedValue(
      [searchResult] as unknown as LidarrSearchResult[],
    );

    const result = await search("test");

    expect(result.artists).toHaveLength(1);
    expect(result.albums).toHaveLength(1);
    expect(result.artists[0]?.id).toBe(1);
    expect(result.albums[0]?.id).toBe(10);
  });

  it("deduplicates artists across multiple results", async () => {
    const results = [
      { artist: mockArtist, album: mockAlbum },
      { artist: mockArtist, album: { ...mockAlbum, id: 11 } },
    ];
    vi.mocked(lidarrClient.search).mockResolvedValue(
      results as unknown as LidarrSearchResult[],
    );

    const result = await search("test");

    expect(result.artists).toHaveLength(1); // deduped
    expect(result.albums).toHaveLength(2);
  });

  it("handles results with only artist (no album)", async () => {
    vi.mocked(lidarrClient.search).mockResolvedValue([
      { artist: mockArtist, album: undefined as unknown as typeof mockAlbum },
    ] as unknown as LidarrSearchResult[]);

    const result = await search("artist only");
    expect(result.artists).toHaveLength(1);
    expect(result.albums).toHaveLength(0);
  });

  it("handles results with only album (no artist)", async () => {
    vi.mocked(lidarrClient.search).mockResolvedValue([
      { artist: undefined as unknown as typeof mockArtist, album: mockAlbum },
    ] as unknown as LidarrSearchResult[]);

    const result = await search("album only");
    expect(result.artists).toHaveLength(0);
    expect(result.albums).toHaveLength(1);
  });

  it("returns empty results for empty search", async () => {
    vi.mocked(lidarrClient.search).mockResolvedValue([]);

    const result = await search("nothing");
    expect(result.artists).toHaveLength(0);
    expect(result.albums).toHaveLength(0);
  });
});

describe("getArtistImageStream", () => {
  it("fetches artist and returns cover stream for poster image", async () => {
    const mockStream = {
      data: { pipe: vi.fn() },
      headers: { "content-type": "image/jpeg" },
    };
    vi.mocked(lidarrClient.getArtist).mockResolvedValue(mockArtist);
    vi.mocked(lidarrClient.getArtistCover).mockResolvedValue(
      mockStream as never,
    );

    const result = await getArtistImageStream(1);

    expect(lidarrClient.getArtist).toHaveBeenCalledWith(1);
    expect(lidarrClient.getArtistCover).toHaveBeenCalledWith(1, "poster.jpg");
    expect(result).toBe(mockStream);
  });

  it("falls back to 'poster.jpg' when no poster image in list", async () => {
    const artistNoImages = { ...mockArtist, images: [] };
    const mockStream = { data: { pipe: vi.fn() } };
    vi.mocked(lidarrClient.getArtist).mockResolvedValue(artistNoImages);
    vi.mocked(lidarrClient.getArtistCover).mockResolvedValue(
      mockStream as never,
    );

    await getArtistImageStream(1);
    expect(lidarrClient.getArtistCover).toHaveBeenCalledWith(1, "poster.jpg");
  });

  it("falls back to 'poster.jpg' when images is null", async () => {
    const artistNullImages = { ...mockArtist, images: null as never };
    const mockStream = { data: { pipe: vi.fn() } };
    vi.mocked(lidarrClient.getArtist).mockResolvedValue(artistNullImages);
    vi.mocked(lidarrClient.getArtistCover).mockResolvedValue(
      mockStream as never,
    );

    await getArtistImageStream(1);
    expect(lidarrClient.getArtistCover).toHaveBeenCalledWith(1, "poster.jpg");
  });
});

describe("getAlbumImageStream", () => {
  it("fetches album and returns cover stream for cover image", async () => {
    const mockStream = {
      data: { pipe: vi.fn() },
      headers: { "content-type": "image/jpeg" },
    };
    vi.mocked(lidarrClient.getAlbum).mockResolvedValue(mockAlbum);
    vi.mocked(lidarrClient.getAlbumCover).mockResolvedValue(
      mockStream as never,
    );

    const result = await getAlbumImageStream(10);

    expect(lidarrClient.getAlbum).toHaveBeenCalledWith(10);
    expect(lidarrClient.getAlbumCover).toHaveBeenCalledWith(10, "cover.jpg");
    expect(result).toBe(mockStream);
  });

  it("falls back to 'cover.jpg' when no cover image in list", async () => {
    const albumNoImages = { ...mockAlbum, images: [] };
    const mockStream = { data: { pipe: vi.fn() } };
    vi.mocked(lidarrClient.getAlbum).mockResolvedValue(albumNoImages);
    vi.mocked(lidarrClient.getAlbumCover).mockResolvedValue(
      mockStream as never,
    );

    await getAlbumImageStream(10);
    expect(lidarrClient.getAlbumCover).toHaveBeenCalledWith(10, "cover.jpg");
  });
});
