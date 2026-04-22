# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BiMusic is a self-hosted music streaming app with a **Node.js/TypeScript backend** (`backend/`) and a **Flutter client** (`bimusic_app/`). The backend integrates with Lidarr for music library management and uses FFmpeg for audio transcoding.

## Build & Development Commands

### Backend (`backend/`)

| Task | Command |
|---|---|
| Install deps | `npm ci` |
| Dev server (watch) | `npm run dev` |
| Type-check | `npm run build` (runs `tsc --noEmit`) |
| Lint | `npm run lint` |
| Format check | `npm run format:check` |
| All tests | `npm test` |
| Unit tests only | `npm run test:unit` |
| Integration tests only | `npm run test:integration` |
| Coverage report | `npm run test:coverage` (80% line threshold enforced) |
| Single test file | `npx vitest run path/to/file.test.ts` |
| Single test by name | `npx vitest run -t "test name pattern"` |

Copy `.env.example` to `.env` for local development. Requires `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET` (≥32 chars each) and `ADMIN_PASSWORD` (≥8 chars). `HLS_CACHE_DIR` sets the directory for HLS segment cache files (default `./data/hls`). `HLS_SEGMENT_SECONDS` sets the duration of each HLS segment in seconds (default `6`). `OFFLINE_STORAGE_PATH` sets the directory for offline download files (default `./data/offline`); files are stored under `<OFFLINE_STORAGE_PATH>/<userId>/<trackId>-<bitrate>.mp3`.

### Flutter Client (`bimusic_app/`)

Flutter SDK is at `/c/dev/flutter` and **not on the default PATH**:

```bash
export PATH="/c/dev/flutter/bin:$PATH"
```

| Task | Command |
|---|---|
| Get deps | `flutter pub get` |
| Code generation | `dart run build_runner build --delete-conflicting-outputs` |
| Analyze | `flutter analyze --fatal-infos` |
| Run tests | `flutter test` |
| Single test file | `flutter test test/some_test.dart` |

## Architecture

### Backend

