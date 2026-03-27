# BiMusic Backend Implementation Plan

## 1. Technology Stack

| Component | Choice | Rationale |
|---|---|---|
| Runtime | Node.js 20 LTS | Stable, long-term support |
| Language | TypeScript 5.x, strict mode | Type safety across the codebase |
| HTTP Framework | Express 5 | Built-in async error handling simplifies middleware. Mature ecosystem, simple for a small-scale app |
| Validation | zod | Runtime schema validation with TypeScript type inference |
| JWT | jsonwebtoken + bcrypt | Standard, well-audited libraries |
| Database | SQLite via better-sqlite3 | Zero-config, file-based, perfect for a few users in an LXC. No external DB process needed |
| ORM/Query | Drizzle ORM | Lightweight, TypeScript-first, works great with SQLite |
| Transcoding | fluent-ffmpeg | Wraps ffmpeg CLI with a clean Node API |
| HTTP Client | axios | For Lidarr API proxy calls |
| Logging | pino | Structured JSON logging, low overhead. File rotation via OS logrotate |
| Testing | vitest + supertest | Fast TS-native test runner + HTTP assertion library |

## 2. Project Structure

```
backend/
├── src/
│   ├── index.ts                  # App entry point — starts server, runs bootstrap
│   ├── app.ts                    # Express app factory (exported for testability)
│   ├── config/
│   │   └── env.ts                # Environment config with zod validation
│   ├── db/
│   │   ├── schema.ts             # Drizzle table definitions
│   │   ├── connection.ts         # SQLite connection singleton
│   │   └── migrations/           # SQL migration files
│   ├── middleware/
│   │   ├── auth.ts               # JWT verification middleware + admin guard
│   │   ├── errorHandler.ts       # Global error handler
│   │   └── requestLogger.ts      # HTTP request logging
│   ├── routes/
│   │   ├── health.ts             # GET /health
│   │   ├── auth.ts               # POST /auth/login, /auth/refresh, /auth/logout, GET /auth/me
│   │   ├── users.ts              # GET/POST/DELETE /users (admin only)
│   │   ├── library.ts            # GET /library/artists, /albums, /tracks, /cover/*
│   │   ├── stream.ts             # GET /stream/:trackId
│   │   ├── downloads.ts          # POST/GET/DELETE /downloads/*
│   │   ├── playlists.ts          # CRUD /playlists
│   │   ├── search.ts             # GET /search/*, POST /request/*
│   │   └── requests.ts           # GET /requests (user's pending requests with live Lidarr status)
│   ├── services/
│   │   ├── authService.ts        # Login, token generation, refresh logic
│   │   ├── userService.ts        # User CRUD, admin bootstrap
│   │   ├── libraryService.ts     # Fetches library data from Lidarr
│   │   ├── streamService.ts      # ffmpeg transcoding pipeline
│   │   ├── downloadService.ts    # Background worker for offline track transcoding
│   │   ├── playlistService.ts    # Playlist CRUD logic
│   │   ├── requestService.ts     # Pending request tracking and status polling
│   │   └── lidarrClient.ts       # Typed HTTP client for Lidarr API
│   ├── utils/
│   │   └── logger.ts             # Pino logger configuration
│   └── types/
│       ├── lidarr.ts             # TypeScript types for Lidarr API resources
│       └── api.ts                # Request/response types for BiMusic API
├── tests/
│   ├── unit/                     # Service-level unit tests
│   ├── integration/              # Route-level tests with supertest
│   └── helpers/                  # Test utilities, fixtures, mock data
├── package.json
├── tsconfig.json
├── vitest.config.ts
├── .env.example
└── Dockerfile
```

## 3. TypeScript Configuration

