// Shaped response types — what the Flutter client sees.
// These are simplified projections of Lidarr types with BiMusic-specific URLs added.

export interface Artist {
  id: number;
  name: string;
  overview: string | null;
  imageUrl: string;
  albumCount: number;
}

export interface Album {
  id: number;
  title: string;
  artistId: number;
  artistName: string;
  imageUrl: string;
  releaseDate: string | null;
  genres: string[];
  trackCount: number;
  duration: number;
}

export interface Track {
  id: number;
  title: string;
  trackNumber: string;
  duration: number;
  albumId: number;
  artistId: number;
  hasFile: boolean;
  streamUrl: string;
}

export interface SearchResults {
  artists: Artist[];
  albums: Album[];
}

export interface MusicRequest {
  id: string;
  type: string;
  lidarrId: number;
  status: string;
  requestedAt: string;
  resolvedAt: string | null;
}
