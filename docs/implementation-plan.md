# BiMusic Implementation Plan

This document translates the architecture, backend, Flutter, QA, and UX plans into a sequenced, task-level implementation guide. Follow the phases in order — later phases depend on earlier ones.

**Reference documents:**
- `docs/architecture-plan.md` — system architecture and ADRs
- `docs/backend-plan.md` — backend routes, schema, services, deployment
- `docs/flutter-plan.md` — Flutter packages, providers, screens, offline
- `docs/qa-plan.md` — test strategy, coverage targets, CI YAML
- `docs/ux-plan.md` — screen layouts, interaction design

---

## Repository Layout

The repo is a monorepo with two top-level packages and a shared `docs/` directory:

```
BiMusic/
├── backend/          # Node.js / TypeScript REST API
├── bimusic_app/      # Flutter cross-platform client
├── docs/             # All planning documents
├── lidarr-openapi.json
└── STARTING-POINT.md
```

---

## Phase 0 — Repository & CI Skeleton

> **Status: COMPLETED** — 2026-03-27
> Files created: `backend/package.json`, `backend/tsconfig.json`, `backend/.eslintrc.json`, `backend/.env.example`, `backend/vitest.config.ts`, `backend/src/` tree, `backend/tests/` tree; `bimusic_app/pubspec.yaml`, `bimusic_app/lib/main.dart`, `bimusic_app/analysis_options.yaml`; `.github/workflows/ci.yml`; `.gitignore`.
> References: `docs/backend-plan.md §2–3`, `docs/qa-plan.md §5.1`, `docs/flutter-plan.md §1–2`.

**Goal:** Repo is structured, linters pass, and CI runs on every push before any feature code exists.

### Tasks

1. **Create `backend/` directory scaffold** — `package.json`, `tsconfig.json`, `.eslintrc.json`, `.env.example`, `vitest.config.ts`, empty `src/` and `tests/` trees per `backend-plan.md §2`.
2. **Create `bimusic_app/` Flutter project** — `flutter create bimusic_app --platforms android,ios,web,windows,linux`. Remove generated counter demo.
3. **Add `analysis_options.yaml`** to Flutter project referencing `flutter_lints`.
4. **Add CI workflow** `.github/workflows/ci.yml`:
   - Job `backend-lint`: `npm ci` → `npm run lint` → `npm run build`
   - Job `flutter-analyze`: `flutter pub get` → `dart run build_runner build` → `flutter analyze --fatal-infos`
   - These two jobs run in parallel; downstream jobs depend on both passing.
5. **Add `.gitignore`** entries for `backend/dist/`, `backend/node_modules/`, `bimusic_app/.dart_tool/`, `bimusic_app/build/`, `**/.env`.

### Completion criteria

`git push` triggers CI. Both lint jobs pass on empty scaffolds.

---

## Phase 1 — Backend Scaffold

> **Status: COMPLETED** — 2026-03-28
> Files created: `backend/src/config/env.ts`, `backend/src/utils/logger.ts`, `backend/src/app.ts`, `backend/src/index.ts`, `backend/src/middleware/errorHandler.ts`, `backend/src/routes/{health,auth,library,stream,offline,admin}.ts`, `backend/src/config/__tests__/env.test.ts`, `backend/vitest.workspace.ts`. Updated: `backend/package.json`, `backend/vitest.config.ts`, `backend/.env.example`.
> References: `docs/backend-plan.md §9–10`, `docs/architecture-plan.md §6.9`.

**Goal:** Express app boots, reads and validates environment, logs to file, handles unknown routes and errors gracefully.

### Tasks

1. **`backend/package.json`** — add all production and dev dependencies:
   - prod: `express@^5`, `better-sqlite3`, `drizzle-orm`, `jsonwebtoken`, `bcrypt`, `zod`, `pino`, `fluent-ffmpeg`, `axios`
   - dev: `typescript`, `@types/*`, `tsx`, `vitest`, `supertest`, `@types/supertest`, `eslint`, `@typescript-eslint/*`, `pino-pretty`

2. **`src/config/env.ts`** — zod schema validating all env vars from `backend-plan.md §9.1`. Server exits immediately with a clear error listing all missing/invalid fields.

3. **`src/utils/logger.ts`** — pino instance per `backend-plan.md §10.1`:
   - Development: pino-pretty transport to stdout
   - Production: `pino.destination()` to `LOG_PATH/app.log` (async, no sync writes on hot path)

4. **`src/app.ts`** — Express app factory (exported, not bound to a port):
   - JSON body parser
   - Request logger middleware (method, path, status, duration, `X-Request-Id`)
   - Mount all routers (stubs initially returning `501 Not Implemented`)
   - Global error handler (`src/middleware/errorHandler.ts`) — catches errors, returns `{ error: { code, message } }` per `architecture-plan.md §6.9`

5. **`src/index.ts`** — entry point:
   - Imports `env`, `logger`, `app`
   - Runs DB migrations
   - Binds HTTP listener on `env.PORT`
   - Handles `SIGTERM`/`SIGINT` for graceful shutdown

6. **`npm run dev`** script using `tsx watch src/index.ts` for development.

7. **Unit test:** `src/config/__tests__/env.test.ts` — validates that missing required vars throw with a useful message.

### Completion criteria

`npm run dev` starts the server. `GET /api/health` returns `503` (stub). `GET /api/nonexistent` returns `404 { error: { code: "NOT_FOUND" } }`. Env validation test passes.

---

## Phase 2 — Database + Auth