```jsonc
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

Key choices:
- `module: "Node16"` — proper ESM/CJS interop for Node.js
- `strict: true` — enables all strict type-checking options
- `ES2022` target — allows top-level await, `Array.at()`, `Object.hasOwn()`
- Source maps enabled for meaningful stack traces in production logs

## 4. REST API Route Definitions

All routes are prefixed with `/api`.

### 4.1 Health Check

| Method | Path | Auth | Response |
|---|---|---|---|
| GET | `/api/health` | None | `{status: "ok", version: string}` — version read from package.json. Used by CI, LXC monitoring, and load balancers. |

### 4.2 Authentication (no auth required for login/refresh)

| Method | Path | Auth | Request Body | Response |
|---|---|---|---|---|
| POST | `/api/auth/login` | None | `{username, password}` | `{accessToken, refreshToken, user: {id, username, isAdmin}}` |
| POST | `/api/auth/refresh` | None | `{refreshToken}` | `{accessToken, refreshToken}` |
| POST | `/api/auth/logout` | Bearer | `{refreshToken}` | `204 No Content` |
| GET | `/api/auth/me` | Bearer | — | `{id, username, isAdmin}` — decoded from the verified JWT, no DB call needed |

### 4.3 User Management (admin only)

| Method | Path | Auth | Request Body | Response |
|---|---|---|---|---|
| GET | `/api/users` | Admin | — | `[{id, username, isAdmin, createdAt}]` |
| POST | `/api/users` | Admin | `{username, password, isAdmin?}` | `{id, username, isAdmin, createdAt}` |
| DELETE | `/api/users/:id` | Admin | — | `204 No Content` |

### 4.4 Library (proxied from Lidarr)

| Method | Path | Auth | Query Params | Description |
|---|---|---|---|---|
| GET | `/api/library/artists` | Bearer | — | List all artists |
| GET | `/api/library/artists/:id` | Bearer | — | Get single artist with albums |
| GET | `/api/library/albums` | Bearer | `?artistId=` | List albums, optional artist filter |
| GET | `/api/library/albums/:id` | Bearer | — | Get single album with tracks |
| GET | `/api/library/tracks` | Bearer | `?albumId=` | List tracks, optional album filter |
| GET | `/api/library/tracks/:id` | Bearer | — | Get single track with file info |
| GET | `/api/library/cover/artist/:artistId/:filename` | Bearer | — | Proxy artist cover art |
| GET | `/api/library/cover/album/:albumId/:filename` | Bearer | — | Proxy album cover art |

### 4.5 Search and Requests (proxied from Lidarr)

| Method | Path | Auth | Query/Body | Description |
|---|---|---|---|---|
| GET | `/api/search` | Bearer | `?term=` | General search (proxies `/api/v1/search`) |
| GET | `/api/search/artist` | Bearer | `?term=` | Artist lookup (proxies `/api/v1/artist/lookup`) |
| GET | `/api/search/album` | Bearer | `?term=` | Album lookup (proxies `/api/v1/album/lookup`) |
| POST | `/api/requests/artist` | Bearer | Lidarr artist payload | Add artist to Lidarr, creates a `requests` record |
| POST | `/api/requests/album` | Bearer | `{albumIds, monitored}` | Monitor/request album in Lidarr, creates a `requests` record |

### 4.6 Streaming

| Method | Path | Auth | Query Params | Description |
|---|---|---|---|---|
| GET | `/api/stream/:trackId` | Bearer | `?quality=high\|low` | Stream track. `high` = 320kbps, `low` = 128kbps. Supports `Range` headers. |

### 4.7 Downloads (Offline Availability)

| Method | Path | Auth | Request Body | Response |
|---|---|---|---|---|
| POST | `/api/downloads/tracks` | Bearer | `{trackIds: number[], deviceId: string}` | `{queued: number}` |
| POST | `/api/downloads/albums/:albumId` | Bearer | `{deviceId: string}` | `{queued: number}` |
| GET | `/api/downloads` | Bearer | `?deviceId=` | `{tracks: [...], totalStorageBytes}` |
| GET | `/api/downloads/:trackId/download` | Bearer | `?deviceId=` | Binary file download (320k MP3) |
| DELETE | `/api/downloads/:trackId` | Bearer | `?deviceId=` | `204 No Content` |

### 4.8 Playlists

| Method | Path | Auth | Request Body | Response |
|---|---|---|---|---|
| GET | `/api/playlists` | Bearer | — | `[{id, name, trackCount, createdAt}]` |
| POST | `/api/playlists` | Bearer | `{name}` | `{id, name, createdAt}` |
| GET | `/api/playlists/:id` | Bearer | — | `{id, name, tracks: [...]}` |
| PUT | `/api/playlists/:id` | Bearer | `{name}` | `{id, name, updatedAt}` |
| DELETE | `/api/playlists/:id` | Bearer | — | `204 No Content` |
| POST | `/api/playlists/:id/tracks` | Bearer | `{trackIds, position?}` | `{added: number}` |
| DELETE | `/api/playlists/:id/tracks/:trackId` | Bearer | — | `204 No Content` |
| PUT | `/api/playlists/:id/tracks/reorder` | Bearer | `{trackIds}` | `200 OK` |

### 4.9 Pending Requests

When a user requests new music via the Lidarr proxy (add artist or monitor album), a `requests` record is created to track the request lifecycle. This gives users visibility into what they have requested and the current download/availability status.

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/api/requests` | Bearer | List the current user's requests. On each call, the backend checks Lidarr for status updates (see below). |

