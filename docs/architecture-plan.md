# BiMusic System Architecture

## 1. System Overview

BiMusic is a self-hosted music streaming application composed of a Flutter mobile/desktop client and a Node.js/TypeScript REST API backend, deployed in an LXC container alongside Lidarr. The backend acts as a thin proxy/orchestrator between the Flutter client and Lidarr's music library, adding user authentication, per-user playlists, offline download tracking, and on-the-fly audio transcoding via ffmpeg.

```
┌──────────────────────────────────────────────────────────┐
│                    LXC Container                         │
│                                                          │
│  ┌─────────────────────┐     ┌─────────────────────┐    │
│  │  BiMusic Backend     │────▶│  Lidarr             │    │
│  │  (Node.js / TS)      │◀────│  (localhost:8686)   │    │
│  │  :3000               │     └─────────────────────┘    │
│  │                      │                                │
│  │  ┌────────────┐      │     ┌─────────────────────┐    │
│  │  │ ffmpeg     │      │     │  Music Files         │    │
│  │  │ transcoder │──────│────▶│  /music/...          │    │
│  │  └────────────┘      │     └─────────────────────┘    │
│  │                      │                                │
│  │  ┌────────────┐      │                                │
│  │  │ SQLite DB  │      │                                │
│  │  └────────────┘      │                                │
│  └─────────────────────┘                                 │
└──────────────────────────────────────────────────────────┘
         ▲
         │ HTTPS (reverse proxy)
         ▼
┌─────────────────────┐
│  Flutter Client      │
│  (iOS/Android/       │
│   macOS/Windows)     │
└─────────────────────┘
```

## 2. Component Breakdown

| Component | Tech | Responsibility |
|-----------|------|----------------|
| Flutter Client | Dart / Flutter | UI, playback, offline cache, network-aware bitrate selection |
| Backend API | Node.js + TypeScript + Express | Auth, REST API, Lidarr proxy, stream orchestration |
| Transcoder | ffmpeg (child process) | On-the-fly audio transcoding to MP3 at target bitrate |
| Database | SQLite (via better-sqlite3) | Users, refresh tokens, playlists, download records |
| Lidarr | External service | Music library management, metadata, search, download requests |
| Reverse Proxy | Nginx/Caddy (host) | TLS termination, forward to backend :3000 |

## 3. Database Choice: SQLite

**Why SQLite over Postgres/MySQL:**
- Small user base (< 20 users) -- no concurrency pressure
- Zero-config, single-file database, trivial to backup
- Runs inside LXC with no extra service
- `better-sqlite3` is synchronous and fast for this scale
- WAL mode enabled for concurrent reads during writes

## 4. Data Models

### 4.1 Users