> **Status: COMPLETED** — 2026-03-28
> Files created: `backend/src/db/schema.ts`, `backend/src/db/connection.ts`, `backend/src/db/migrate.ts`, `backend/src/db/migrations/0000_initial.sql`, `backend/src/db/migrations/meta/_journal.json`, `backend/src/services/authService.ts`, `backend/src/services/userService.ts`, `backend/src/middleware/auth.ts`, `backend/src/routes/users.ts`, `backend/src/types/express.d.ts`, `backend/src/services/__tests__/authService.test.ts`, `backend/tests/setup.ts`, `backend/tests/integration/auth.test.ts`. Updated: `backend/src/routes/auth.ts`, `backend/src/app.ts`, `backend/src/index.ts`.
> All 29 tests pass (10 unit, 10 integration auth, 9 existing env tests).

**Goal:** Full JWT authentication works end-to-end. Admin user bootstrapped on first start.

### Tasks

#### 2a — Database

1. **`src/db/schema.ts`** — Drizzle table definitions for all 5 tables per `backend-plan.md §8.1`:
   - `users`, `refresh_tokens`, `playlists`, `playlist_tracks`, `offline_tracks`, `requests`
   - All BiMusic PKs: `text().primaryKey().$defaultFn(() => generateUUID())`
   - Lidarr IDs: `integer()` columns (not PKs — these are foreign references to Lidarr)

2. **`src/db/connection.ts`** — singleton `better-sqlite3` connection:
   - `PRAGMA journal_mode = WAL`
   - `PRAGMA foreign_keys = ON`
   - Wrapped in Drizzle: `drizzle(sqlite, { schema })`

3. **`src/db/migrations/`** — generate initial migration with `drizzle-kit generate`. Add `migrate()` call in `index.ts` before HTTP listener starts.

4. **UUID helper** — `lower(hex(randomblob(16)))` generated via SQLite default expression in the schema. Also provide a JS-side fallback using `crypto.randomUUID()` for use outside DB context.

#### 2b — Auth Service

5. **`src/services/authService.ts`**:
   - `login(username, password)` — look up user, `bcrypt.compare`, generate access + refresh tokens, insert `refresh_tokens` row
   - `refresh(rawToken)` — compute `HMAC-SHA256(JWT_REFRESH_SECRET, rawToken)`, look up by `token_hash`, delete old row, insert new row, return new token pair
   - `logout(rawToken)` — delete `refresh_tokens` row by hash
   - `generateAccessToken(user)` — `jwt.sign({ userId, username, isAdmin }, JWT_ACCESS_SECRET, { expiresIn: '15m', algorithm: 'HS256' })`
   - `generateRefreshToken()` — `crypto.randomBytes(64).toString('hex')`
   - `hashRefreshToken(raw)` — `createHmac('sha256', JWT_REFRESH_SECRET).update(raw).digest('hex')`

6. **`src/services/userService.ts`**:
   - `createUser(username, password, isAdmin)` — hash password with bcrypt (cost 12), insert user row
   - `getUser(id)`, `listUsers()`, `deleteUser(id)`
   - `bootstrapAdminIfNeeded()` — called from `index.ts`; if `users` table is empty, creates admin user from `ADMIN_USERNAME`/`ADMIN_PASSWORD` env vars and logs a startup message

#### 2c — Middleware

7. **`src/middleware/auth.ts`**:
   - `authenticate` — extracts Bearer token, calls `jwt.verify(token, JWT_ACCESS_SECRET)`, attaches `req.user = { userId, username, isAdmin }` to request
   - `requireAdmin` — checks `req.user.isAdmin`; returns 403 if not

#### 2d — Auth Routes

8. **`src/routes/auth.ts`** — implements all 4 auth endpoints per `backend-plan.md §4.2`:
   - `POST /api/auth/login` — zod-validate body, call `authService.login`, return tokens
   - `POST /api/auth/refresh` — zod-validate body, call `authService.refresh`
   - `POST /api/auth/logout` — requires `authenticate`, call `authService.logout`, return 204
   - `GET /api/auth/me` — requires `authenticate`, return `req.user` directly (no DB call)

9. **`src/routes/users.ts`** — admin-only CRUD (`GET /api/users`, `POST /api/users`, `DELETE /api/users/:id`), all require `authenticate` + `requireAdmin`.

#### 2e — Tests

10. **Unit tests** (`src/services/__tests__/authService.test.ts`):
    - Correct password → returns access + refresh tokens
    - Wrong password → throws `UNAUTHORIZED`
    - Refresh with valid token → rotates correctly
    - Refresh with expired token → throws `UNAUTHORIZED`
    - Refresh with already-used token → throws `UNAUTHORIZED` (rotation prevents reuse)

11. **Integration tests** (`tests/integration/auth.test.ts`) via supertest:
    - `POST /login` with valid creds → 200 with tokens
    - `POST /login` with bad password → 401
    - `GET /me` with valid access token → 200 with user payload
    - `GET /me` with expired/invalid token → 401
    - `POST /refresh` → returns new token pair, old refresh token is invalidated
    - `POST /logout` → 204, subsequent refresh with same token → 401

### Completion criteria

Auth integration tests pass. Admin user is created on first startup. Curl can log in and use the returned JWT to hit `/api/auth/me`.

---

## Phase 3 — Lidarr Client

> **Status: COMPLETED** — 2026-03-28
> Files created: `backend/src/types/lidarr.ts`, `backend/src/services/lidarrClient.ts`, `backend/src/services/__tests__/lidarrClient.test.ts`. Installed: `nock`, `@types/nock`.
> All 50 tests pass (21 new lidarrClient unit tests + 29 existing).