**Status update logic:** When `GET /api/requests` is called, the backend iterates each request with status != `available` and queries Lidarr:
- For type `artist`: `GET /api/v1/artist/:lidarrId` — if `statistics.trackFileCount > 0`, set status to `available`
- For type `album`: `GET /api/v1/album/:lidarrId` — if `statistics.trackFileCount > 0`, set status to `available`
- If Lidarr shows the item is being downloaded (in queue), set status to `downloading`

Status flow: `pending` -> `downloading` -> `available`

## 5. JWT Authentication Implementation

### 5.1 Token Design

**Access Token (JWT):**
- Lifetime: 15 minutes
- Payload: `{userId: string, username: string, displayName: string, isAdmin: boolean}` (userId is a UUID)
- Algorithm: HS256
- Signed with `JWT_ACCESS_SECRET` environment variable
- Stateless — not stored server-side

**Refresh Token (opaque):**
- Lifetime: 30 days
- **Not a JWT** — a cryptographically random opaque string generated via `crypto.randomBytes(64).toString('hex')`
- **Hashed with HMAC-SHA256 before storage** — keyed with `JWT_REFRESH_SECRET`:
  ```typescript
  createHmac('sha256', process.env.JWT_REFRESH_SECRET).update(rawToken).digest('hex')
  ```
  Only the HMAC hash is persisted in the `token_hash` column; the raw token is never stored. This is more secure than plain SHA-256 because forging a valid hash requires knowing the secret.

### 5.2 Token Rotation

On each call to `/api/auth/refresh`:
1. Compute `HMAC-SHA256(JWT_REFRESH_SECRET, incomingToken)` and look up the hash in `refresh_tokens.token_hash`
2. If not found or expired, return 401 (token was revoked or already rotated)
3. Delete the old refresh token row
4. Generate a new access token (JWT signed with `JWT_ACCESS_SECRET`)
5. Generate a new opaque refresh token, compute its HMAC-SHA256 hash, and insert into the database
6. Return both raw tokens to the client

This rotation strategy ensures:
- A stolen refresh token can only be used once before it is invalidated
- The legitimate user's next refresh attempt will fail, signaling compromise
- Admins can revoke all sessions for a user by deleting their refresh token rows

### 5.3 Auth Middleware

```typescript
// Pseudocode for middleware chain
function authenticate(req, res, next) {
  const token = extractBearerToken(req.headers.authorization);
  if (!token) return res.status(401).json({ error: 'Missing token' });

  try {
    const payload = jwt.verify(token, env.JWT_ACCESS_SECRET);
    req.user = { userId: payload.userId, username: payload.username, displayName: payload.displayName, isAdmin: payload.isAdmin };
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

function requireAdmin(req, res, next) {
  if (!req.user.isAdmin) return res.status(403).json({ error: 'Admin access required' });
  next();
}
```

The `GET /api/auth/me` endpoint uses the same `authenticate` middleware and returns `{id, username, isAdmin}` decoded directly from the verified JWT — no database call needed.

### 5.4 Multi-User Session Handling

- Each user can have multiple active refresh tokens (one per device/client)
- No limit on concurrent sessions for simplicity
- Logout revokes the specific refresh token passed in the request body
- Admin user deletion cascades to delete all refresh tokens for that user
- No session affinity needed — access tokens are stateless and any server instance can verify them

## 6. ffmpeg Streaming and Transcoding

### 6.1 Stream Endpoint Flow

```
Client -> GET /api/stream/:trackId?quality=high -> Auth Middleware -> StreamService -> Response
```

1. **Resolve file path:** Fetch track info from Lidarr (`GET /api/v1/track/:trackId`) to get `trackFileId`, then fetch file details (`GET /api/v1/trackfile/:trackFileId`) to get the on-disk path
2. **Determine quality:** Parse `?quality=` query parameter
   - `high` (default) = 320kbps MP3
   - `low` = 128kbps MP3
