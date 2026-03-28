// TypeScript interfaces for raw Lidarr API responses.
// Only fields BiMusic actually uses are included.

export interface LidarrMediaCover {
  url: string | null;
  coverType: string;
  extension: string | null;
  remoteUrl: string | null;
}

export interface LidarrRatings {
  votes: number;
  value: number;
}

export interface LidarrArtist {
  id: number;
  artistName: string | null;
  foreignArtistId: string | null;
  overview: string | null;
  artistType: string | null;
  status: string;
  ended: boolean;
  images: LidarrMediaCover[] | null;
  path: string | null;
  monitored: boolean;
  genres: string[] | null;
  sortName: string | null;
  ratings: LidarrRatings;
  statistics: { trackFileCount: number } | null;
}

export interface LidarrAlbum {
  id: number;
  title: string | null;
  disambiguation: string | null;
  overview: string | null;
  artistId: number;
  foreignAlbumId: string | null;
  monitored: boolean;
  duration: number;
  albumType: string | null;
  releaseDate: string | null;
  artist: LidarrArtist;
  images: LidarrMediaCover[] | null;
  genres: string[] | null;
  ratings: LidarrRatings;
  remoteCover: string | null;
  statistics: { trackFileCount: number } | null;
}

export interface LidarrQuality {
  quality: { id: number; name: string };
}

export interface LidarrTrackFile {
  id: number;
  artistId: number;
  albumId: number;
  path: string | null;
  size: number;
  dateAdded: string;
  quality: LidarrQuality;
}

export interface LidarrTrack {
  id: number;
  artistId: number;
  albumId: number;
  trackFileId: number;
  foreignTrackId: string | null;
  trackNumber: string | null;
  absoluteTrackNumber: number;
  title: string | null;
  duration: number;
  hasFile: boolean;
  explicit: boolean;
  mediumNumber: number;
  trackFile: LidarrTrackFile | null;
  artist: LidarrArtist;
}

export interface LidarrSearchResult {
  id: number;
  foreignId: string | null;
  artist: LidarrArtist;
  album: LidarrAlbum;
}

export interface LidarrQueue {
  id: number;
  artistId: number | null;
  albumId: number | null;
  title: string | null;
  size: number;
  sizeleft: number;
  status: string | null;
  trackedDownloadStatus: string;
  errorMessage: string | null;
}

export interface LidarrCommand {
  id: number;
  name: string | null;
  commandName: string | null;
  status: string;
  queued: string;
  started: string | null;
  ended: string | null;
}