**Goal:** Typed HTTP client for all Lidarr endpoints the backend needs. No routes yet — this is the foundation for library, stream, search, and requests.

### Tasks

1. **`src/types/lidarr.ts`** — TypeScript interfaces for raw Lidarr API responses:
   - `LidarrArtist`, `LidarrAlbum`, `LidarrTrack`, `LidarrTrackFile`, `LidarrSearchResult`, `LidarrQueue`, `LidarrCommand`
   - Derive field names from `lidarr-openapi.json` — only include fields BiMusic actually uses

2. **`src/services/lidarrClient.ts`** — axios instance + typed methods per `backend-plan.md §7`:
   ```
   baseURL: LIDARR_URL/api/v1
   headers: { X-Api-Key: LIDARR_API_KEY }
   timeout: 30000
   ```
   Implement all methods from the method mapping table in `backend-plan.md §7.2`. Error mapping: Lidarr 404 → BiMusic 404; Lidarr 5xx → 502 with `LIDARR_ERROR` code; timeout → 504.

3. **Unit tests** (`src/services/__tests__/lidarrClient.test.ts`) — use `nock` to stub Lidarr responses for each method, verify correct URL construction and response shaping.

### Completion criteria

All `lidarrClient` methods have unit tests with nock stubs passing.

---

## Phase 4 — Library API

> **Status: COMPLETED** — 2026-03-28
> Files created: `backend/src/types/api.ts`, `backend/src/services/libraryService.ts`, `backend/tests/integration/library.test.ts`. Updated: `backend/src/routes/library.ts`, `backend/src/config/env.ts` (added `API_BASE_URL`), `backend/.env.example`, `backend/tests/setup.ts`.
> All 62 tests pass (12 new library integration tests + 50 existing).

**Goal:** All `/api/library/*` endpoints work. Flutter client can browse artists, albums, and tracks.

### Tasks

1. **`src/types/api.ts`** — shaped response types `Artist`, `Album`, `Track`, `TrackFile` per `architecture-plan.md §8` (the simplified types the Flutter client sees, not raw Lidarr types).

2. **`src/services/libraryService.ts`** — methods that call `lidarrClient`, reshape the response to API types, and add `streamUrl` and `imageUrl` fields:
   - `getArtists()` → `Artist[]`
   - `getArtist(id)` → `Artist`
   - `getArtistAlbums(artistId)` → `Album[]`
   - `getAlbum(id)` → `Album`
   - `getAlbumTracks(albumId)` → `Track[]`
   - `getTrack(id)` → `Track`
   - `streamUrl`: `${API_BASE_URL}/api/stream/${trackId}`
   - `imageUrl` for artists: `${API_BASE_URL}/api/library/artists/${id}/image`
   - `imageUrl` for albums: `${API_BASE_URL}/api/library/albums/${id}/image`

3. **`src/routes/library.ts`** — mount all library endpoints per `architecture-plan.md §6.4`:
   - `GET /api/library/artists`
   - `GET /api/library/artists/:id`
   - `GET /api/library/artists/:id/albums`
   - `GET /api/library/albums/:id`
   - `GET /api/library/albums/:id/tracks`
   - `GET /api/library/tracks/:id`
   - `GET /api/search?term=`
   - `GET /api/library/artists/:id/image` — pipe Lidarr image stream through (do not buffer)
   - `GET /api/library/albums/:id/image` — pipe Lidarr image stream through

4. **Integration tests** with nock-stubbed Lidarr:
   - Artists list returns shaped array
   - Single artist returns with `imageUrl` pointing to BiMusic proxy URL
   - Image proxy streams content-type header from Lidarr

### Completion criteria

With Lidarr nock stubs, all library route integration tests pass. Image proxy returns binary content.

---

## Phase 5 — Streaming

> **Status: COMPLETED** — 2026-03-28
> Files created: `backend/src/services/streamService.ts`, `backend/tests/integration/stream.test.ts`. Updated: `backend/src/routes/stream.ts`, `backend/src/index.ts`.
> All 71 tests pass (9 new streaming integration tests + 62 existing).

**Goal:** `GET /api/stream/:trackId` transcodes via ffmpeg and serves with full HTTP Range / seeking support.

### Tasks

1. **`/tmp/bimusic/` management** — on server startup, clear the directory (create if missing). Export a `startTempFileCleanup()` function that schedules `setInterval` hourly cleanup removing files older than 24 hours.

2. **`src/services/streamService.ts`**:
   - `resolveFilePath(trackId)` — calls `lidarrClient.getTrack(id)` then `lidarrClient.getTrackFile(trackFileId)` to get on-disk path. Verify path exists and is readable.
   - `getTempFilePath(sourcePath, bitrate)` — returns `/tmp/bimusic/<sha256(sourcePath+bitrate)>.mp3`
   - `isPassthrough(sourcePath, requestedBitrate)` — returns true if file is MP3 and bitrate is at or below requested
   - `ensureTranscoded(sourcePath, bitrate)` — check temp file exists; if not, run ffmpeg to completion:
     ```
     ffmpeg -i <sourcePath> -vn -codec:a libmp3lame -b:a <bitrate>k <tempPath>
     ```
     Track in-progress transcodes in a `Map<string, Promise<void>>` so concurrent requests for the same file wait on the same promise.
   - `serveFile(filePath, req, res)` — handle Range header, set `Accept-Ranges: bytes`, serve `206 Partial Content` or `200`. Use `fs.createReadStream` with `start`/`end`.