3. **Passthrough check:** If the source file is already MP3 at or below the requested bitrate, serve the file directly without transcoding (saves CPU)
4. **Transcode to temp file:** Otherwise, check if a cached temp file exists at `/tmp/bimusic/<hash>.mp3` (where hash is derived from trackId + bitrate). If not, spawn ffmpeg to transcode to that path:
   ```bash
   ffmpeg -i <source_path> -vn -codec:a libmp3lame -b:a 320k /tmp/bimusic/<hash>.mp3
   ```
5. **Serve the file** with standard HTTP Range headers — both passthrough and transcoded files are regular files on disk, so full `Content-Range` / `206 Partial Content` / seeking support works identically for both.
6. **Response headers:**
   - `Content-Type: audio/mpeg`
   - `Accept-Ranges: bytes`
   - `Content-Length` (known, since the file is complete on disk)

### 6.2 Range Request / Seeking Support

Both passthrough and transcoded modes serve files from disk, so seeking works identically:
- Standard HTTP range serving using Node.js `fs.createReadStream` with `start`/`end` byte offsets
- Full `Content-Range` / `206 Partial Content` support
- The temp-file approach eliminates the complexity of approximate seeking during live transcoding

### 6.3 Temp File Cache Management

- Temp files are written to `/tmp/bimusic/` with a filename derived from `<trackId>-<bitrate>.mp3`
- An hourly `setInterval` cleanup removes files older than 24 hours
- On server startup, the `/tmp/bimusic/` directory is cleared to prevent stale files from prior runs
- No concurrency limit enforced (small user base), but the logger records active transcode count for observability

### 6.4 Format Support

The backend accepts any audio format that ffmpeg supports as input (FLAC, ALAC, AAC, OGG, WAV, MP3, etc.). Output is always MP3 for consistency — the Flutter client only needs to handle one codec for streaming playback.

### 6.5 Process Lifecycle

- If the temp file doesn't exist yet, a transcode is triggered and the response waits for it to complete before serving
- If a transcode is already in progress for the same file (concurrent request), the second request waits for the first to finish
- On ffmpeg error, the partial temp file is deleted and an appropriate error is returned
- On client disconnect during transcode, the transcode continues (the temp file is useful for future requests)

### 6.5 Offline Transcoding

Offline downloads use the same ffmpeg pipeline but write to a file instead of piping to a response:

```bash
ffmpeg -i <source_path> -vn -codec:a libmp3lame -b:a 320k <output_path>
```

A simple `setInterval`-based background worker (10-second poll interval) picks up `pending` rows from `offline_tracks`, processes them one at a time, and updates the status to `ready` or `failed`. No need for a job queue library at this scale.

## 7. Lidarr API Proxy Design

### 7.1 Client Architecture

`lidarrClient.ts` is a typed HTTP client wrapping axios:

```typescript
// Configured from environment
const lidarrApi = axios.create({
  baseURL: `${env.LIDARR_URL}/api/v1`,
  headers: { 'X-Api-Key': env.LIDARR_API_KEY },
  timeout: 30000,
});
```

### 7.2 Method Mapping

| BiMusic Method | Lidarr Endpoint | HTTP |
|---|---|---|
| `getArtists()` | `/api/v1/artist` | GET |
| `getArtist(id)` | `/api/v1/artist/{id}` | GET |
| `lookupArtist(term)` | `/api/v1/artist/lookup?term=` | GET |
| `addArtist(payload)` | `/api/v1/artist` | POST |
| `getAlbums(artistId?)` | `/api/v1/album?artistId=` | GET |
| `getAlbum(id)` | `/api/v1/album/{id}` | GET |
| `lookupAlbum(term)` | `/api/v1/album/lookup?term=` | GET |
| `monitorAlbum(ids, monitored)` | `/api/v1/album/monitor` | PUT |
| `getTracks(albumId?)` | `/api/v1/track?albumId=` | GET |
| `getTrack(id)` | `/api/v1/track/{id}` | GET |
| `getTrackFile(id)` | `/api/v1/trackfile/{id}` | GET |
| `getTrackFiles(albumId)` | `/api/v1/trackfile?albumId=` | GET |
| `search(term)` | `/api/v1/search?term=` | GET |
| `getArtistCover(artistId, filename)` | `/api/v1/mediacover/artist/{artistId}/{filename}` | GET (stream) |
| `getAlbumCover(albumId, filename)` | `/api/v1/mediacover/album/{albumId}/{filename}` | GET (stream) |
| `runCommand(name, body?)` | `/api/v1/command` | POST |