- **Module system:** CommonJS (no `"type": "module"` in `package.json`). Use `__dirname` for path resolution — `import.meta.url` is not available and will cause a compile error.
- **Framework:** Express 5 with TypeScript strict mode
- **Database:** SQLite via `better-sqlite3` + Drizzle ORM. Schema in `src/db/schema.ts`, migrations in `src/db/migrations/`
- **Auth:** JWT with separate access/refresh secrets. Refresh tokens stored as HMAC-SHA256 hashes. The `authenticate` middleware accepts tokens via `Authorization: Bearer <token>` header **or** `?token=<jwt>` query parameter (fallback for clients like libmpv that don't support custom HTTP headers on media streams).
- **Primary keys:** UUID TEXT via `lower(hex(randomblob(16)))` for all BiMusic tables; Lidarr IDs stay INTEGER
- **Logging:** Pino — structured JSON to stdout in production, pino-pretty (debug level) in dev/test. The process manager (PM2) is responsible for capturing/rotating stdout. There is no in-process file destination.
- **Lidarr client:** `src/services/lidarrClient.ts` — typed axios wrapper for all Lidarr API calls. Routes must call lidarrClient methods, never axios directly. Lidarr errors are mapped: 404 → 404 `NOT_FOUND`, 5xx → 502 `LIDARR_ERROR`, timeout → 504 `LIDARR_TIMEOUT`. Cover art methods return `AxiosResponse<Readable>` for pipe-through (no buffering). Lidarr types are in `src/types/lidarr.ts`.
- **Library service:** `src/services/libraryService.ts` — reshapes raw Lidarr responses into Flutter-facing types (`Artist`, `Album`, `Track` defined in `src/types/api.ts`), injects relative `imageUrl` (`/api/library/{artists|albums}/:id/image`) and `streamUrl` (`/api/stream/:id`) paths. The Flutter client prepends the user-configured backend URL via `resolveBackendUrl`. Image proxy methods fetch the Lidarr artist/album to determine the cover filename before streaming.
- **Track file resolver:** `src/services/trackFileResolver.ts` — resolves Lidarr track → `{ sourcePath, durationMs }` (path remapping + readability check), `isPassthrough` (MP3 check), `serveFile` (Range-capable HTTP serve with optional `contentType`), and the ffmpeg process registry (`registerFfmpegCommand` / `unregisterFfmpegCommand` / `killAllActiveTranscodes`). Imported by both `hlsService.ts` and `downloadService.ts`.
- **HLS service:** `src/services/hlsService.ts` — implements the HLS streaming logic: `computeTrackKey(sourcePath, mtime, size, bitrate)` → sha256 cache key; `buildPlaylist(durationMs, segmentCount, segmentSeconds, bitrate, token)` → m3u8 string (rebuilt per-request, never cached — token is embedded in every segment URI); `ensureSegment(...)` → absolute path to a ready 6-second MPEG-TS segment (transcoded on demand, concurrent callers deduplicated via `Map<segmentKey, Promise<string>>`); `initHlsCacheDir()` clears stale `.part` files at startup; `startHlsCacheCleanup()` prunes dirs older than 24 h hourly. Segments are cached at `HLS_CACHE_DIR/<trackKey>/segment<NNN>.ts`.
- **HLS endpoints:** `GET /api/stream/:trackId/playlist.m3u8?bitrate=128|320&token=<jwt>` returns the VOD playlist; `GET /api/stream/:trackId/segment/:index?bitrate=...&token=...` returns the MPEG-TS segment (`Content-Type: video/mp2t`). Both require auth via `?token=` query param (libmpv does not support custom request headers on media streams). Segment indices are zero-based three-digit zero-padded integers (`000`–`NNN`); indices ≥ segmentCount return 400.
- **Path remapping:** Lidarr may return absolute file paths under its own root folder (e.g. `/music/...` inside Docker). `resolveFilePath()` fetches Lidarr's root folder via `/api/v1/rootfolder` (cached), strips it from the track file path, and prepends `MUSIC_LIBRARY_PATH` from env. This lets the backend find files even when Lidarr and BiMusic see different mount points.
- **Playlist service:** `src/services/playlistService.ts` — CRUD for `playlists` + `playlist_tracks` tables. Ownership is always verified before mutations (returns 404 to avoid leaking existence). `addTracks()` shifts existing `position` values when `insertPosition` is provided; `removeTrack()` repacks positions after deletion; `reorderTracks()` reassigns positions in a `db.transaction()`. Duplicate track inserts (unique constraint on `(playlistId, lidarrTrackId)`) are silently skipped. **Playlist route:** `GET /api/playlists/:id` (in `src/routes/playlists.ts`) enriches the raw `{lidarrTrackId, position}` rows with full `Track` objects via `libraryService.getTrack()` using `Promise.allSettled` — tracks missing from Lidarr are silently dropped rather than failing the request. The response shape is `{ id, name, tracks: Track[] }` (ordered by position).
- **Request service:** `src/services/requestService.ts` — tracks music requests in the `requests` table. `createRequest(userId, type, lidarrId)` inserts a row and returns it immediately (explicit UUID). `listRequests(userId)` fetches all rows for the user and live-polls Lidarr for each with `status != 'available'`: artist requests check `GET /api/v1/artist/:id` → `statistics.trackFileCount > 0` → `available`; album requests check `GET /api/v1/album/:id` similarly. Queue is fetched once per call to detect `downloading` status. Both the queue fetch and per-item status checks are best-effort (errors are swallowed). `type` is `'artist'` or `'album'`; `status` progresses `pending` → `downloading` → `available`. **Artist request Lidarr defaults:** `POST /api/requests/artist` accepts optional `qualityProfileId`, `metadataProfileId`, `rootFolderPath`; when any are omitted the route auto-fetches the first available values from Lidarr (`/api/v1/qualityprofile`, `/api/v1/metadataprofile`, `/api/v1/rootfolder`) via `getLidarrDefaults()`. Flutter clients only need to send `foreignArtistId` and `artistName`.
- **Download service:** `src/services/downloadService.ts` — records download requests in the `offline_tracks` table and manages offline file transcoding. `requestDownload()` upserts (returns existing record if already queued for the same user/device/track). `processOnePendingDownload()` picks the oldest `pending` row (ordered by `requestedAt`), transcodes via ffmpeg to `OFFLINE_STORAGE_PATH/<userId>/<trackId>-<bitrate>.mp3`, and updates status to `ready` or `failed`. `startDownloadWorker()` schedules `processOnePendingDownload()` on a 10 s `setInterval` — called from `index.ts` at startup. `processOnePendingDownload` is exported for direct use in integration tests (bypasses the timer).
- **UUID generation pattern:** The schema uses `$defaultFn(() => randomUUID())` but Drizzle's `.run()` does not return the inserted row. When the generated ID or timestamp is needed immediately (e.g. to return in the response), generate it explicitly in JS and pass it into `.values({ id, createdAt, ... })` — do not round-trip with an extra SELECT.
- **Transcoding:** `fluent-ffmpeg` (`libmp3lame`, configurable bitrate 128/320 kbps). HLS segments live in `HLS_CACHE_DIR/<trackKey>/` (default `./data/hls`); offline download files live in `OFFLINE_STORAGE_PATH`. Partial files are deleted on ffmpeg error.
- **Error handler:** `src/middleware/errorHandler.ts` — logs `error`-level for 5xx, `warn`-level for 4xx. In `production`, all 5xx responses return a generic `"Internal server error"` message (stack traces and internal details are never sent to clients regardless of environment). Use `createError(statusCode, code, message)` to create typed errors; throw them from any route handler or service.
- **Shutdown:** SIGTERM/SIGINT triggers graceful shutdown — stops accepting connections, waits up to 5 s for in-flight requests, kills active ffmpeg processes, flushes pino's async log buffer, then `exit 0`. A 5 s timeout forces `exit 1` if requests don't drain.
- **Validation:** Zod schemas for env config and request validation
- **Express 5 route params typing:** `req.params['id']` is typed as `string | string[]` in Express 5. Use `req.params['id'] as string` (not `req.params['id']!`) when passing a route param to a function that expects `string`.

**Request flow:** `index.ts` → boots migrations + admin user + HLS cache dir + download worker → `app.ts` mounts routes → route handlers call services → `lidarrClient` (Lidarr API) or Drizzle ORM (SQLite)

**Route prefixes:** `/api/health`, `/api/auth`, `/api/library`, `/api/search`, `/api/stream`, `/api/downloads`, `/api/admin`, `/api/users`, `/api/playlists`, `/api/requests`

**Admin route** (`src/routes/admin.ts`): all routes require `authenticate` + `requireAdmin`. `GET /api/admin/logs` reads the file at `env.PM2_LOG_PATH` (the PM2 out-log for the backend process, e.g. `/etc/.pm2/logs/bimusic-backend-out.log`) and returns the last 200 non-empty lines as `{ lines: string[] }`. Returns 404 if `PM2_LOG_PATH` is unset (dev mode) or the file doesn't exist.

### Flutter Client

- **State management:** Riverpod (flutter_riverpod ^2.6, riverpod_annotation ^2.6, riverpod_generator ^2.6)
- **Audio:** just_audio ^0.9 + just_audio_media_kit ^2.1 (libmpv backend for Windows/Linux — `just_audio_windows` dropped due to WMF not supporting HTTP headers) + audio_service ^0.18 + audio_session ^0.1. `JustAudioMediaKit.ensureInitialized()` is called in `main()` before audio service init. Stream URLs pass the JWT as a `?token=` query parameter (not an `Authorization` header) because just_audio's header proxy doesn't work reliably with libmpv.
- **Routing:** go_router ^14.6 — `StatefulShellRoute.indexedStack` with 6 branches; shell builder delegates to `AdaptiveScaffold`
- **Offline storage:** `DownloadTask` records are persisted as JSON files at `<app_documents>/bimusic_downloads_<userId>.json`. Do not introduce a heavyweight ORM here — keep it file-based. Do not add Isar or similar ORM annotations to `DownloadTask`.
- **Background downloads:** flutter_background_service ^5.0 — initialized in `main()` for Android/iOS only (`!kIsWeb && (Platform.isAndroid || Platform.isIOS)`). The service acts as a process keepalive (foreground notification) so downloads continue when the app is backgrounded; actual download logic runs in the main Riverpod context via `DownloadNotifier`.
- **HTTP:** Dio ^5.7. `apiClientProvider` (`lib/services/api_client.dart`) provides a Dio instance with `AuthInterceptor` pre-attached. Use this for all authenticated API calls.
- **Auth:** `AuthService` (`lib/services/auth_service.dart`) handles token storage (`flutter_secure_storage`) and auth API calls using its own private Dio instance (never the intercepted one — avoids circular refresh loops). User info is decoded from the JWT payload locally, no extra `/api/auth/me` call. `AuthNotifier` (`lib/providers/auth_provider.dart`) manages `AuthState` (sealed class: `AuthStateLoading`, `AuthStateUnauthenticated`, `AuthStateAuthenticated`). `authNotifierProvider.notifier.initialized` is a `Future<void>` that resolves once the startup token check completes — await it in tests.
- **Routing:** `routerProvider` (`lib/router.dart`) is a Riverpod `Provider<GoRouter>`. The `_RouterNotifier` (ChangeNotifier) bridges `authNotifierProvider` to GoRouter's `refreshListenable`, triggering redirects on auth state changes.
- **Code gen:** freezed ^2.5 + json_serializable ^6.8 + riverpod_generator. Run `dart run build_runner build --delete-conflicting-outputs` after model changes. **Providers use manual Riverpod 2 style** (`NotifierProvider`, `Provider`, etc.) — not `@Riverpod` codegen. Only freezed models require build_runner.
- **Library models:** `lib/models/artist.dart`, `album.dart`, `track.dart`, `search_results.dart` — freezed + json_serializable, matching `src/types/api.ts` exactly. IDs are `int` (Lidarr integer IDs), not UUID strings.
- **Search/request models:** `lib/models/lidarr_search_results.dart` (`LidarrArtistResult`, `LidarrAlbumResult`, `LidarrSearchResults`) and `lib/models/music_request.dart` (`MusicRequest`) — **plain Dart classes with manual `fromJson`**, no freezed. Do not add freezed to these files.
- **Playlist models:** `lib/models/playlist.dart` — `PlaylistSummary` (`id` String UUID, `name`, `trackCount`, `createdAt`) and `PlaylistDetail` (`id`, `name`, `tracks: List<Track>`) — **plain Dart classes with manual `fromJson`**, no freezed. Playlist IDs are `String` (UUID), unlike library IDs which are `int` (Lidarr integer IDs).
- **MusicService:** `lib/services/music_service.dart` — all `/api/library/*` calls. Provided via `musicServiceProvider`. Never call the library endpoints directly from UI.
- **SearchService:** `lib/services/search_service.dart` — library search (`GET /api/search`), Lidarr lookup (`GET /api/requests/search`), request submission (`POST /api/requests/artist|album`), and request list (`GET /api/requests`). Provided via `searchServiceProvider`.
- **Library providers:** `lib/providers/library_provider.dart` — `libraryProvider` (`AsyncNotifierProvider<LibraryNotifier, List<Artist>>`) caches the artist list and exposes `refresh()`. Per-item lookups are `FutureProvider.family<T, int>`: `artistProvider`, `artistAlbumsProvider`, `albumProvider`, `albumTracksProvider`.
- **Search provider:** `lib/providers/search_provider.dart` — `searchProvider` (`StateNotifierProvider<SearchNotifier, SearchState>`). Library search is debounced 300 ms automatically on `setQuery()`; Lidarr search is manual (call `searchLidarr()`). Per-item request submission state is stored in `SearchState.requestStatuses` keyed `"artist:<id>"` or `"album:<id>"`.
- **Requests provider:** `lib/providers/requests_provider.dart` — `requestsProvider` (`AsyncNotifierProvider<RequestsNotifier, List<MusicRequest>>`). Loads on mount, exposes `refresh()`.
- **Playlist service:** `lib/services/playlist_service.dart` — all `/api/playlists/*` calls. Provided via `playlistServiceProvider`.
- **Playlist providers:** `lib/providers/playlist_provider.dart` — `playlistProvider` (`AsyncNotifierProvider<PlaylistNotifier, List<PlaylistSummary>>`) manages the playlist list and exposes `createPlaylist()`, `updatePlaylist()`, `deletePlaylist()`, `addTracks()`, `removeTrack()`, `reorderTracks()`, `refresh()`; mutation methods call `refresh()` then `ref.invalidate(playlistDetailProvider(id))`. `playlistDetailProvider` (`FutureProvider.family<PlaylistDetail, String>`) fetches a single playlist's full track list; invalidated by all mutation methods.
- **Download model:** `lib/models/download_task.dart` — `DownloadTask` is a **plain Dart class** (not freezed) with manual `copyWith`, `fromJson`, `toJson`. `DownloadStatus` enum: `pending | downloading | completed | failed`. The `copyWith` method cannot clear nullable fields back to `null` (standard limitation of manual copyWith without freezed).
- **Download service:** `lib/services/download_service.dart` — `DownloadService.downloadFile()` calls `GET /api/downloads/:id/file` and retries every 10 s (up to 60 times) when the backend returns **409** while the transcode is still in progress. `deviceIdProvider` (`FutureProvider<String>`) generates and persists a UUID v4 under `bimusic_device_id` in `FlutterSecureStorage`. UUID generation uses `dart:math` (no external package).
- **Download provider:** `lib/providers/download_provider.dart` — `downloadProvider` (`NotifierProvider<DownloadNotifier, DownloadState>`). Persists tasks as JSON to `<app_documents>/bimusic_downloads_<userId>.json`. Max 2 concurrent downloads; pauses on connectivity loss, resumes on restore. Key methods: `requestDownload(track, albumId:, artistId:, albumTitle:, artistName:)`, `requestAlbumDownload(tracks, ...)`, `cancelDownload(serverId)`, `removeDownload(serverId)`, `clearAllDownloads()` (cancels all transfers, deletes local files, removes backend records, clears state). `userDownloadsProvider` (`Provider<List<DownloadTask>>`) returns empty list on web. `storageUsageProvider` (`Provider<StorageUsage>`) sums `fileSizeBytes` of completed tasks. Downloading tasks reset to `pending` on app restart (tasks serialised as `downloading` are reset on load).
- **Image auth headers:** `CachedNetworkImage` requires `httpHeaders: {'Authorization': 'Bearer $token'}` to load images through the proxy endpoints. Read the token via `ref.watch(authServiceProvider).accessToken` in `ConsumerWidget`. Use `ColoredBox(color: colorScheme.surfaceContainerHighest)` as the placeholder — `surfaceVariant` is deprecated in Flutter 3.22+.
- **Audio handler:** `BiMusicAudioHandler` (`lib/services/audio_service.dart`) is a `BaseAudioHandler` wrapping `just_audio`. It is instantiated once in `main()` via `AudioService.init()` and injected via `audioHandlerProvider` (a throw-sentinel `Provider` — must be overridden in both `main()` and tests). Call `handler.playQueue(tracks, startIndex, token, bitrate, localFilePaths: {...}, ...)` to start playback. Pass `localFilePaths` (a `Map<int, String>` of `trackId → filePath`) to use `AudioSource.file()` for any downloaded tracks instead of the stream URL. `PlayerNotifier.play()` resolves this map automatically from `downloadProvider`. Never instantiate `BiMusicAudioHandler` directly. Stream URLs point to the HLS playlist: `$baseUrl/api/stream/${t.id}/playlist.m3u8?bitrate=$bitrate&token=$token`; libmpv/ExoPlayer/AVPlayer detect HLS from the `.m3u8` URL automatically.
- **Player state:** `playerNotifierProvider` (`lib/providers/player_provider.dart`) is a `NotifierProvider<PlayerNotifier, PlayerState>`. `PlayerState` is a plain immutable class (not freezed) with manual `copyWith`. Position and duration are intentionally excluded from `PlayerState` — watch `playerPositionProvider` and `playerDurationProvider` (both `StreamProvider`) separately in widgets that need the seek bar, to avoid per-tick rebuilds of the full state tree.
- **Connectivity/bitrate:** `connectivityProvider` (`StreamProvider<ConnectivityResult>`, `lib/providers/connectivity_provider.dart`) wraps `connectivity_plus` v6 (emits `List<ConnectivityResult>`, collapsed to single value). `bitrateProvider` (`Provider<int>`, `lib/providers/bitrate_provider.dart`) returns the effective bitrate (128 or 320) by combining `bitratePreferenceProvider` with current connectivity. `bitratePreferenceProvider` (`lib/providers/bitrate_preference_provider.dart`) stores a `BitratePreference` enum (`auto | alwaysLow | alwaysHigh`) persisted to `FlutterSecureStorage`. Read bitrate once at play time via `ref.read(bitrateProvider)`, not watch.
- **BehaviorSubject in Notifier.build():** When subscribing to `audio_service`'s `BehaviorSubject` streams inside `Notifier.build()`, use `.skip(1)` to skip the synchronous initial emission — setting `state` before `build()` returns throws in Riverpod 2.
- **Theme:** Material 3, `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`, light + dark, `ThemeMode.system`
- **API config:** `lib/config/api_config.dart` — timeout constants only. The runtime backend URL is stored in `FlutterSecureStorage` under `bimusic_backend_url` and exposed via `backendUrlProvider` (`lib/providers/backend_url_provider.dart`). On first launch (no stored URL) `BiMusicApp` renders `BackendSetupScreen` before the router. URL can be edited in Settings → About → Backend URL (edits force sign-out).

**Layout:** `AdaptiveScaffold` (`lib/ui/widgets/adaptive_scaffold.dart`) switches at 1024 px:
- `< 1024` → `MobileLayout` — 5-tab `NavigationBar` (Home/Library/Search/Playlists/Settings); Downloads tab omitted on mobile
- `≥ 1024` → `DesktopLayout` — 220 px fixed sidebar with all 6 nav items + 80 px bottom player bar

**Entry point:** `main.dart` is async — calls `WidgetsFlutterBinding.ensureInitialized()`, then `_initBackgroundService()` (Android/iOS only), then `AudioService.init<BiMusicAudioHandler>(builder: BiMusicAudioHandler.new, config: ...)` to start the audio background service, then `runApp(ProviderScope(overrides: [audioHandlerProvider.overrideWithValue(audioHandler)], child: BiMusicApp()))`. `BiMusicApp` is a `ConsumerWidget` in `lib/app.dart` that watches `routerProvider`.

### Testing

**`isAdmin` is stored as integer in SQLite** — Drizzle returns `isAdmin` as `0` or `1`, not `boolean`. Backend unit test assertions must use `toBe(0)` / `toBe(1)`; integration test assertions on `res.body.isAdmin` should use `toBeFalsy()` / `toBeTruthy()` since JSON preserves the integer value.

**Schema uses camelCase SQL column names** — Unlike the typical snake_case convention, the BiMusic schema stores all columns as camelCase directly in SQLite (e.g., `displayName TEXT`, `passwordHash TEXT`, `isAdmin INTEGER`, `createdAt TEXT`). Backend unit test DB mocks must use these exact column names in `CREATE TABLE` SQL — do not use snake_case.

**Backend unit tests: mock both `env.js` and `db/connection.js`** — `env.ts` calls `process.exit(1)` if required vars are missing. Unit tests that import any module touching `env.ts` must mock it with `vi.mock('../../config/env.js', () => ({ env: { ... } }))`. Tests that also need DB access must additionally mock `db/connection.js` with an in-memory SQLite instance that manually creates tables with the camelCase column names from `schema.ts`. See `src/services/__tests__/authService.test.ts` for the canonical pattern.

**Backend tests use Vitest** with two workspace projects:
- **Unit tests:** `src/**/__tests__/**/*.test.ts` — colocated with source. Mock env with `vi.mock('../../config/env.js', ...)`. Use `nock` to stub outbound HTTP (lidarrClient tests); use `vi.mock` for DB/logger.
- **Integration tests:** `tests/integration/**/*.test.ts` — use setup file (`tests/setup.ts`), run in forked processes, 15s timeout. Library integration tests use `nock` to stub Lidarr HTTP calls; call `nock.cleanAll()` in `afterEach`. Stream and download integration tests mock `fluent-ffmpeg` using `vi.hoisted` (to make the mock reference available before imports are resolved) + `vi.mock('fluent-ffmpeg', ...)`. Each test that triggers transcoding must use a unique fixture file path so the `sha256(path:bitrate)` temp key doesn't collide across tests. Download worker tests call `processOnePendingDownload()` directly; because the in-memory DB is shared within a test file, any pending records created by earlier tests must be drained first (stub them to 404 so the worker marks them failed) before the target record is processed.

**Flutter tests:** `test/**/*_test.dart`. Tests are organised into subdirectories by layer (e.g. `test/providers/`, `test/services/`, `test/ui/`). Use `mocktail` for mocks; register fallback values with `setUpAll(() => registerFallbackValue(...))` for any non-primitive types passed to `any()`. To override a `FutureProvider.family` for a specific argument in widget tests: `albumProvider(1).overrideWith((_) async => testAlbum)`. Always override `authServiceProvider` in widget tests that render image-bearing widgets (to avoid secure storage errors and supply a fake token). **Dart getter gotcha:** Dart does not allow property getters (`Type get name => ...`) inside a function body such as `main()`. Use regular helper functions (`Type name() => ...`) instead — e.g. `SearchNotifier n() => container.read(...)` rather than `SearchNotifier get n => ...`.

To test widgets that use audio playback, override all four providers: `audioHandlerProvider` (mock `BiMusicAudioHandler`), `playerNotifierProvider` (fake notifier — see pattern below), `playerPositionProvider`, and `playerDurationProvider`. The fake notifier pattern: `class _FakePlayerNotifier extends Notifier<PlayerState> implements PlayerNotifier { ... }` — extend `Notifier<PlayerState>` AND implement `PlayerNotifier`, override `build()` to return a fixed state, and stub all methods as no-ops. Use `playerNotifierProvider.overrideWith(() => _FakePlayerNotifier(state))`.

**`AsyncNotifierProvider` and `NotifierProvider` overrideWith type constraint:** The stub must implement the concrete notifier type — not just the base class. For `AsyncNotifierProvider<PlaylistNotifier, T>`: `class _Stub extends PlaylistNotifier { ... }`. For `NotifierProvider<AuthNotifier, AuthState>`: `class _Stub extends Notifier<AuthState> implements AuthNotifier { ... }` — because `AuthNotifier._initialized` is library-private you cannot subclass it directly; implementing the interface is required. The `overrideWith` factory parameter is typed as `ConcreteNotifier Function()`, so passing a plain `Notifier<T> Function()` is a compile error.

**`AuthNotifier` stub pattern:** `AuthNotifier._initialized` is a private `late Future<void>`. Extend `Notifier<AuthState>` and implement `AuthNotifier` instead of extending it. Provide `Future<void> get initialized async {}` in the stub. Example: `class _StubAuthNotifier extends Notifier<AuthState> implements AuthNotifier { @override Future<void> get initialized async {} @override AuthState build() => AuthStateAuthenticated(tokens); @override Future<void> login(...) async {} @override Future<void> logout() async {} }`

**`TrackTile` is a `ConsumerWidget`** — any test that renders `TrackTile` (directly or via a screen like `AlbumDetailScreen`) must have a `ProviderScope` ancestor. `TrackTile.build()` now reads `downloadProvider` on every render (for the offline indicator), so **all** tests rendering `TrackTile` must override `downloadProvider` — not just long-press tests. The widget only accesses `playlistProvider` inside the long-press context sheet, so `playlistServiceProvider` can be omitted for tests that don't trigger long-press. Stub pattern: `class _StubDownloadNotifier extends DownloadNotifier { @override DownloadState build() => DownloadState(tasks: [], isLoading: false, deviceId: 'test-dev'); }` — then `downloadProvider.overrideWith(() => _StubDownloadNotifier())`. Same override is required for `AlbumDetailScreen` tests (which render `TrackTile` and `_DownloadAlbumButton`). Playlist integration tests use `nock` (call `nock.disableNetConnect()` + `nock.enableNetConnect('127.0.0.1')` in `beforeAll`, `nock.cleanAll()` in `afterEach`) since `GET /api/playlists/:id` now calls Lidarr.

**`SettingsScreen` widget tests:** The screen contains two file-private `FutureProvider`s (`_backendHealthProvider`, `_adminLogsProvider`) that make real HTTP calls when `user.isAdmin == true`. These create pending timers that fail tests. Use a **non-admin user** in `SettingsScreen` widget tests to skip the Debug section. If admin functionality must be tested, override `apiClientProvider` with a mock Dio that returns immediately. Additionally, `_BitratePreferenceTile` watches `bitratePreferenceProvider` which reads `FlutterSecureStorage` on init — override it: `class _StubBitratePreferenceNotifier extends BitratePreferenceNotifier { @override BitratePreference build() => BitratePreference.auto; }`.

**`SearchNotifier` stub for `searchProvider`:** `searchProvider` is `StateNotifierProvider<SearchNotifier, SearchState>`, so the override factory must return a `SearchNotifier`. Stub: `class _StubSearchNotifier extends SearchNotifier { _StubSearchNotifier(super.searchService); }` — use `searchProvider.overrideWith((ref) => _StubSearchNotifier(mockSearchService))`.

**Connectivity provider in unit tests:** `connectivityProvider` uses a platform channel (EventChannel). Pure unit tests (non-widget) that indirectly instantiate providers watching connectivity must call `TestWidgetsFlutterBinding.ensureInitialized()` in `setUpAll` to avoid "Binding has not yet been initialized" errors.

**`Radio`/`RadioListTile` deprecated in Flutter 3.32+:** `groupValue` and `onChanged` on both widgets are deprecated — `flutter analyze --fatal-infos` will fail. Use `ListTile` with a leading `Icon(Icons.radio_button_checked)` / `Icon(Icons.radio_button_unchecked)` and `onTap` instead.

### CI Pipeline (`.github/workflows/ci.yml`)

Three stages on push/PR to main:
1. **Stage 1 (parallel):**
   - `backend-lint-unit` — npm ci → lint → format:check → build → unit tests with coverage (gate: ≥80% lines, ≥75% branches)
   - `flutter-lint-unit` — pub get → build_runner → analyze → flutter test with coverage (gate: ≥70% lines)
2. **Stage 2** (needs stage 1): `backend-integration` — installs ffmpeg → npm ci → integration tests (real SQLite + nock Lidarr)

Coverage artifacts uploaded: `backend-coverage/` and `flutter-coverage/`.

## Locked Architecture Decisions

These decisions are final and documented in `docs/architecture-decisions.md`. Do not re-litigate unless the user explicitly requests a design change.