3. **`src/routes/stream.ts`** — `GET /api/stream/:trackId`:
   - Require `authenticate`
   - Parse `?bitrate=128|320` (default 320, validate strictly)
   - Call `streamService.resolveFilePath`, `isPassthrough`, `ensureTranscoded`, `serveFile`
   - On ffmpeg error: delete partial temp file, return `500 { error: { code: "TRANSCODE_ERROR" } }`

4. **Integration tests**:
   - Stream MP3 source (passthrough): verify `Accept-Ranges: bytes` header, Range request returns `206`
   - Stream FLAC source (transcode): temp file created, Range request returns `206`
   - Concurrent requests for same track: only one ffmpeg process spawned
   - Invalid bitrate: `400` error

### Completion criteria

Streaming integration tests pass with fixture audio files. `GET /api/stream/1?bitrate=320` with a real FLAC file returns seekable MP3.

---

## Phase 6 — Playlists

**Goal:** Full playlist CRUD with track ordering.

### Tasks

1. **`src/services/playlistService.ts`** — all methods operating on `playlists` and `playlist_tracks` tables:
   - `listPlaylists(userId)`, `createPlaylist(userId, name)`, `getPlaylist(id, userId)`, `updatePlaylist(id, userId, name)`, `deletePlaylist(id, userId)`
   - `addTracks(playlistId, userId, trackIds, insertPosition?)` — insert at end or at position, shift existing positions
   - `removeTrack(playlistId, userId, lidarrTrackId)` — delete and repack positions
   - `reorderTracks(playlistId, userId, orderedTrackIds)` — reassign positions in a transaction

2. **`src/routes/playlists.ts`** — all 8 endpoints per `backend-plan.md §4.8`. Validate that the authenticated user owns the playlist before any mutation (return 404 to avoid leaking existence).

3. **Integration tests** — create playlist, add tracks, reorder, remove track, delete playlist. Verify another user cannot access or modify.

### Completion criteria

Playlist integration test suite passes.

---

## Phase 7 — Offline Downloads

**Goal:** Backend records download requests, serves transcoded files for offline storage, tracks status.

### Tasks

1. **`src/services/downloadService.ts`**:
   - `requestDownload(userId, deviceId, trackId, bitrate)` — upsert into `offline_tracks` with `status: 'pending'`
   - `listDownloads(userId, deviceId)` — query `offline_tracks` for user+device
   - `deleteDownload(id, userId)` — verify ownership, delete row
   - Background worker: `setInterval` every 10 seconds polling for `status: 'pending'` rows, transcoding one at a time using same ffmpeg pipeline as streaming (but always to `OFFLINE_STORAGE_PATH/<userId>/<trackId>-<bitrate>.mp3`), updating `status` to `ready` or `failed`

2. **`src/routes/downloads.ts`** — per `backend-plan.md §4.7`:
   - `POST /api/downloads` — validate `{ trackId, deviceId, bitrate }` with zod
   - `GET /api/downloads?deviceId=` — require `deviceId` query param
   - `DELETE /api/downloads/:id`
   - `GET /api/downloads/:id/file` — verify ownership, serve the transcoded file with `Content-Disposition: attachment`, update status to `complete`

3. **Integration tests** — request download, verify `pending` status; simulate worker completion; fetch file; delete record.

### Completion criteria

Download integration tests pass. File is served correctly.

---

## Phase 8 — Search & Music Requests

**Goal:** Users can search the Lidarr catalog and request new music, tracking status of pending requests.

### Tasks

1. **`src/routes/search.ts`** (or merge into `library.ts`):
   - `GET /api/search?term=` — proxy to Lidarr `/api/v1/search`

2. **`src/routes/requests.ts`**:
   - `GET /api/requests/search?term=` — proxy Lidarr artist and album lookup, return combined results
   - `POST /api/requests/artist` — add artist to Lidarr, trigger `ArtistSearch` command, insert `requests` row with `status: 'pending'`
   - `POST /api/requests/album` — monitor album in Lidarr, trigger search, insert `requests` row
   - `GET /api/requests` — list user's requests; for each with `status != 'available'`, live-check Lidarr:
     - Artist: `GET /api/v1/artist/:lidarrId` → if `statistics.trackFileCount > 0`, set `available`
     - Album: `GET /api/v1/album/:lidarrId` → if `statistics.trackFileCount > 0`, set `available`
     - Also check Lidarr queue to detect `downloading` status

3. **Integration tests** — add artist request, verify `requests` row created; simulate Lidarr returning `trackFileCount > 0`; verify status updates to `available`.

### Completion criteria

All search and request integration tests pass.

---

## Phase 9 — Health, Admin Bootstrap, and Polish

**Goal:** Backend is feature-complete and production-ready.

### Tasks

1. **`GET /api/health`** — return `{ status: "ok", version: "<from package.json>" }`. No auth. Used by reverse proxy.

2. **Admin bootstrap** — wire `userService.bootstrapAdminIfNeeded()` call in `index.ts` after migrations complete.

3. **Error handler polish** — ensure all unhandled promise rejections and synchronous throws in route handlers reach the global error handler. Log `error`-level for 5xx, `warn`-level for 4xx. Never leak stack traces in production (`NODE_ENV === 'production'`).

4. **Startup/shutdown sequence** — on SIGTERM: stop accepting new connections, wait for in-flight requests (5s timeout), kill active ffmpeg processes, flush pino logs, exit 0.

5. **Backend coverage check** — run `vitest --coverage` and verify ≥ 80% line coverage.