### 7.3 Design Principles

- **Thin proxy:** Routes call lidarrClient methods, apply minimal transformation (strip server-side file paths, inject BiMusic stream URLs), and return. The frontend never communicates with Lidarr directly.
- **Type narrowing:** Lidarr responses are large. The proxy returns simplified types containing only the fields the Flutter client needs (id, title, artist name, cover URLs, duration, track number, etc.).
- **Error mapping:** Lidarr HTTP errors are caught and re-thrown as appropriate BiMusic errors (404 -> 404, 500 -> 502 Bad Gateway, timeout -> 504).
- **Cover art streaming:** Cover art is streamed through (piped) rather than buffered, to keep memory usage low.

## 8. Database Schema (SQLite via Drizzle)

### 8.1 Table Definitions

All primary keys use `TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16))))` — UUIDs generated by SQLite. This avoids exposing sequential IDs in the API.

**users**

| Column | Type | Constraints |
|---|---|---|
| `id` | TEXT | PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))) |
| `username` | TEXT | UNIQUE NOT NULL |
| `displayName` | TEXT | NOT NULL (defaults to username on creation) |
| `passwordHash` | TEXT | NOT NULL |
| `isAdmin` | INTEGER | NOT NULL DEFAULT 0 |
| `createdAt` | TEXT | NOT NULL DEFAULT (datetime('now')) |

**refresh_tokens**

| Column | Type | Constraints |
|---|---|---|
| `id` | TEXT | PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))) |
| `userId` | TEXT | NOT NULL, FK -> users(id) ON DELETE CASCADE |
| `token_hash` | TEXT | UNIQUE NOT NULL (HMAC-SHA256 hash of the opaque refresh token, keyed with `JWT_REFRESH_SECRET`) |
| `expiresAt` | TEXT | NOT NULL |
| `createdAt` | TEXT | NOT NULL DEFAULT (datetime('now')) |

**playlists**

| Column | Type | Constraints |
|---|---|---|
| `id` | TEXT | PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))) |
| `userId` | TEXT | NOT NULL, FK -> users(id) ON DELETE CASCADE |
| `name` | TEXT | NOT NULL |
| `createdAt` | TEXT | NOT NULL DEFAULT (datetime('now')) |
| `updatedAt` | TEXT | NOT NULL DEFAULT (datetime('now')) |

**playlist_tracks**

| Column | Type | Constraints |
|---|---|---|
| `id` | TEXT | PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))) |
| `playlistId` | TEXT | NOT NULL, FK -> playlists(id) ON DELETE CASCADE |
| `lidarrTrackId` | INTEGER | NOT NULL |
| `position` | INTEGER | NOT NULL |
| — | — | UNIQUE(playlistId, lidarrTrackId) |

**offline_tracks**

| Column | Type | Constraints |
|---|---|---|
| `id` | TEXT | PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))) |
| `userId` | TEXT | NOT NULL, FK -> users(id) ON DELETE CASCADE |
| `lidarrTrackId` | INTEGER | NOT NULL |
| `deviceId` | TEXT | NOT NULL (client-generated device identifier — offline files are per-user-per-device) |
| `filePath` | TEXT | NULLABLE (null until transcoding completes) |
| `fileSize` | INTEGER | NULLABLE (bytes, for storage tracking) |
| `status` | TEXT | NOT NULL DEFAULT 'pending' — enum: pending, processing, ready, failed |
| `requestedAt` | TEXT | NOT NULL DEFAULT (datetime('now')) |
| `completedAt` | TEXT | NULLABLE |
| — | — | UNIQUE(userId, lidarrTrackId, deviceId) |

**requests**

```sql
CREATE TABLE requests (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,        -- 'artist' | 'album'
  lidarr_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  cover_url TEXT,
  status TEXT NOT NULL DEFAULT 'pending', -- pending | downloading | available
  requested_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, type, lidarr_id)
);
```