```sql
CREATE TABLE users (
  id            TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  username      TEXT NOT NULL UNIQUE,
  display_name  TEXT NOT NULL DEFAULT '',
  password_hash TEXT NOT NULL,         -- bcrypt
  is_admin      INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### 4.2 Refresh Tokens

```sql
CREATE TABLE refresh_tokens (
  id          TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,    -- SHA-256 of the opaque token; raw token is NEVER stored
  device_name TEXT,
  expires_at  TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
```

### 4.3 Playlists

```sql
CREATE TABLE playlists (
  id          TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  description TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE playlist_tracks (
  id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  playlist_id     TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  lidarr_track_id INTEGER NOT NULL,    -- references Lidarr track ID (integer from Lidarr)
  position        INTEGER NOT NULL,
  added_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX idx_playlist_track_pos ON playlist_tracks(playlist_id, position);
CREATE INDEX idx_playlist_tracks_playlist ON playlist_tracks(playlist_id);
```

### 4.4 Offline Downloads

```sql
CREATE TABLE offline_downloads (
  id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id       TEXT NOT NULL,         -- client-generated stable device ID
  lidarr_track_id INTEGER NOT NULL,      -- integer from Lidarr
  bitrate         INTEGER NOT NULL,      -- 128 or 320
  status          TEXT NOT NULL DEFAULT 'pending',  -- pending | downloading | complete | failed
  file_size_bytes INTEGER,
  downloaded_at   TEXT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX idx_offline_user_device_track
  ON offline_downloads(user_id, device_id, lidarr_track_id);
CREATE INDEX idx_offline_user_device ON offline_downloads(user_id, device_id);
```

### 4.5 Requests

```sql
CREATE TABLE requests (
  id           TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type         TEXT NOT NULL,            -- 'artist' or 'album'
  lidarr_id    INTEGER NOT NULL,         -- Lidarr artist/album ID after adding
  name         TEXT NOT NULL,            -- artist name or album title
  cover_url    TEXT,                     -- proxied cover URL
  requested_at TEXT NOT NULL DEFAULT (datetime('now')),
  status       TEXT NOT NULL DEFAULT 'pending'  -- pending | downloading | available
);

CREATE INDEX idx_requests_user ON requests(user_id);
CREATE INDEX idx_requests_status ON requests(status);
```

## 5. JWT Authentication Strategy

### Token Types

| Token | Lifetime | Storage (Client) | Purpose |
|-------|----------|-------------------|---------|
| Access Token | 15 minutes | Memory only | Authorize API requests |
| Refresh Token | 30 days | Secure storage (flutter_secure_storage) | Obtain new access tokens |

### Flow

```
1. POST /api/auth/login  { username, password }
   ← 200 { accessToken, refreshToken, user }

2. All API requests: Authorization: Bearer <accessToken>

3. On 401:
   POST /api/auth/refresh  { refreshToken }
   ← 200 { accessToken, refreshToken }   (token rotation)

4. POST /api/auth/logout  { refreshToken }
   ← 204  (revokes refresh token)
```

### Implementation Details

- Access tokens: signed with HS256 using `JWT_ACCESS_SECRET`, payload `{ sub: userId, username, isAdmin, iat, exp }`
- Refresh tokens: opaque random string (64 bytes hex), stored as SHA-256 hash in DB (not JWTs)
- Token rotation: each refresh issues a new refresh token and invalidates the old one
- Revocation: delete from `refresh_tokens` table; access tokens are short-lived enough to not need a blocklist
- Admin creates initial users; no self-registration (small, private deployment)

### JWT Secret Management

- Two separate secrets for security isolation:
  - `JWT_ACCESS_SECRET` -- signs access tokens
  - `JWT_REFRESH_SECRET` -- used as HMAC key when hashing refresh tokens (adds server-side keyed hashing on top of SHA-256)
- Each secret: minimum 256-bit random value, generated at first deploy
- Stored in `.env` file on the LXC container (not in repo)
- Rotating one secret does not invalidate the other token type

## 6. REST API Endpoints

Base path: `/api`

### 6.1 Health

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | None | Returns `{ status: "ok", version: "1.0.0" }`. No auth required. Used by reverse proxy and monitoring. |

### 6.2 Authentication

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /auth/login | None | Login, returns `{ accessToken, refreshToken, user }` |
| POST | /auth/refresh | None | Rotate refresh token, returns `{ accessToken, refreshToken }` |
| POST | /auth/logout | Bearer | Revoke refresh token |
| GET | /auth/me | Bearer | Returns `{ id, username, isAdmin }` extracted from the JWT payload. Used on app resume after restoring tokens from secure storage. |

### 6.3 Users (Admin)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /users | Admin | List all users |
| POST | /users | Admin | Create a user |
| PATCH | /users/:id | Admin | Update user |
| DELETE | /users/:id | Admin | Delete user (cascades tokens, playlists, downloads) |

### 6.4 Library (Lidarr Proxy)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /library/artists | Bearer | List artists (proxies Lidarr GET /api/v1/artist) |
| GET | /library/artists/:id | Bearer | Artist detail |
| GET | /library/artists/:id/albums | Bearer | Albums for artist |
| GET | /library/albums/:id | Bearer | Album detail |
| GET | /library/albums/:id/tracks | Bearer | Tracks for album |
| GET | /library/tracks/:id | Bearer | Track detail + file info |
| GET | /search | Bearer | Search artists/albums (proxies Lidarr /api/v1/search) |
| GET | /library/artists/:id/image | Bearer | Proxy artist image from Lidarr |
| GET | /library/albums/:id/image | Bearer | Proxy album cover from Lidarr |

### 6.5 Streaming

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /stream/:trackId | Bearer | Stream audio (query: `?bitrate=128\|320`). Supports HTTP Range headers for seeking in both passthrough and transcoded modes. |

### 6.6 Requests (Lidarr)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /requests | Bearer | List current user's requests from the `requests` table, enriched with live Lidarr status (monitored, hasFile, queue progress) |
| GET | /requests/search | Bearer | Search for new artists/albums to request (proxies Lidarr lookup) |
| POST | /requests/artist | Bearer | Add artist to Lidarr, trigger search, create row in `requests` table |
| POST | /requests/album | Bearer | Add/monitor album in Lidarr, trigger search, create row in `requests` table |

### 6.7 Playlists

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /playlists | Bearer | List current user's playlists |
| POST | /playlists | Bearer | Create playlist |
| GET | /playlists/:id | Bearer | Get playlist with tracks |
| PATCH | /playlists/:id | Bearer | Update playlist name/description |
| DELETE | /playlists/:id | Bearer | Delete playlist |
| POST | /playlists/:id/tracks | Bearer | Add track(s) to playlist |
| DELETE | /playlists/:id/tracks/:trackId | Bearer | Remove track from playlist |
| PATCH | /playlists/:id/tracks/reorder | Bearer | Reorder tracks |

### 6.8 Offline Downloads

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /downloads?deviceId= | Bearer | List downloads for current user filtered by `deviceId` (required query param) |
| POST | /downloads | Bearer | Request track for offline. Body: `{ trackId: number, deviceId: string, bitrate: 128\|320 }` |
| DELETE | /downloads/:id | Bearer | Remove offline download record |
| GET | /downloads/:id/file | Bearer | Download the transcoded file for offline storage |

### 6.9 Error Response Format

All errors use a consistent JSON shape:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable message",
    "details": {}
  }
}
```

Standard error codes: `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `VALIDATION_ERROR`, `LIDARR_ERROR`, `TRANSCODE_ERROR`, `INTERNAL_ERROR`.

## 7. ffmpeg Streaming/Transcoding Pipeline

### Streaming (GET /api/stream/:trackId)

Two modes depending on whether transcoding is needed:

#### Mode A: Passthrough (source is MP3 at or below requested bitrate)

```
Client Request
  │
  ▼
Backend resolves trackId → Lidarr TrackFileResource → file path on disk
  │
  ▼
Source is MP3 at ≤ requested bitrate?
  │
  YES → Serve file directly with standard HTTP Range headers
  │
  Headers:
  │  Content-Type: audio/mpeg
  │  Accept-Ranges: bytes
  │  Content-Length: <file size>
  │
  ▼
Client receives file → full seek support via Range requests
```

#### Mode B: Transcode to temp file (source needs transcoding)

```
Client Request
  │
  ▼
Backend resolves trackId → file path on disk
  │
  ▼
Source needs transcoding → check for cached temp file
  │
  Cache hit? → serve temp file directly with Range headers
  │
  Cache miss → transcode to named temp file:
  │  ffmpeg -i <source_path> -vn -codec:a libmp3lame -b:a <bitrate>k /tmp/bimusic/<hash>.mp3
  │
  ▼
Serve temp file with standard HTTP Range headers
  │
  Headers:
  │  Content-Type: audio/mpeg
  │  Accept-Ranges: bytes
  │  Content-Length: <file size>
  │
  ▼
Client receives file → full seek support via Range requests
```

### Design Decisions

- **Temp-file transcoding with seek support**: Rather than piping ffmpeg output directly to the response (which prevents seeking), the backend transcodes to a named temp file in `/tmp/bimusic/` and then serves it with standard HTTP Range headers. This adds a brief initial delay on first request but enables full seek support via the progress bar.
- **Temp file naming**: Files are named by a hash of `(source_path, bitrate)` so repeated requests for the same track/bitrate reuse the cached file.
- **Temp file cleanup**: A periodic cleanup task (runs every hour) deletes temp files older than 24 hours. On process exit, a best-effort cleanup runs. The `/tmp/bimusic/` directory is also cleared on server startup.
- **Passthrough optimization**: If the source file is already MP3 at or below the requested bitrate, serve it directly without transcoding (saves CPU and eliminates transcoding delay).
- **Bitrate selection**: Client sends `?bitrate=128` or `?bitrate=320`. Backend validates (only 128 or 320 allowed). Client determines bitrate based on network type.
- **Process management**: Each transcode spawns one ffmpeg process. On client disconnect during active transcoding, the process continues (the temp file will be useful for future requests). If the server is shutting down, in-flight ffmpeg processes are killed.
- **Source format agnostic**: ffmpeg handles FLAC, MP3, AAC, OGG, etc. transparently.

### Offline Download (GET /api/downloads/:id/file)

Same ffmpeg pipeline, but the full file is transcoded and sent as a download:
- `Content-Disposition: attachment; filename="Artist - Title.mp3"`
- `Content-Type: audio/mpeg`
- Backend updates `offline_downloads.status` to `complete` after successful transfer.

## 8. Lidarr Integration / Proxy Design

### Approach: Thin Proxy with Response Shaping

The backend does NOT replicate Lidarr's data. It acts as a pass-through proxy that:
1. Forwards requests to Lidarr's local API (`http://localhost:8686/api/v1/...`)
2. Strips unnecessary fields from Lidarr responses (reduce payload size)
3. Adds the `X-Api-Key` header server-side (clients never see the Lidarr API key)

### Lidarr Client Service

```typescript
// Simplified interface
class LidarrClient {
  private baseUrl: string;   // http://localhost:8686
  private apiKey: string;    // from env LIDARR_API_KEY

  getArtists(): Promise<Artist[]>
  getArtist(id: number): Promise<Artist>
  getAlbums(artistId: number): Promise<Album[]>
  getAlbum(id: number): Promise<Album>
  getTracks(albumId: number): Promise<Track[]>
  getTrack(id: number): Promise<Track>
  getTrackFile(id: number): Promise<TrackFile>  // includes .path
  search(term: string): Promise<SearchResult[]>
  lookupArtist(term: string): Promise<Artist[]>
  lookupAlbum(term: string): Promise<Album[]>
  addArtist(foreignArtistId: string, ...): Promise<Artist>
  runCommand(name: string, ...): Promise<void>  // e.g., ArtistSearch
  getArtistImage(artistId: number, filename: string): Stream
  getAlbumImage(albumId: number, filename: string): Stream
}
```

### Shaped Response Types (what the Flutter client sees)

```typescript
interface Artist {
  id: number;
  name: string;
  overview: string | null;
  imageUrl: string;          // /api/library/artists/:id/image
  albumCount: number;
}

interface Album {
  id: number;
  title: string;
  artistId: number;
  artistName: string;
  imageUrl: string;          // /api/library/albums/:id/image
  releaseDate: string | null;
  genres: string[];
  trackCount: number;
  duration: number;          // total ms
}

interface Track {
  id: number;
  title: string;
  trackNumber: string;
  duration: number;          // ms
  albumId: number;
  artistId: number;
  hasFile: boolean;
  streamUrl: string;         // /api/stream/:trackId
}
```

### Lidarr Endpoints Used

| BiMusic feature | Lidarr endpoint |
|-----------------|-----------------|
| Browse artists | GET /api/v1/artist |
| Artist detail | GET /api/v1/artist/:id |
| Artist albums | GET /api/v1/album?artistId=:id |
| Album detail | GET /api/v1/album/:id |
| Album tracks | GET /api/v1/track?albumId=:id |
| Track detail | GET /api/v1/track/:id |
| Track file path | GET /api/v1/trackfile/:id |
| Search library | GET /api/v1/search?term=:q |
| Lookup artist (request) | GET /api/v1/artist/lookup?term=:q |
| Lookup album (request) | GET /api/v1/album/lookup?term=:q |
| Add artist | POST /api/v1/artist |
| Monitor album | PUT /api/v1/album/monitor |
| Trigger search | POST /api/v1/command { name: "ArtistSearch" } |
| Download queue | GET /api/v1/queue |
| Wanted/missing | GET /api/v1/wanted/missing |
| Artist image | GET /api/v1/mediacover/artist/:id/:filename |
| Album image | GET /api/v1/mediacover/album/:id/:filename |

## 9. Bitrate Selection Logic (Client-Side)

```dart
// In Flutter client
enum ConnectionType { wifi, cellular5G, cellularOther, none }

int selectBitrate(ConnectionType type) {
  switch (type) {
    case ConnectionType.wifi:
    case ConnectionType.cellular5G:
      return 320;
    default:
      return 128;
  }
}
```

- Uses `connectivity_plus` package to detect WiFi vs cellular
- On cellular, uses `NetworkInformation` API or carrier info to detect 5G where available
- Bitrate sent as query parameter on stream requests
- Backend enforces: only 128 or 320 accepted

## 10. Offline Sync Architecture

### Per-User, Per-Device Model

Each device has a stable `deviceId` (generated on first launch, stored in secure storage). Downloads are scoped to `(userId, deviceId)` so the same user on two devices maintains separate offline libraries.

### Download Flow

```
1. User marks track/album/playlist for offline
2. Client POST /api/downloads { trackId, deviceId, bitrate }
3. Backend creates offline_downloads record (status: pending)
4. Client background task: GET /api/downloads/:id/file
5. Client stores MP3 in app-local storage
6. Client updates local DB (track available offline)
```

### Background Downloads (Flutter)

- Use `flutter_background_service` package for continuous background downloads (better suited than `workmanager` for long-running download tasks that need to keep running when the app is backgrounded)
- Download queue processed one-at-a-time to avoid overwhelming the backend
- Resume on app restart if downloads were interrupted
- Respect battery/network constraints (pause on low battery, cellular-only if user opts in)

### Cleanup

- When user removes offline track: DELETE /api/downloads/:id + delete local file
- Backend can query downloads per user/device for admin visibility

## 11. Logging Strategy

### Backend Logging

- Library: **`pino`** (not winston -- pino is faster, outputs structured JSON natively, fewer dependencies)
- Output: file-based, written to `/var/log/bimusic/`
  - `app.log` -- all application logs
  - `access.log` -- HTTP request/response logs (method, path, status, duration)
- Log levels: `error`, `warn`, `info`, `debug`
- Production default: `info`
- Rotation: `logrotate` (daily, 14 days retention)
- Sensitive data: never log passwords, tokens, or full request bodies

```typescript
// Example: pino logger setup
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: {
    targets: [
      { target: 'pino/file', options: { destination: '/var/log/bimusic/app.log' } }
    ]
  }
});
```

### Frontend Logging

- Lightweight file logger writing to app-local storage
- Captures: API errors, playback errors, connectivity changes, crash context
- Structured JSON, one line per entry
- Max file size: 5 MB, oldest entries rotated out
- Viewable in a debug screen (admin users only) and exportable for bug reports

### What to Log

| Event | Level | Where |
|-------|-------|-------|
| Server start/stop | info | backend |
| HTTP requests | info | backend (access log) |
| Auth failures | warn | backend |
| Lidarr proxy errors | error | backend |
| ffmpeg spawn/exit | info | backend |
| ffmpeg errors | error | backend |
| API call failures | error | frontend |
| Playback errors | error | frontend |
| Network state changes | info | frontend |
| Download progress | debug | frontend |

## 12. CI/CD Pipeline (GitHub Actions)

### Workflows

#### 1. `ci.yml` -- On push/PR to main

```yaml
Jobs:
  lint:
    - ESLint (backend)
    - dart analyze (frontend)

  test-backend:
    - npm ci
    - npm run build (TypeScript compile)
    - npm test (vitest)

  test-frontend:
    - flutter pub get
    - flutter test

  build-check:
    - flutter build apk --debug (verify it compiles)
```

#### 2. `deploy.yml` -- Manual trigger or tag push

```yaml
Jobs:
  deploy-backend:
    - SSH into LXC container
    - git pull
    - npm ci --production
    - npm run build
    - systemctl restart bimusic

  build-apps:
    - flutter build apk --release
    - flutter build ipa --release (if macOS runner available)
    - Upload artifacts
```

### Branch Strategy

- `main` -- stable, deployable
- Feature branches: `feature/<name>`, merged via PR
- No staging environment needed at this scale

## 13. LXC Deployment Notes

### Container Setup

```
OS:          Debian 12 or Ubuntu 22.04
Node.js:     v20 LTS (via nodesource)
ffmpeg:      apt install ffmpeg
Lidarr:      running on same container or accessible at localhost:8686
Music files: mounted/accessible at a known path (e.g., /music)
```

### Backend as a systemd Service

```ini
[Unit]
Description=BiMusic Backend
After=network.target

[Service]
Type=simple
User=bimusic
WorkingDirectory=/opt/bimusic/backend
ExecStart=/usr/bin/node dist/index.js
EnvironmentFile=/opt/bimusic/.env
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Environment Variables (.env)

```
PORT=3000
NODE_ENV=production
JWT_ACCESS_SECRET=<random-256-bit-hex>     # signs access tokens
JWT_REFRESH_SECRET=<random-256-bit-hex>    # HMAC key for refresh token hashing
LIDARR_URL=http://localhost:8686
LIDARR_API_KEY=<lidarr-api-key>
MUSIC_ROOT=/music
DB_PATH=/opt/bimusic/data/bimusic.db
LOG_DIR=/var/log/bimusic
LOG_LEVEL=info
ADMIN_USERNAME=admin
ADMIN_PASSWORD=<initial-admin-password>
```

### Filesystem Layout

```
/opt/bimusic/
  .env
  backend/
    dist/           # compiled JS
    node_modules/
    package.json
  data/
    bimusic.db      # SQLite database
/var/log/bimusic/
  app.log
  access.log
/tmp/bimusic/       # Transcoded temp files (auto-cleaned, survives restarts within uptime)
/music/             # Lidarr-managed music files (read-only for BiMusic)
```

### Security

- Backend runs as non-root `bimusic` user
- Music directory mounted read-only for the backend
- Lidarr API key never exposed to clients
- HTTPS terminated at reverse proxy (Caddy/Nginx on host)
- SQLite DB file permissions: `bimusic:bimusic 600`

## 14. Security Boundaries & Trust Model

```
┌─────────────┐      HTTPS        ┌──────────────┐  localhost  ┌────────┐
│ Flutter App  │ ◄──────────────► │  Backend API  │ ──────────►│ Lidarr │
│ (untrusted)  │   JWT Bearer     │  (trusted)    │  API key   │(trusted)│
└─────────────┘                   └──────────────┘             └────────┘
                                         │
                                         ▼
                                   ┌──────────┐
                                   │  SQLite   │
                                   │ (trusted) │
                                   └──────────┘
```

- **Client is untrusted**: all input validated on backend
- **Backend trusts Lidarr**: same container, localhost only
- **Backend trusts SQLite**: local file, no network exposure
- **No client-to-Lidarr direct access**: backend proxies all Lidarr calls
- **Rate limiting**: optional, low priority given small user base, but `express-rate-limit` can be added to auth endpoints if needed

## 15. Key Architectural Decisions (ADRs)

### ADR-1: SQLite over PostgreSQL
- **Context**: Small user base, LXC deployment
- **Decision**: Use SQLite with WAL mode
- **Rationale**: Zero operational overhead, single-file backup, sufficient for < 20 concurrent users

### ADR-2: Temp-file transcoding with seek support
- **Context**: Need to serve 128k and 320k MP3 from various source formats, with seek support for the UX progress bar
- **Decision**: Transcode to a named temp file in `/tmp/bimusic/`, then serve with HTTP Range headers. Passthrough (no transcode) for source MP3 files at acceptable bitrate.
- **Rationale**: Piping ffmpeg output directly prevents seeking. Temp files add a brief initial delay but enable full seek via standard Range requests. Temp files are named by hash of (source, bitrate) for reuse and auto-cleaned after 24 hours.

### ADR-3: Thin Lidarr proxy over data replication
- **Context**: Need to expose music library to Flutter client
- **Decision**: Backend proxies Lidarr API, reshaping responses, never storing music metadata locally
- **Rationale**: Single source of truth stays in Lidarr; no sync/staleness issues; drastically simpler backend

### ADR-4: Opaque refresh tokens over JWT refresh tokens
- **Context**: Need revocable refresh tokens
- **Decision**: Random opaque strings, stored as SHA-256 hashes in DB
- **Rationale**: Allows instant revocation by deleting from DB; rotation prevents token reuse after theft

### ADR-5: Express 5 over Fastify/Hono
- **Context**: Choosing a Node.js HTTP framework
- **Decision**: Express 5 (stable since 2024)
- **Rationale**: Most widely known, massive ecosystem, simple enough for this project's needs. Express 5 adds native async error handling. Performance difference is irrelevant at this scale.

### ADR-6: pino over winston for logging
- **Context**: Choosing a structured logging library for the backend
- **Decision**: pino with file transport
- **Rationale**: Faster than winston (10x+ throughput), native structured JSON, fewer dependencies. Log rotation handled by OS-level logrotate, not the logger.

### ADR-7: UUID TEXT primary keys for BiMusic tables
- **Context**: Choosing primary key strategy for BiMusic-owned tables (users, refresh_tokens, playlists, playlist_tracks, offline_downloads, requests)
- **Decision**: TEXT PKs using `lower(hex(randomblob(16)))`. Lidarr IDs (track, album, artist) remain integers as they come from Lidarr.
- **Rationale**: UUIDs are non-guessable (avoids IDOR if an endpoint is accidentally unprotected), and decouple identity from insertion order. The performance difference is negligible at this scale.