### Completion criteria

`GET /api/health` returns `200`. Coverage gate passes. Backend is feature-complete.

---

## Phase 10 — Flutter Scaffold

> **Status: COMPLETED** — 2026-03-28
> Files created: `bimusic_app/pubspec.yaml`, `bimusic_app/build.yaml`, `bimusic_app/lib/config/api_config.dart`, `bimusic_app/lib/config/theme.dart`, `bimusic_app/lib/app.dart`, `bimusic_app/lib/main.dart`, `bimusic_app/lib/router.dart`, `bimusic_app/lib/ui/layouts/breakpoints.dart`, `bimusic_app/lib/ui/layouts/mobile_layout.dart`, `bimusic_app/lib/ui/layouts/desktop_layout.dart`, `bimusic_app/lib/ui/widgets/adaptive_scaffold.dart`, `bimusic_app/lib/ui/screens/{login,home,library,artist_detail,album_detail,search,playlists,playlist_detail,downloads,settings}_screen.dart`.
> `flutter analyze --fatal-infos` passes. All nav tabs switch screens. Dark mode works.

**Goal:** Flutter app builds for all targets, navigation shell works, theme is set.

### Tasks

1. **`pubspec.yaml`** — add all packages from `flutter-plan.md §3` with pinned version ranges. Run `flutter pub get`.

2. **Code generation setup** — add `build.yaml`. Run `dart run build_runner build --delete-conflicting-outputs` to verify code gen works.

3. **`lib/config/api_config.dart`** — `baseUrl`, `connectTimeout`, `receiveTimeout` constants. Read base URL from env or a compile-time constant (`--dart-define=API_BASE_URL=...`).

4. **`lib/config/theme.dart`** — Material 3 theme with `ColorScheme.fromSeed`. Light and dark themes.

5. **`lib/app.dart`** — `MaterialApp.router` wired to go_router. Initial route: redirect to `/login` if not authenticated, else `/home`.

6. **`lib/ui/layouts/`** — `AdaptiveScaffold` that switches between `MobileLayout` (bottom nav) and `DesktopLayout` (sidebar) based on `MediaQuery.sizeOf(context).width` per `flutter-plan.md §6`.

7. **go_router setup** — define all routes: `/login`, `/home` (shell with tabs), `/library`, `/artist/:id`, `/album/:id`, `/search`, `/playlists`, `/playlist/:id`, `/downloads`, `/settings`. Shell route wraps the nav + mini-player.

8. **All screens** — stub `Scaffold` with `AppBar(title: Text('Screen Name'))`.

9. **`flutter analyze --fatal-infos`** must pass.

### Completion criteria

App launches. Nav tabs switch screens. Dark mode works. Analyze passes.

---

## Phase 11 — Flutter Auth

> **Status: COMPLETED** — 2026-03-28
> Files created: `bimusic_app/lib/models/user.dart`, `bimusic_app/lib/models/auth_tokens.dart`, `bimusic_app/lib/services/auth_service.dart`, `bimusic_app/lib/services/api_client.dart`, `bimusic_app/lib/providers/auth_provider.dart`, `bimusic_app/test/providers/auth_notifier_test.dart`, `bimusic_app/test/services/auth_interceptor_test.dart`. Updated: `bimusic_app/lib/router.dart`, `bimusic_app/lib/app.dart`, `bimusic_app/lib/ui/screens/login_screen.dart`.
> All 13 unit tests pass. `flutter analyze --fatal-infos` passes.

**Goal:** Login screen, secure token storage, auto-refresh, and auth-guarded routing work end-to-end.

### Tasks

1. **`lib/models/auth_tokens.dart`** — freezed model with `accessToken`, `refreshToken`, `user`.

2. **`lib/services/api_client.dart`** — Dio instance with `AuthInterceptor` per `flutter-plan.md §7`:
   - Attaches `Authorization: Bearer <jwt>` to every request
   - On 401: attempt refresh via `authService.refreshToken()`; retry original request once on success; force logout on failure
   - Concurrent refresh protection via `Completer` (one in-flight refresh at a time)

3. **`lib/services/auth_service.dart`** — `login()`, `refresh()`, `logout()`, `storeTokens()`, `clearTokens()`, `readStoredTokens()` using `flutter_secure_storage`.

4. **`lib/providers/auth_provider.dart`** — `AuthNotifier` managing `AuthState` (unauthenticated, loading, authenticated). Reads tokens from secure storage on startup, calls `/api/auth/refresh` to validate, navigates accordingly.

5. **`lib/ui/screens/login_screen.dart`** — per UX plan: centered card, username + password fields (with show/hide toggle), "Sign In" button, inline error display, loading state. No self-registration.

6. **go_router redirect** — `redirect` callback watches `authProvider`; redirects to `/login` if unauthenticated, to `/home` if authenticated and at `/login`.

7. **Unit tests**:
   - `AuthNotifier` — login success/failure, refresh on startup, logout clears state
   - `AuthInterceptor` — 401 triggers refresh, retry succeeds, concurrent refresh protection

### Completion criteria

Login screen works against real backend. Refresh token persists across app restarts. Expired session redirects to login.

---

## Phase 12 — Flutter Library