| Column | Type | Constraints |
|---|---|---|
| `id` | TEXT | PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))) |
| `user_id` | TEXT | NOT NULL, FK -> users(id) ON DELETE CASCADE |
| `type` | TEXT | NOT NULL — enum: artist, album |
| `lidarr_id` | INTEGER | NOT NULL |
| `name` | TEXT | NOT NULL (artist or album name, for display) |
| `cover_url` | TEXT | NULLABLE (cover art URL from Lidarr lookup) |
| `status` | TEXT | NOT NULL DEFAULT 'pending' — enum: pending, downloading, available |
| `requested_at` | TEXT | NOT NULL DEFAULT (datetime('now')) |
| — | — | UNIQUE(user_id, type, lidarr_id) |

### 8.2 Why SQLite

- Zero configuration, no external process — ideal for an LXC with a handful of users
- Single-file database, easy to back up (copy the file)
- `better-sqlite3` is synchronous and fast — no connection pool overhead
- WAL mode enabled for concurrent reads during writes
- Drizzle ORM provides type-safe queries and migrations without the weight of Prisma

### 8.3 Migrations

Drizzle Kit generates SQL migration files from schema changes. Migrations run automatically on server startup before the HTTP listener binds:

```typescript
// In index.ts
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
migrate(db, { migrationsFolder: './src/db/migrations' });
```

## 9. Environment Configuration

### 9.1 Variables

```env
# Server
PORT=3000
NODE_ENV=production                 # production | development | test

# JWT (generate with: openssl rand -base64 64)
JWT_ACCESS_SECRET=<random-64-byte-secret>   # Signs access token JWTs
JWT_REFRESH_SECRET=<random-64-byte-secret>  # Keys HMAC-SHA256 of refresh tokens
JWT_ACCESS_EXPIRY=15m
JWT_REFRESH_EXPIRY=30d

# Lidarr connection
LIDARR_URL=http://localhost:8686
LIDARR_API_KEY=<lidarr-api-key>

# Filesystem paths
MUSIC_LIBRARY_PATH=/music           # Lidarr music library mount point (read-only)
OFFLINE_STORAGE_PATH=./data/offline # Transcoded offline files
DB_PATH=./data/bimusic.db          # SQLite database
LOG_PATH=/var/log/bimusic          # Log directory

# Admin bootstrap (used on first startup only)
ADMIN_USERNAME=admin
ADMIN_PASSWORD=<initial-admin-password>
```

### 9.2 Validation

Environment variables are validated at startup using a zod schema in `config/env.ts`:

```typescript
const envSchema = z.object({
  PORT: z.coerce.number().default(3000),
  NODE_ENV: z.enum(['production', 'development', 'test']).default('production'),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  JWT_ACCESS_EXPIRY: z.string().default('15m'),
  JWT_REFRESH_EXPIRY: z.string().default('30d'),
  LIDARR_URL: z.string().url(),
  LIDARR_API_KEY: z.string().min(1),
  MUSIC_LIBRARY_PATH: z.string().min(1),
  OFFLINE_STORAGE_PATH: z.string().default('./data/offline'),
  DB_PATH: z.string().default('./data/bimusic.db'),
  LOG_PATH: z.string().default('/var/log/bimusic'),
  ADMIN_USERNAME: z.string().default('admin'),
  ADMIN_PASSWORD: z.string().min(8),
});

export const env = envSchema.parse(process.env);
```

The server fails fast with a clear error message listing all missing or invalid variables.

## 10. File-Based Structured Logging

### 10.1 Pino Configuration

Pino is used for its low overhead, native JSON output, and simple API. Logs are written to `/var/log/bimusic/app.log`. Rotation is handled by OS-level logrotate (not pino-roll), keeping the Node process simple.

```typescript
import pino from 'pino';

const logger = pino({
  level: env.NODE_ENV === 'production' ? 'info' : 'debug',
  transport: env.NODE_ENV === 'development'
    ? { target: 'pino-pretty', options: { colorize: true } }
    : undefined,
}, pino.destination({
  dest: '/var/log/bimusic/app.log',
  sync: false,
}));
```

**Log rotation** is configured via OS logrotate (`/etc/logrotate.d/bimusic`):

```
/var/log/bimusic/*.log {
  daily
  rotate 14
  compress
  missingok
  notifempty
  copytruncate
}
```

Using `copytruncate` avoids the need for pino to reopen file handles after rotation.

### 10.2 Request Logging Middleware

Every HTTP request is logged with:
- Timestamp
- HTTP method and path
- Response status code
- Duration in milliseconds
- Request ID (generated UUID, attached via `X-Request-Id` header)