> **Status: COMPLETED** — 2026-03-28
> Files created: `lib/models/artist.dart`, `lib/models/album.dart`, `lib/models/track.dart`, `lib/models/search_results.dart` (all freezed + json_serializable); `lib/services/music_service.dart`; `lib/providers/library_provider.dart`; `lib/ui/widgets/artist_card.dart`, `lib/ui/widgets/album_card.dart`, `lib/ui/widgets/track_tile.dart`; `lib/ui/screens/library_screen.dart`, `lib/ui/screens/artist_detail_screen.dart`, `lib/ui/screens/album_detail_screen.dart` (replaced stubs); `test/ui/album_detail_screen_test.dart`, `test/ui/track_tile_test.dart`.
> References: `docs/flutter-plan.md`, `docs/ux-plan.md`.

**Goal:** Browse artists, albums, and tracks. Album art loads and caches.

### Tasks

1. **Models** — `artist.dart`, `album.dart`, `track.dart` with `@freezed` + `@JsonSerializable`. Include `imageUrl` and `streamUrl` fields that come pre-built from the backend.

2. **`lib/services/music_service.dart`** — `getArtists()`, `getArtist(id)`, `getAlbumTracks(albumId)`, `getAlbum(id)`, `searchLibrary(term)`. All use the Dio instance with auth interceptor.

3. **`lib/providers/library_provider.dart`** — `AsyncNotifier` loading artists on first use. Cached until explicit refresh.

4. **Screens**:
   - `LibraryScreen` — grid or list of artists. Pull-to-refresh. Tap navigates to `ArtistDetailScreen`.
   - `ArtistDetailScreen` — artist name, image, album grid. Tap album → `AlbumDetailScreen`.
   - `AlbumDetailScreen` — album cover, title, release year, track list (`TrackTile` per track). Tap track → start playback.

5. **`TrackTile` widget** — track number, title, duration. Tapping plays the track. Shows offline indicator if downloaded.

6. **`AlbumCard` / `ArtistCard` widgets** — `CachedNetworkImage` with auth header injection (use `imageHeaders` parameter). Placeholder shimmer on load.

7. **Widget tests** — `AlbumDetailScreen` renders track list from mocked provider state; `TrackTile` tap triggers play action.

### Completion criteria

Library browses end-to-end against real backend. Album art loads. Tapping a track will trigger playback (even if player is a stub at this point).

---

## Phase 13 — Flutter Audio Playback

> **Status: COMPLETED** — 2026-03-28
> Files created: `bimusic_app/lib/services/audio_service.dart`, `bimusic_app/lib/providers/connectivity_provider.dart`, `bimusic_app/lib/providers/bitrate_provider.dart`, `bimusic_app/lib/providers/player_provider.dart`, `bimusic_app/lib/ui/widgets/player_bar.dart`, `bimusic_app/lib/ui/widgets/full_player.dart`, `bimusic_app/test/ui/player_bar_test.dart`, `bimusic_app/test/ui/full_player_test.dart`. Updated: `bimusic_app/lib/main.dart`, `bimusic_app/lib/ui/layouts/mobile_layout.dart`, `bimusic_app/lib/ui/layouts/desktop_layout.dart`, `bimusic_app/lib/ui/screens/album_detail_screen.dart`.
> References: `docs/flutter-plan.md §5`, `docs/ux-plan.md`.

**Goal:** Tracks play, seeking works, media controls appear on lock screen and notifications.

### Tasks

1. **`lib/services/audio_service.dart`** — `AudioHandler` subclass wrapping `just_audio`:
   - `playFromUrl(url, headers, track)` — set `AudioSource.uri` with auth header
   - `playFromFile(path, track)` — set `AudioSource.file` for offline
   - Queue management via `ConcatenatingAudioSource` for gapless album/playlist playback
   - Handle interruptions (phone calls, other apps) via `audio_session`

2. **`lib/providers/player_provider.dart`** — `PlayerNotifier` managing `PlayerState`:
   - `currentTrack`, `queue`, `isPlaying`, `position`, `duration`, `repeatMode`, `isShuffled`
   - Methods: `play(track, queue)`, `pause()`, `resume()`, `seekTo(position)`, `skipNext()`, `skipPrev()`, `setRepeat()`, `toggleShuffle()`
   - Selects bitrate from `connectivityProvider` at play time

3. **`lib/providers/connectivity_provider.dart`** — `StreamProvider<ConnectivityResult>` via `connectivity_plus`.

4. **`lib/providers/bitrate_provider.dart`** — derives 128 or 320 from `connectivityProvider` per `flutter-plan.md §10`.

5. **`lib/ui/widgets/player_bar.dart`** (mini-player):
   - Shows album art thumbnail, track title, artist name, play/pause button, progress indicator
   - Tapping the bar expands to `FullPlayer` (slide-up `DraggableScrollableSheet` or navigation)

6. **`lib/ui/widgets/full_player.dart`** (full-screen now-playing):
   - Large album art, track info, full progress bar (draggable), play/pause, skip prev/next, repeat, shuffle, queue list
   - Progress bar seeks via `playerNotifier.seekTo(position)` → backend serves Range response

7. **`audio_service` integration** — register `AudioHandler` with `AudioService.init()` in `main()`. Lock screen controls, notification controls, and media key support.

8. **Widget tests**:
   - `PlayerBar` shows correct track name; play/pause button triggers correct action
   - `FullPlayer` progress bar is interactive

### Completion criteria

Tap a track in `AlbumDetailScreen` → audio plays. Progress bar is draggable. Lock screen shows controls on mobile. Skip works.

---

## Phase 14 — Flutter Search & Music Requests

**Goal:** Search the library and request new music from Lidarr.

### Tasks

1. **`lib/providers/search_provider.dart`** — `StateNotifier<SearchState>`:
   - Library search (debounced 300ms): calls `/api/search?term=`
   - Lidarr lookup (for requests): calls `/api/requests/search?term=`
   - Request submission state

2. **`lib/ui/screens/search_screen.dart`** — per UX plan:
   - Search field at top. Debounced results below.
   - Two tabs: "In Library" (library search results) and "Request Music" (Lidarr lookup)
   - Result items show artist/album name, cover, and either a "Play" button (in library) or a "Request" button (not in library)
   - Tapping "Request" → shows confirmation sheet → `POST /api/requests/artist` or `POST /api/requests/album`

3. **`lib/ui/screens/` — Pending Requests screen** (or section within Search):
   - `GET /api/requests` on load
   - Shows each request with status badge: Pending / Downloading / Available
   - Status color-coded. Available items link to the artist/album in library.

4. **Unit tests** — `SearchNotifier` debounce behavior, request submission state transitions.

### Completion criteria

Search returns library results. Lidarr lookup works. Requesting an artist creates a pending request visible in the requests list.

---

## Phase 15 — Flutter Playlists

**Goal:** Create, edit, and play playlists.

### Tasks

1. **`lib/providers/playlist_provider.dart`** — `AsyncNotifier` for user playlists. Methods: `createPlaylist()`, `addTracks()`, `removeTrack()`, `reorderTracks()`, `deletePlaylist()`.

2. **Screens**:
   - `PlaylistScreen` — list of playlists with track count and created date. Floating action button to create new. Tap → `PlaylistDetailScreen`.
   - `PlaylistDetailScreen` — playlist name, track list (reorderable via `ReorderableListView`), play all button, edit name button, delete button.

3. **`TrackTile` context menu** — long-press shows bottom sheet: "Add to Playlist" (shows playlist picker), "Download" (mobile/desktop only), "Remove from Playlist" (if in playlist detail).

4. **Widget tests** — `PlaylistDetailScreen` renders track list; reorder interaction triggers notifier method.

### Completion criteria

Create a playlist. Add tracks from an album. Reorder. Play. Delete.

---

## Phase 16 — Flutter Offline Downloads (Mobile + Desktop)

**Goal:** Users can download albums for offline listening. Downloads persist across app restarts.

### Tasks

1. **Isar setup** — define `DownloadTaskSchema` collection. Open Isar in `main()` before `runApp()`. Schema fields per `flutter-plan.md §9`.

2. **Device ID** — `getOrCreateDeviceId()` per `flutter-plan.md §9`. Store in `flutter_secure_storage`.

3. **`lib/services/download_service.dart`** — handles actual file download:
   - `downloadFile(taskId, trackId, deviceId, filePath)` — `GET /api/downloads/:id/file` with Dio, stream bytes to `filePath`, track progress via `onReceiveProgress`
   - Max 2 concurrent downloads
   - Pause/resume on connectivity loss

4. **`lib/providers/download_provider.dart`** — `StateNotifier<DownloadState>`:
   - Loads existing Isar records on startup
   - `requestDownload(track, album, artist)` — `POST /api/downloads`, create Isar record, enqueue
   - `cancelDownload(id)`, `removeDownload(id)` — `DELETE /api/downloads/:id`, delete local file, remove Isar record
   - Progress updates from `DownloadService`

5. **`flutter_background_service` (mobile)** — initialize in `main()` on mobile platforms only (`!kIsWeb && (Platform.isAndroid || Platform.isIOS)`). Background service calls `DownloadService` to process queue. Foreground notification shows active download progress.

6. **`lib/ui/screens/downloads_screen.dart`** — per UX plan:
   - Storage usage bar (`storageUsageProvider`)
   - List of downloads grouped by album, with progress indicators for active downloads
   - Swipe to delete. Bulk delete by album.
   - Hidden entirely on web (`if (!kIsWeb)`)

7. **Update `TrackTile`** — show download indicator (downloading/downloaded/not downloaded). Desktop/mobile only.

8. **Update `AlbumDetailScreen`** — "Download Album" button (mobile/desktop only). Shows total size and download progress.

9. **Offline playback** — `playerProvider.play(track)` checks `downloadProvider` for local file path; uses `AudioSource.file()` if available.

10. **Integration tests** — request download, simulate completion, play offline track (mocked audio source).

### Completion criteria

Download an album. Background download continues when app is backgrounded (mobile). Play downloaded track without network.

---

## Phase 17 — Flutter Settings

**Goal:** Settings screen with useful controls and debug info.

### Tasks

1. **`lib/ui/screens/settings_screen.dart`** — per UX plan:
   - **Account section:** Display name, username. "Log Out" button.
   - **Playback section:** Default bitrate override toggle (always low / always high / automatic). Crossfade duration slider (future, placeholder).
   - **Storage section (mobile/desktop only):** Storage usage display. "Clear All Downloads" button with confirmation.
   - **Debug section (admin only):** Log file viewer (last 200 lines from `LogService`). "Export Logs" button. Backend version and health status.
   - **About:** App version, links.

2. **App version** — read from `pubspec.yaml` at build time via `package_info_plus` package.

### Completion criteria

Settings screen renders all sections. Logout works. Storage usage is accurate.

---

## Phase 18 — Testing Pass

**Goal:** All coverage targets from `qa-plan.md §1.2` are met.

### Tasks

#### Backend

1. Run `vitest --coverage --reporter=verbose`. Identify files below 80% line coverage.
2. Add unit tests for any uncovered service methods.
3. Verify 100% of public API routes have at least one integration test (use the route listing in `backend-plan.md §4` as a checklist).
4. Add the 56 test scenarios from `qa-plan.md §7` — P0 scenarios first, then P1, then P2.