```json
{"level":30,"time":1711540201234,"requestId":"abc-123","method":"GET","path":"/api/library/artists","status":200,"duration":45}
```

### 10.3 What Gets Logged

- **Info:** Request/response, server startup, Lidarr proxy calls, offline job progress
- **Warn:** Slow requests (>5s), failed login attempts, Lidarr API errors that were retried
- **Error:** Unhandled exceptions, ffmpeg failures, database errors, Lidarr unreachable
- **Debug:** JWT decode details, ffmpeg command arguments, Lidarr raw responses (development only)

### 10.4 What Never Gets Logged

- Passwords (plaintext or hashed)
- JWT tokens (access or refresh)
- Lidarr API key
- Full request bodies on auth endpoints

## 11. LXC Deployment

### 11.1 Container Setup

Base: Debian 12 (Bookworm) or Ubuntu 22.04 LXC container

**Required packages:**
```bash
apt install -y nodejs npm ffmpeg sqlite3
# Or install Node.js 20 via NodeSource for latest LTS
```

### 11.2 Filesystem Layout

```
/opt/bimusic/              # Application root
├── dist/                  # Compiled JavaScript
├── node_modules/
├── data/
│   ├── bimusic.db         # SQLite database
│   └── offline/           # Transcoded offline files per user
├── package.json
└── .env                   # Environment configuration
/var/log/bimusic/          # Pino log files (app.log, access.log)
/music/                    # Bind-mount from host (Lidarr's music library, read-only)
```

### 11.3 Bind Mounts

| Host Path | Container Path | Mode | Purpose |
|---|---|---|---|
| Lidarr music library | `/music` | read-only | Source audio files for streaming |
| Persistent data volume | `/opt/bimusic/data` | read-write | SQLite DB + offline files |
| Persistent log volume | `/var/log/bimusic` | read-write | Pino log files (app.log, access.log) |

### 11.4 Process Management

**Systemd service (`/etc/systemd/system/bimusic.service`):**

```ini
[Unit]
Description=BiMusic Backend
After=network.target

[Service]
Type=simple
User=bimusic
Group=bimusic
WorkingDirectory=/opt/bimusic
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=5
EnvironmentFile=/opt/bimusic/.env
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
```

- `StandardOutput=null` / `StandardError=null` because logging is handled by Pino to files
- `Restart=always` with 5-second delay for automatic recovery
- Dedicated `bimusic` system user with minimal permissions

### 11.5 Ports

| Port | Protocol | Purpose |
|---|---|---|
| 3000 | TCP | BiMusic REST API (configurable via `PORT` env var) |

The LXC should expose port 3000 to the host network. If a reverse proxy (nginx/Caddy) is used on the host for TLS termination, it forwards to this port.

### 11.6 Build and Deploy

```bash
# On the container or via CI artifact
cd /opt/bimusic
npm ci --production=false   # Install all deps including devDeps for build
npm run build               # tsc -> dist/
npm prune --production      # Remove devDeps after build
npm start                   # Or: systemctl start bimusic
```

### 11.7 First Run Bootstrap

On first startup, if no users exist in the database:
1. Migrations run automatically
2. An admin user is created using `ADMIN_USERNAME` and `ADMIN_PASSWORD` from the environment
3. A log entry records the bootstrap
4. The admin should change the password after first login (future enhancement)

## 12. Implementation Sequence

Recommended build order based on dependency chain:

| Step | Module | Depends On |
|---|---|---|
| 1 | Project scaffold — package.json, tsconfig, env config, logger | — |
| 2 | Database — Drizzle schema, connection, migration runner | Step 1 |
| 3 | Auth — user service, JWT service, auth routes, middleware | Steps 1-2 |
| 4 | Lidarr client — typed HTTP client for Lidarr API | Step 1 |
| 5 | Library routes — artist/album/track browsing via proxy | Steps 3-4 |
| 6 | Streaming — ffmpeg transcoding endpoint | Steps 3-4 |
| 7 | Playlists — CRUD with playlist_tracks table | Steps 2-3 |
| 8 | Downloads (offline) — background worker, download endpoint | Steps 2-3, 6 |
| 9 | Search, requests, and pending request tracking — Lidarr search/add proxy + status poller | Steps 3-4 |
| 10 | Health endpoint and polish — /health, error handling improvements, request logging, admin bootstrap | Steps 1-9 |

Each step should include its corresponding unit and integration tests before moving to the next.