#### Flutter

5. Run `flutter test --coverage`. Identify screens with no widget test.
6. Add widget tests for every screen (at least one smoke test per screen).
7. Verify `AuthInterceptor` unit tests cover: token attached, 401 triggers refresh, concurrent protection, refresh failure forces logout.
8. Run integration tests (`flutter test integration_test/`) against a local backend instance.

#### CI

9. Wire coverage gates into CI per `qa-plan.md §5` — fail pipeline if backend < 80% or Flutter < 70%.
10. Add the full GitHub Actions YAML from `qa-plan.md §5` as `.github/workflows/ci.yml`. Stages:
    - Stage 1 (parallel): backend lint+unit, Flutter analyze+unit
    - Stage 2: backend integration (real SQLite + nock Lidarr)
    - Stage 3: Flutter E2E on web target (headless Chrome)
    - Stage 4: build matrix (Android APK, web, Windows, Linux)

### Completion criteria

CI pipeline is green. Backend ≥ 80% line coverage. Flutter ≥ 70% line coverage. All P0 test scenarios pass.

---

## Phase 19 — Deployment

**Goal:** Backend runs in LXC under systemd. Reverse proxy terminates TLS. Logrotate configured.

### Tasks

1. **LXC container setup** (Debian 12):
   ```bash
   apt install -y nodejs npm ffmpeg sqlite3
   # Or: use NodeSource for Node.js 20 LTS
   curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
   apt install -y nodejs
   ```

2. **Create `bimusic` system user:**
   ```bash
   useradd --system --shell /bin/false --home /opt/bimusic bimusic
   ```

3. **Filesystem setup** — create all directories from `backend-plan.md §13`:
   ```bash
   mkdir -p /opt/bimusic/{dist,data} /var/log/bimusic /tmp/bimusic
   chown -R bimusic:bimusic /opt/bimusic /var/log/bimusic /tmp/bimusic
   chmod 700 /opt/bimusic/data   # DB directory private to bimusic user
   ```

4. **Deploy backend:**
   ```bash
   cd /opt/bimusic
   git clone <repo> .
   cd backend && npm ci && npm run build && npm prune --production
   cp .env.example .env && nano .env  # fill in secrets
   ```

5. **Generate secrets:**
   ```bash
   openssl rand -hex 64  # for JWT_ACCESS_SECRET
   openssl rand -hex 64  # for JWT_REFRESH_SECRET
   ```

6. **Systemd service** — create `/etc/systemd/system/bimusic.service` per `backend-plan.md §11.4`:
   ```bash
   systemctl daemon-reload
   systemctl enable bimusic
   systemctl start bimusic
   systemctl status bimusic
   ```

7. **Logrotate** — create `/etc/logrotate.d/bimusic` per `backend-plan.md §10.1` with `copytruncate`, `daily`, 14-day retention.

8. **Reverse proxy** (host, not LXC) — configure Caddy or nginx to terminate TLS and forward to `<lxc-ip>:3000`. Example Caddyfile:
   ```
   music.yourdomain.com {
     reverse_proxy <lxc-ip>:3000
   }
   ```

9. **Verify first run** — check `journalctl -u bimusic -f` for startup logs. Call `GET /api/health`. Log in with admin credentials.

10. **Flutter release builds** — from a local dev machine or CI:
    ```bash
    flutter build apk --release --dart-define=API_BASE_URL=https://music.yourdomain.com
    flutter build web --release --dart-define=API_BASE_URL=https://music.yourdomain.com
    flutter build windows --release --dart-define=API_BASE_URL=https://music.yourdomain.com
    ```

11. **Deploy `build/web/`** — serve from Caddy or nginx as static files (or serve from the same Caddy config on a `/` sub-path if desired).

### Completion criteria

Backend responds to HTTPS requests. Admin can log in. A track streams. iOS/Android APK installs and connects.

---

## Summary: Build Order

| Phase | Scope | Depends On |
|-------|-------|------------|
| 0 | Repo + CI skeleton | — |
| 1 | Backend scaffold (env, logger, app factory) | 0 |
| 2 | Database + Auth (schema, JWT, routes, middleware) | 1 |
| 3 | Lidarr client (typed HTTP client) | 1 |
| 4 | Library API (artist/album/track/image proxy) | 2, 3 |
| 5 | Streaming (ffmpeg, temp files, Range) | 2, 3 |
| 6 | Playlists (CRUD, track ordering) | 2 |
| 7 | Offline downloads (record, worker, file serve) | 2, 5 |
| 8 | Search + Requests (Lidarr lookup, pending tracking) | 2, 3 |
| 9 | Health, bootstrap, polish | 1–8 |
| 10 | Flutter scaffold (routing, layouts, theme) | 0 |
| 11 | Flutter auth (login, token storage, interceptor) | 10, 2 |
| 12 | Flutter library (browse artists/albums/tracks) | 11, 4 |
| 13 | Flutter audio (just_audio, player bar, seeking) | 12, 5 |
| 14 | Flutter search + requests | 13, 8 |
| 15 | Flutter playlists | 13, 6 |
| 16 | Flutter offline downloads | 13, 7 |
| 17 | Flutter settings | 11–16 |
| 18 | Testing pass (coverage gates, CI YAML) | 9, 17 |
| 19 | LXC deployment | 9, 17 |

Phases 1–9 (backend) and 10–17 (Flutter) can largely proceed in parallel once Phase 0 is done, with Flutter blocked only on specific backend phases being deployed or running locally.
