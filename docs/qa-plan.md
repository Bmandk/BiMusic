# BiMusic QA Plan

## Table of Contents

1. [Overall Test Strategy](#1-overall-test-strategy)
2. [Backend Test Plan](#2-backend-test-plan)
3. [Flutter Client Test Plan](#3-flutter-client-test-plan)
4. [End-to-End Scenarios](#4-end-to-end-scenarios)
5. [GitHub Actions CI Workflow](#5-github-actions-ci-workflow)
6. [Test Environment Setup](#6-test-environment-setup)
7. [Prioritized Test Scenario List](#7-prioritized-test-scenario-list)

---

## 1. Overall Test Strategy

### 1.1 Testing Pyramid

```
           /   E2E    \          ~10% of tests  |  Slow, full-stack confidence
          /-------------\
         /  Integration   \      ~30% of tests  |  Real DB, real ffmpeg, mocked Lidarr
        /-------------------\
       /     Unit Tests      \   ~60% of tests  |  Fast, isolated, all deps mocked
      /________________________\
```

**Unit tests** verify individual functions and classes in isolation. All I/O boundaries (database, HTTP, filesystem, ffmpeg subprocess) are mocked. These run in milliseconds and form the bulk of the suite.

**Integration tests** exercise real interactions: the backend boots with a real SQLite database, real ffmpeg transcoding against fixture audio files, and HTTP endpoints tested via Supertest. Only external services we do not control (Lidarr) are mocked with nock.

**End-to-end tests** validate complete user journeys: the Flutter client talks to a running backend instance over HTTP, with a mock Lidarr stub providing library data. These run on CI via headless Chrome (web target).

### 1.2 Coverage Targets

| Scope | Metric | Target | Enforcement |
|-------|--------|--------|-------------|
| Backend unit tests | Line coverage | **80%** | CI gate -- pipeline fails below threshold |
| Backend integration tests | Endpoint coverage | **100% of public API routes** | PR checklist |
| Flutter unit tests | Line coverage | **70%** | CI gate -- pipeline fails below threshold |
| Flutter widget tests | Screen coverage | **Every screen has at least 1 widget test** | PR checklist |
| E2E scenario pass rate | Scenario count | **All defined scenarios pass** | CI gate |
| Overall backend | Branch coverage | **75%** | CI warning (non-blocking initially) |

### 1.3 Key Principles

1. **Deterministic** -- no flaky tests. Mock time, use fixed seeds, no real network calls to external services.
2. **Independent** -- each test manages its own setup/teardown. No shared mutable state between tests.
3. **Fast feedback** -- unit tests complete in <30s. Full CI pipeline target: <10 minutes.
4. **Contract over implementation** -- test public APIs and observable behavior, not internal details.
5. **Lidarr is always mocked** -- we never hit a real Lidarr instance. Mocks are derived from the OpenAPI spec in `lidarr-openapi.json`.

---

## 2. Backend Test Plan (Node.js / TypeScript)

### 2.1 Tooling

| Tool | Purpose |
|------|---------|
| **Vitest** | Test runner (preferred over Jest for native ESM + TypeScript support, faster execution) |
| **Supertest** | HTTP-level integration tests against the Express app |
| **nock** | Intercepts outgoing HTTP to mock Lidarr API responses |
| **better-sqlite3** | Real SQLite used in integration tests (same driver as production) |
| **c8** | Native V8 coverage (built into Vitest) |
| **@faker-js/faker** | Generate realistic test data for users, playlists, tracks |

Configuration: `vitest.config.ts` at backend root with separate projects for unit vs integration:

```ts
// vitest.config.ts
export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: 'unit',
          include: ['src/**/__tests__/**/*.test.ts'],
          environment: 'node',
        },
      },
      {
        test: {
          name: 'integration',
          include: ['test/integration/**/*.test.ts'],
          environment: 'node',
          setupFiles: ['test/setup.ts'],
          pool: 'forks',       // isolate integration tests
          testTimeout: 15000,  // ffmpeg can be slow
        },
      },
    ],
  },
});
```

### 2.2 Unit Tests

All external boundaries are mocked. Tests are co-located with source in `__tests__/` directories.

| Module | Test Cases |
|--------|-----------|
| **Auth service** | Generate access token (signed with `JWT_ACCESS_SECRET`) with correct claims and expiry; generate opaque refresh token (random hex); verify valid access token returns decoded payload; reject expired token; reject token signed with wrong secret; reject malformed token string; refresh token rotation invalidates old token; HMAC-SHA256 hash of refresh token (keyed with `JWT_REFRESH_SECRET`) stored in DB, never raw; get current user profile from token payload |
| **User service** | Create user hashes password with bcrypt; reject duplicate username; validate correct password; reject incorrect password; list users (admin only logic); admin bootstrap creates initial admin user when no users exist; admin bootstrap skips when users already exist |
| **Transcoding service** | Build ffmpeg command for 320k MP3 output; build ffmpeg command for 128k MP3 output; handle FLAC source input; handle MP3 source input (passthrough when bitrate matches); return correct content-type header; throw on unsupported source format; generate correct temp file path from hash of source path + bitrate; detect existing temp file and skip re-transcode |
| **Lidarr client** | Map album list request to correct Lidarr URL and API key header; parse album response into internal model; map artist lookup to correct endpoint; map search query; propagate Lidarr 404 as "not found"; propagate Lidarr 500 as service unavailable; handle timeout |
| **Playlist service** | Create playlist for user; add track to playlist; remove track from playlist; reorder tracks; delete playlist; reject modification by non-owner; list playlists for user (returns only own playlists) |
| **Download service** | Resolve track file path from DB; validate track exists; return 320k bitrate for download (always high quality for offline) |
| **Logging** | Outputs structured JSON via pino; includes timestamp and level; respects LOG_LEVEL filter; pino/file transport writes to disk; log rotation handled by OS-level logrotate (not in-process) |
| **Middleware: auth guard** | Pass request with valid Bearer token; reject request without Authorization header; reject request with expired token; attach user to request context |
| **Middleware: bitrate negotiation** | Parse `X-Connection-Type` header; default to 320k for wifi/ethernet/5g; default to 128k for cellular/unknown |

### 2.3 Integration Tests

Integration tests use a **real SQLite database** (file-based, reset between suites via `beforeEach` teardown) and **real ffmpeg** execution against fixture audio files. Lidarr HTTP calls remain mocked with nock.

| Endpoint | Test Cases |
|----------|-----------|
| **GET /api/health** | Returns 200 with `{ status: 'ok', version }` when server is running; no auth required; verifies DB connectivity |
| **POST /api/auth/login** | Valid credentials return 200 with `{ accessToken, refreshToken, user }`; invalid password returns 401; unknown user returns 401; missing fields returns 400 |
| **POST /api/auth/refresh** | Valid refresh token returns new access+refresh token pair; expired refresh token returns 401; reused (rotated-out) refresh token returns 401 and invalidates token family |
| **POST /api/auth/logout** | Invalidates refresh token; subsequent refresh attempt fails |
| **GET /api/auth/me** | Returns current user profile `{ id, username, isAdmin }` from valid token; returns 401 without token; returns 401 with expired token |
| **Admin bootstrap** | On first startup with empty users table, admin user created from env vars (`ADMIN_USERNAME`, `ADMIN_PASSWORD`); on subsequent startups with existing users, no duplicate admin created; bootstrap admin has `isAdmin: true` |
| **GET /api/users** (admin) | Returns user list; non-admin gets 403 |
| **POST /api/users** (admin) | Creates user; duplicate username returns 409 |
| **PATCH /api/users/:id** (admin) | Updates user; non-admin gets 403 |
| **DELETE /api/users/:id** (admin) | Deletes user and cascades (tokens, playlists, downloads); non-admin gets 403 |
| **GET /api/stream/:trackId** | Returns audio/mpeg stream; ffmpeg transcodes FLAC fixture to MP3 via temp file then serves with Range support; Content-Type is audio/mpeg; `Accept-Ranges: bytes`; returns 404 for nonexistent track; returns 401 without token |
| **GET /api/stream/:trackId?bitrate=128** | Returns lower bitrate stream; validate smaller response size than 320k |
| **Streaming: passthrough seek** | Source is MP3 at/below requested bitrate: served directly with standard Range headers; `Range: bytes=1000-` returns 206 Partial Content with correct `Content-Range` header and valid audio data |
| **Streaming: transcoded seek** | Source requires transcoding (e.g., FLAC): first request transcodes to temp file `/tmp/bimusic/<hash>.mp3`, then serves with Range headers; `Range: bytes=1000-` returns 206 Partial Content; subsequent request for same track+bitrate reuses cached temp file (no re-transcode) |
| **Streaming: temp file cleanup** | Temp files older than 24 hours are cleaned up; temp directory cleared on server startup |
| **GET /api/library/artists** | Proxies to Lidarr, returns shaped artist list with image URLs |
| **GET /api/library/artists/:id** | Returns single artist with album list |
| **GET /api/library/artists/:id/albums** | Returns albums for a specific artist |
| **GET /api/library/albums/:id** | Returns single album with track list |
| **GET /api/library/albums/:id/tracks** | Returns tracks for album |
| **GET /api/library/tracks/:id** | Returns track detail with file info |
| **GET /api/library/search?term=...** | Proxies to Lidarr search; returns unified results (artists + albums) |
| **GET /api/library/artists/:id/image** | Proxies artist cover art from Lidarr; streams response |
| **GET /api/library/albums/:id/image** | Proxies album cover art from Lidarr; streams response |
| **GET /api/requests/search?term=...** | Searches Lidarr for new artists/albums to request (lookup endpoints) |
| **POST /api/requests/artist** | Adds artist to Lidarr and triggers search; returns 202 |
| **POST /api/requests/album** | Adds/monitors album in Lidarr and triggers search; returns 202 |
| **GET /api/requests** | Returns list of pending requests for authenticated user with status (`pending`, `available`); each entry includes artist/album name, request timestamp, and current status |
| **Pending requests lifecycle** | POST /api/requests/artist stores request with status `pending`; GET /api/requests returns it in list; when mock Lidarr returns `trackFileCount > 0` for the artist, status becomes `available`; validates status transition logic |
| **GET /api/playlists** | Returns playlists for authenticated user only |
| **POST /api/playlists** | Creates playlist; returns 201 with playlist object |
| **GET /api/playlists/:id** | Returns playlist with tracks; returns 404 if not owner |
| **PATCH /api/playlists/:id** | Updates playlist name; returns 403 if not owner |
| **DELETE /api/playlists/:id** | Deletes playlist; returns 403 if not owner |
| **POST /api/playlists/:id/tracks** | Adds tracks to playlist at optional position |
| **DELETE /api/playlists/:id/tracks/:trackId** | Removes track from playlist |
| **PATCH /api/playlists/:id/tracks/reorder** | Reorders tracks in playlist |
| **GET /api/downloads** | Returns offline download list for user+device (`?deviceId=`); without deviceId returns all downloads for user |
| **POST /api/downloads** | Requests track for offline `{ trackId, deviceId, bitrate }`; returns queued status; deviceId is required |
| **DELETE /api/downloads/:id** | Removes offline download record |
| **GET /api/downloads/:id/file** | Returns transcoded file for offline storage at 320k; Content-Disposition header set for download |
| **Downloads: device isolation** | User1 POSTs download with `deviceId: "device-A"`; user1 POSTs same track with `deviceId: "device-B"`; GET /api/downloads?deviceId=device-A returns only device-A record; GET /api/downloads?deviceId=device-B returns only device-B record; both are separate download entries |

### 2.4 API Contract Tests

Validate that our Lidarr proxy correctly handles responses matching the Lidarr OpenAPI spec:

- Parse `lidarr-openapi.json` at test time to extract response schemas for key endpoints.
- Snapshot test: record transformed output for a known Lidarr response fixture; fail if transformation changes unexpectedly.
- Key Lidarr endpoints to validate: `/api/v1/album`, `/api/v1/album/lookup`, `/api/v1/artist`, `/api/v1/artist/lookup`, `/api/v1/track`, `/api/v1/search`, `/api/v1/command`.

### 2.5 Backend npm Scripts

```json
{
  "scripts": {
    "test": "vitest run",
    "test:unit": "vitest run --project unit",
    "test:integration": "vitest run --project integration",
    "test:watch": "vitest --project unit",
    "test:coverage": "vitest run --coverage",
    "lint": "eslint src/ test/ --ext .ts",
    "lint:fix": "eslint src/ test/ --ext .ts --fix",
    "format:check": "prettier --check 'src/**/*.ts' 'test/**/*.ts'"
  }
}
```

---

## 3. Flutter Client Test Plan

### 3.1 Tooling

| Tool | Purpose |
|------|---------|
| **flutter_test** | Built-in unit and widget test framework |
| **mocktail** | Mocking (preferred over mockito -- no codegen needed) |
| **bloc_test** | State management testing (if using BLoC/Cubit) |
| **integration_test** | On-device / browser integration test package |
| **http_mock_adapter** | Mock Dio HTTP client responses |
| **fake_async** | Control time in tests (token expiry, debounce) |

### 3.2 Unit Tests

Target: **>70% line coverage** on non-UI code.

| Module | Test Cases |
|--------|-----------|
| **AuthService** | `login()` stores tokens on success; `login()` throws on 401; `logout()` clears stored tokens; `refreshToken()` obtains new access token; `refreshToken()` clears session on 401; auto-refresh triggers before expiry; `isLoggedIn` reflects token state |
| **ApiClient** | Attaches Authorization header to requests; retries with refreshed token on 401; throws typed exceptions for 4xx/5xx; parses JSON responses into models; handles network timeout |
| **AudioPlayerService** | `play(track)` starts playback; `pause()` pauses; `resume()` resumes; `skip()` advances queue; `previous()` goes back; queue wraps around or stops; emits position/duration streams; selects 320k on WiFi/5G; selects 128k on cellular |
| **DownloadManager** | Enqueues track for download; tracks download progress; resumes interrupted download; removes downloaded file; calculates total storage used; concurrent download limit respected |
| **PlaylistRepository** | Fetches playlists from API; creates playlist; updates playlist; deletes playlist; caches playlists locally |
| **SearchService** | Debounces input (300ms); sends query to API; maps response to SearchResult model; returns empty list for empty query |
| **ConnectivityMonitor** | Detects WiFi; detects cellular; detects offline; emits stream of connectivity changes |
| **StorageTracker** | Sums file sizes in offline directory; formats bytes to human-readable string |
| **Models** | `Album.fromJson()` / `toJson()` round-trips; `Artist.fromJson()`; `Track.fromJson()`; `Playlist.fromJson()` handles empty track list |

### 3.3 Widget Tests

Target: **every screen has at least one widget test**.

| Screen / Widget | Test Cases |
|----------------|-----------|
| **LoginScreen** | Renders username and password fields; shows CircularProgressIndicator during login; shows error SnackBar on failure; navigates to HomeScreen on success; login button disabled when fields empty |
| **HomeScreen** | Displays recent albums section; displays playlists section; pull-to-refresh triggers reload; navigation to album/playlist/search works |
| **AlbumScreen** | Displays album art, title, artist; lists tracks with duration; tapping track calls play; "Download" button visible; shows offline badge when downloaded |
| **ArtistScreen** | Displays artist name and image; lists albums; tapping album navigates to AlbumScreen |
| **NowPlayingScreen** | Shows track title, artist, album art; play/pause button toggles icon; seek bar reflects position; skip/previous buttons work; shows queue |
| **PlaylistScreen** | Lists tracks; long-press enables reorder; swipe to remove track; edit name; delete playlist with confirmation dialog |
| **SearchScreen** | Text field has autofocus; typing triggers debounced search; displays artist and album results in sections; "No results" state; tapping result navigates |
| **SettingsScreen** | Displays current user info; shows storage usage with progress bar; logout button triggers confirmation and navigates to login |
| **MiniPlayer** | Appears at bottom when track is playing; shows track info; tap expands to NowPlayingScreen; play/pause button |
| **OfflineBadge** | Shows download icon on offline-available items; hidden when not downloaded |
| **Responsive layout** | Mobile (width < 600): bottom navigation bar; Tablet/Desktop (width >= 600): side navigation rail/drawer |

### 3.4 Flutter Integration Tests

Run on a real device, emulator, or headless Chrome. Backend is a real running instance.

| Flow | Steps | Assertions |
|------|-------|------------|
| **Login** | Launch -> enter valid credentials -> tap Login | HomeScreen visible; greeting shows username |
| **Failed login** | Launch -> enter bad credentials -> tap Login | Error message displayed; stays on LoginScreen |
| **Browse album** | Login -> tap album in recent -> view tracks | AlbumScreen shows correct track count |
| **Play track** | Login -> tap album -> tap first track | NowPlayingScreen shows track; audio state is playing |
| **Search** | Login -> tap search -> type query -> wait | Results appear; tapping result navigates to detail |
| **Playlist CRUD** | Login -> create playlist -> add track from album -> view playlist -> remove track -> delete playlist | Each step reflects correct state |
| **Offline** | Login -> long-press album -> "Make available offline" -> wait for download -> verify badge | Badge appears; storage screen shows usage |

---

## 4. End-to-End Scenarios

Full-stack tests: Flutter client communicates with a live backend, which uses a mock Lidarr stub.

### 4.1 Environment

- Backend started as a Docker container or local process.
- Mock Lidarr: a lightweight Express stub that serves canned responses from `lidarr-openapi.json` schemas.
- Fixture library: 5 short audio files (1-2 seconds each, mix of FLAC and MP3) pre-seeded in the music directory.
- Pre-seeded users: `testuser1` / `password1`, `testuser2` / `password2`, `admin` / `adminpass`.

### 4.2 Scenario Definitions

| ID | Scenario | Priority | Steps | Expected Result |
|----|----------|----------|-------|-----------------|
| E01 | **Health check** | P0 | GET /api/health before any auth | 200 `{ status: 'ok', version }`; confirms backend and DB are reachable; no auth required |
| E02 | **Admin bootstrap** | P0 | Start backend with empty DB and ADMIN_USERNAME/ADMIN_PASSWORD env vars; attempt login with admin credentials | Login succeeds; user has `isAdmin: true`; subsequent restart does not create duplicate admin |
| E03 | **Auth: login and browse** | P0 | Login as testuser1; GET /api/auth/me; GET /api/library/artists; GET /api/library/albums | 200 responses; /auth/me returns user profile; artists and albums populated from mock Lidarr |
| E04 | **Auth: invalid credentials** | P0 | Attempt login with wrong password | 401; no tokens issued |
| E05 | **Auth: token refresh** | P0 | Login; wait for access token to expire (short-lived in test env: 5s); make authenticated request | Client obtains new access token via refresh; request succeeds transparently |
| E06 | **Auth: refresh token reuse detection** | P1 | Login; use refresh token; replay same refresh token | Second refresh returns 401; all tokens for user invalidated |
| E07 | **Auth: GET /auth/me** | P0 | Login; GET /api/auth/me with valid token; GET /api/auth/me with expired token | First returns `{ id, username, isAdmin }`; second returns 401 |
| E08 | **Streaming: play track** | P0 | Login; GET /api/stream/:trackId | 200; Content-Type audio/mpeg; response body is valid audio |
| E09 | **Streaming: bitrate 320k** | P0 | Stream with `?bitrate=320` | Response transcoded at 320kbps |
| E10 | **Streaming: bitrate 128k** | P1 | Stream with `?bitrate=128` | Response transcoded at 128kbps; smaller payload than 320k |
| E11 | **Streaming: seek on transcoded content** | P1 | Stream track that requires transcoding (FLAC source); send `Range: bytes=1000-` header | First request triggers temp-file transcoding; response is 206 Partial Content with `Content-Range` header and `Accept-Ranges: bytes`; valid audio data in response body |
| E11a | **Streaming: seek on passthrough** | P1 | Stream track that is already MP3 at requested bitrate; send `Range: bytes=0-999` | Response is 206 Partial Content; `Content-Range: bytes 0-999/<total>`; served directly from source file without transcoding |
| E12 | **Streaming: missing track** | P1 | Request stream for nonexistent track ID | 404 with standard error format |
| E13 | **Library: browse artists and albums** | P0 | GET /api/library/artists; GET /api/library/artists/:id; GET /api/library/artists/:id/albums; GET /api/library/albums/:id; GET /api/library/albums/:id/tracks | All return shaped responses from mock Lidarr with image URLs |
| E14 | **Library: search** | P0 | GET /api/library/search?term=test | Results returned from mock Lidarr search endpoint |
| E15 | **Library: cover art proxy** | P1 | GET /api/library/artists/:id/image; GET /api/library/albums/:id/image | Both stream image data from mock Lidarr |
| E16 | **Requests: search and request artist** | P1 | GET /api/requests/search?term=new-artist; POST /api/requests/artist with result | Search returns Lidarr lookup results; POST returns 202; mock Lidarr /api/v1/command receives ArtistSearch |
| E17 | **Requests: request album** | P1 | POST /api/requests/album with album payload | 202; mock Lidarr receives monitor PUT and command POST |
| E18 | **Requests: pending status polling** | P1 | POST /api/requests/artist; GET /api/requests shows entry with status `pending`; send `X-Force-Available: true` header to mock Lidarr to simulate `trackFileCount > 0`; GET /api/requests now shows status `available`; GET /api/library/artists confirms new artist in library | Validates the full pending request lifecycle: create, poll status, status transitions from pending to available |
| E19 | **Playlist: full lifecycle** | P0 | Login; POST /api/playlists; POST /api/playlists/:id/tracks (2 tracks); PATCH /api/playlists/:id/tracks/reorder; DELETE /api/playlists/:id/tracks/:trackId; PATCH /api/playlists/:id (rename); DELETE /api/playlists/:id | Each mutation reflected in subsequent GET /api/playlists/:id |
| E20 | **Playlist: user isolation** | P0 | Login as user1, create playlist; login as user2, GET /api/playlists | User2 does not see user1's playlist; user2 GET /api/playlists/:id for user1's playlist returns 404 |
| E21 | **Offline: request and download** | P1 | POST /api/downloads `{ trackId, deviceId: "test-device-1", bitrate: 320 }`; GET /api/downloads?deviceId=test-device-1 to check status; GET /api/downloads/:id/file | File returned at 320k; Content-Disposition set; deviceId included in download record |
| E22 | **Offline: list and delete** | P2 | POST download; GET /api/downloads?deviceId=test-device-1; DELETE /api/downloads/:id; GET /api/downloads?deviceId=test-device-1 | Download removed from list |
| E22a | **Offline: device isolation** | P2 | User1 POST /api/downloads with `deviceId: "phone"`; user1 POST same track with `deviceId: "tablet"`; GET /api/downloads?deviceId=phone returns only phone record; GET /api/downloads?deviceId=tablet returns only tablet record | Separate download entries per device; device-scoped listing works correctly |
| E23 | **Multi-user: concurrent streams** | P2 | User1 and user2 both stream simultaneously | Both receive valid audio streams; no interference |
| E24 | **Resilience: Lidarr down** | P1 | Stop mock Lidarr; GET /api/library/search | Backend returns 502/503; error response uses standard error format |
| E25 | **Resilience: backend 500** | P2 | Force backend error; client handles gracefully | Client displays error, does not crash |

---

## 5. GitHub Actions CI Workflow

### 5.1 Workflow File: `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  # ── Stage 1: Lint & Unit (parallel) ──────────────────────────
  backend-lint-unit:
    name: Backend Lint & Unit Tests
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: backend/package-lock.json
      - run: npm ci
      - run: npm run lint
      - run: npm run format:check
      - run: npm run test:unit -- --coverage
      - name: Check coverage threshold
        run: |
          npx c8 check-coverage --lines 80 --branches 75
      - uses: actions/upload-artifact@v4
        with:
          name: backend-coverage
          path: backend/coverage/

  flutter-lint-unit:
    name: Flutter Lint & Unit Tests
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: client
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage
      - name: Check coverage threshold
        run: |
          # Using lcov to check coverage
          sudo apt-get install -y lcov
          lcov --summary coverage/lcov.info | grep -E 'lines' | awk '{if ($2+0 < 70) exit 1}'
      - uses: actions/upload-artifact@v4
        with:
          name: flutter-coverage
          path: client/coverage/

  # ── Stage 2: Integration (depends on stage 1) ───────────────
  backend-integration:
    name: Backend Integration Tests
    needs: [backend-lint-unit]
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: backend/package-lock.json
      - name: Install ffmpeg
        run: sudo apt-get install -y ffmpeg
      - run: npm ci
      - run: npm run test:integration
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: integration-results
          path: backend/test-results/

  # ── Stage 3: E2E (depends on stages 1 & 2) ──────────────────
  e2e-tests:
    name: End-to-End Tests
    needs: [backend-integration, flutter-lint-unit]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: backend/package-lock.json
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - name: Install ffmpeg
        run: sudo apt-get install -y ffmpeg
      - name: Start mock Lidarr
        run: |
          cd backend && npm ci
          node test/mocks/lidarr-server.js &
          echo "Mock Lidarr started on :8686"
      - name: Start backend
        run: |
          cd backend && npm run start:test &
          sleep 3
          curl -f http://localhost:3000/api/health || exit 1
        env:
          NODE_ENV: test
          PORT: 3000
          JWT_ACCESS_SECRET: test-access-secret-do-not-use-in-prod
          JWT_REFRESH_SECRET: test-refresh-secret-do-not-use-in-prod
          JWT_ACCESS_EXPIRY: 5s
          JWT_REFRESH_EXPIRY: 1h
          LIDARR_URL: http://localhost:8686
          LIDARR_API_KEY: test-api-key
          MUSIC_LIBRARY_PATH: ./test/fixtures/audio
          OFFLINE_STORAGE_PATH: ./test/fixtures/offline
          DB_PATH: ./test/fixtures/e2e-test.db
          LOG_PATH: ./logs
          ADMIN_USERNAME: admin
          ADMIN_PASSWORD: adminpass123
      - name: Seed test data
        run: cd backend && node test/fixtures/seed-e2e.js
      - name: Run Flutter E2E (Chrome)
        run: |
          cd client && flutter pub get
          flutter test integration_test/ -d chrome --headless
        env:
          API_URL: http://localhost:3000
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: e2e-results
          path: |
            client/integration_test/screenshots/
            backend/logs/

  # ── Stage 4: Build matrix (depends on all tests) ────────────
  build:
    name: Build ${{ matrix.target }}
    needs: [e2e-tests]
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        include:
          - target: apk
            os: ubuntu-latest
            build-cmd: flutter build apk --release
          - target: web
            os: ubuntu-latest
            build-cmd: flutter build web --release
          - target: linux
            os: ubuntu-latest
            build-cmd: flutter build linux --release
          - target: windows
            os: windows-latest
            build-cmd: flutter build windows --release
          - target: macos
            os: macos-latest
            build-cmd: flutter build macos --release
    defaults:
      run:
        working-directory: client
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - name: Install Linux build deps
        if: matrix.target == 'linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
      - name: Setup Java (Android)
        if: matrix.target == 'apk'
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - run: ${{ matrix.build-cmd }}
      - uses: actions/upload-artifact@v4
        with:
          name: build-${{ matrix.target }}
          path: |
            client/build/app/outputs/flutter-apk/*.apk
            client/build/web/
            client/build/linux/x64/release/bundle/
            client/build/windows/x64/runner/Release/
            client/build/macos/Build/Products/Release/

  # ── Coverage comment on PRs ─────────────────────────────────
  coverage-report:
    name: Coverage Report
    needs: [backend-lint-unit, flutter-lint-unit]
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: backend-coverage
          path: backend-coverage
      - uses: actions/download-artifact@v4
        with:
          name: flutter-coverage
          path: flutter-coverage
      - name: Post coverage summary
        uses: marocchino/sticky-pull-request-comment@v2
        with:
          header: coverage
          message: |
            ## Coverage Report
            **Backend**: See `backend-coverage` artifact for detailed lcov report.
            **Flutter**: See `flutter-coverage` artifact for detailed lcov report.
```

### 5.2 Pipeline Diagram

```
PR opened / push to main
 |
 +---> backend-lint-unit --------+
 |                               |
 +---> flutter-lint-unit ---+    +---> backend-integration ---+
                            |                                 |
                            +---------------------------------+---> e2e-tests ---> build (matrix: apk, web, linux, windows, macos)
                            |
                            +---> coverage-report (PR only)
```

### 5.3 Required Status Checks (branch protection on `main`)

- `backend-lint-unit`
- `flutter-lint-unit`
- `backend-integration`
- `e2e-tests`

All must pass before PR merge is allowed.

### 5.4 Caching Strategy

| Cache | Key | Saves |
|-------|-----|-------|
| npm | `backend/package-lock.json` hash | ~30s install time |
| Flutter SDK | Flutter channel + version | ~45s setup time |
| Pub cache | `client/pubspec.lock` hash | ~15s pub get time |
| Gradle | `client/android/build.gradle` hash | ~60s Android build time |

### 5.5 Concurrency

- `concurrency.group: ci-${{ github.ref }}` with `cancel-in-progress: true` ensures that pushing a new commit to a PR branch cancels the previous run, saving CI minutes.

---

## 6. Test Environment Setup

### 6.1 Local Development Commands

```bash
# Backend
cd backend/
npm install
npm run test:unit          # Unit tests only (~5s)
npm run test:integration   # Integration tests with real DB + ffmpeg (~20s)
npm run test               # All tests
npm run test:coverage      # Coverage report at backend/coverage/index.html

# Flutter
cd client/
flutter pub get
flutter test               # Unit + widget tests (~15s)
flutter test integration_test/  # Needs Chrome or emulator
```

### 6.2 Test Fixtures

| Fixture | Path | Description |
|---------|------|-------------|
| Audio: silence.flac | `backend/test/fixtures/audio/silence.flac` | 2-second silent FLAC, used for transcoding tests |
| Audio: silence.mp3 | `backend/test/fixtures/audio/silence.mp3` | 2-second silent MP3 at 320kbps |
| Audio: short-song.flac | `backend/test/fixtures/audio/short-song.flac` | 2-second tone FLAC with metadata (artist, album, title) |
| Lidarr: albums.json | `backend/test/fixtures/lidarr/albums.json` | Canned response for GET /api/v1/album |
| Lidarr: artists.json | `backend/test/fixtures/lidarr/artists.json` | Canned response for GET /api/v1/artist |
| Lidarr: search.json | `backend/test/fixtures/lidarr/search.json` | Canned response for album/artist lookup |
| Lidarr: tracks.json | `backend/test/fixtures/lidarr/tracks.json` | Canned response for GET /api/v1/track |
| Lidarr: artist-1.json | `backend/test/fixtures/lidarr/artist-1.json` | Canned response for GET /api/v1/artist/1 (used by pending requests tests) |
| Lidarr: album-1.json | `backend/test/fixtures/lidarr/album-1.json` | Canned response for GET /api/v1/album/1 (used by pending requests tests) |
| DB seed: seed.sql | `backend/test/fixtures/db/seed.sql` | Creates test users, playlists, track metadata |
| E2E seed script | `backend/test/fixtures/seed-e2e.js` | Programmatic seed for E2E test database |

### 6.3 Mock Lidarr Server

A lightweight Express app (`backend/test/mocks/lidarr-server.ts`) that:

- Serves canned JSON responses from the fixture files.
- Validates that requests include the `X-Api-Key` header.
- Returns appropriate errors (404 for unknown routes, 500 on demand via `X-Force-Error` header for resilience testing).
- Supports individual resource endpoints needed for pending request status checks:
  - `GET /api/v1/artist/:id` -- returns single artist resource; supports `X-Force-Available: true` header to simulate the artist having `trackFileCount > 0` (for pending requests lifecycle test).
  - `GET /api/v1/album/:id` -- returns single album resource; supports `X-Force-Available: true` header to simulate the album having downloaded tracks.
- Supports `POST /api/v1/command` -- records received commands (e.g., `ArtistSearch`) for assertion in tests.
- Logs all requests for debugging.
- Used in both local E2E testing and CI.

### 6.4 Test Environment Variables

```env
NODE_ENV=test
PORT=3001
JWT_ACCESS_SECRET=test-access-secret-do-not-use-in-prod
JWT_REFRESH_SECRET=test-refresh-secret-do-not-use-in-prod
JWT_ACCESS_EXPIRY=15m          # shortened to 5s in E2E for token refresh testing
JWT_REFRESH_EXPIRY=7d
LIDARR_URL=http://localhost:8686
LIDARR_API_KEY=test-api-key
MUSIC_LIBRARY_PATH=./test/fixtures/audio
OFFLINE_STORAGE_PATH=./test/fixtures/offline
DB_PATH=:memory:               # in-memory for unit/integration; file for E2E
LOG_LEVEL=error                # suppress noise in tests
LOG_PATH=./test/logs
ADMIN_USERNAME=admin           # used by bootstrap test
ADMIN_PASSWORD=adminpass123    # used by bootstrap test
```

### 6.5 Test Users (Pre-seeded)

| Username | Password | Role | Purpose |
|----------|----------|------|---------|
| `testuser1` | `password1` | user | Primary test user |
| `testuser2` | `password2` | user | Multi-user isolation tests |
| `admin` | `adminpass` | admin | Admin endpoint tests |

---

## 7. Prioritized Test Scenario List

Scenarios ordered by priority. **P0** = must pass before any release. **P1** = should pass; blocking for feature completeness. **P2** = nice to have; non-blocking initially.

### P0 -- Critical Path (implement first)

| # | Layer | Scenario | Rationale |
|---|-------|----------|-----------|
| 1 | Backend Integration | GET /health returns 200 | CI smoke test; confirms backend is alive |
| 2 | Backend Unit | Admin bootstrap creates admin on empty DB | First-run setup must work |
| 3 | Backend Unit | JWT generation and verification | Auth is the gateway to everything |
| 4 | Backend Unit | Password hashing and validation | Security-critical |
| 5 | Backend Integration | POST /api/auth/login (valid + invalid) | Cannot use app without login |
| 6 | Backend Integration | POST /api/auth/refresh | Seamless session continuity |
| 7 | Backend Integration | GET /api/auth/me | Client needs to verify identity on startup |
| 8 | Backend Integration | GET /api/stream/:trackId | Core feature: music playback |
| 9 | Backend Unit | ffmpeg command construction (320k, 128k) | Transcoding correctness |
| 10 | Backend Integration | GET /api/library/artists, /albums (Lidarr proxy) | Browse library |
| 11 | Backend Integration | GET /api/library/search (Lidarr proxy) | Find music |
| 12 | Backend Integration | Playlist CRUD full lifecycle (all 7 endpoints) | Core feature |
| 13 | Backend Integration | Playlist user isolation | Security: users must not see others' playlists |
| 14 | Flutter Unit | AuthService (login, token storage, refresh, getMe) | Client auth foundation |
| 15 | Flutter Unit | ApiClient (header injection, error handling) | All API calls depend on this |
| 16 | Flutter Widget | LoginScreen | First screen users see |
| 17 | Flutter Widget | HomeScreen (albums, playlists) | Main navigation hub |
| 18 | E2E | Health check + admin bootstrap | Validates first-run and CI readiness |
| 19 | E2E | Login, GET /auth/me, and browse library | Validates full auth + identity + Lidarr proxy chain |
| 20 | E2E | Stream a track | Validates full playback chain |

### P1 -- Feature Complete

| # | Layer | Scenario | Rationale |
|---|-------|----------|-----------|
| 21 | Backend Integration | Bitrate negotiation (320k vs 128k) | Quality adaptation |
| 22 | Backend Integration | Streaming: seek on passthrough (206 + Content-Range) | Validates Range header support on direct-serve MP3 files |
| 22a | Backend Integration | Streaming: seek on transcoded content (temp-file + 206) | Validates temp-file transcoding then Range-based serving; cached temp file reuse |
| 22b | Backend Integration | Streaming: temp file cleanup (24h expiry, startup clear) | Validates temp file lifecycle management |
| 23 | Backend Integration | POST /api/downloads + GET /api/downloads/:id/file | Offline support |
| 24 | Backend Integration | POST /api/requests/artist (Lidarr add + command) | Music request feature |
| 25 | Backend Integration | POST /api/requests/album (Lidarr monitor + command) | Music request feature |
| 26 | Backend Integration | GET /api/requests returns pending request list with status | Validates request tracking and status field |
| 26a | Backend Integration | Pending requests lifecycle: POST request, status=pending, Lidarr trackFileCount>0 triggers status=available | Validates the full request-then-poll workflow with status transitions |
| 27 | Backend Unit | Lidarr client error handling (timeout, 500, unreachable) | Resilience |
| 28 | Backend Integration | Cover art proxy (artists/:id/image, albums/:id/image) | Image streaming |
| 29 | Backend Integration | GET /api/requests/search (Lidarr lookup proxy) | Search for new music to request |
| 30 | Flutter Unit | AudioPlayerService (play, pause, queue) | Playback controls |
| 31 | Flutter Unit | DownloadManager (queue, progress, storage) | Offline feature |
| 32 | Flutter Unit | ConnectivityMonitor (WiFi vs cellular) | Bitrate switching |
| 33 | Flutter Widget | NowPlayingScreen | Playback UI |
| 34 | Flutter Widget | AlbumScreen, ArtistScreen | Browse UI |
| 35 | Flutter Widget | SearchScreen | Search UI |
| 36 | Flutter Widget | PlaylistScreen | Playlist management UI |
| 37 | Flutter Integration | Full playlist CRUD flow | Client-side playlist lifecycle |
| 38 | E2E | Token refresh mid-session | Session resilience |
| 39 | E2E | Playlist user isolation (multi-user) | Security validation |
| 40 | E2E | Lidarr down -> 502/503 graceful error | Error handling |
| 41 | E2E | Search and request artist + album via Lidarr | Lidarr integration |
| 42 | E2E | Pending requests: request then poll until available | Full request lifecycle |
| 43 | Backend Contract | Lidarr response schema validation against openapi.json | API contract safety net |

### P2 -- Hardening

| # | Layer | Scenario | Rationale |
|---|-------|----------|-----------|
| 44 | Backend Integration | Refresh token reuse detection (replay invalidates family) | Security hardening |
| 45 | Backend Integration | Admin user management (PATCH, DELETE with cascade) | Admin feature |
| 46 | Backend Integration | Admin bootstrap: no duplicate on subsequent startup | Idempotency |
| 47 | Backend Integration | Offline downloads: list and delete | Download management |
| 47a | Backend Integration | Offline downloads: device isolation (same user, different deviceId) | Device-scoped download records |
| 48 | Flutter Unit | SearchService debounce timing | UX polish |
| 49 | Flutter Unit | StorageTracker calculation | Storage display accuracy |
| 50 | Flutter Widget | SettingsScreen (storage, logout) | Settings UI |
| 51 | Flutter Widget | MiniPlayer | Persistent player bar |
| 52 | Flutter Widget | Responsive layout (mobile vs desktop) | Cross-platform UI |
| 53 | Flutter Integration | Offline download + playback | Offline experience |
| 54 | E2E | Concurrent multi-user streaming | Load handling |
| 55 | E2E | Bitrate adaptation (320k vs 128k) | Adaptive streaming |
| 56 | E2E | Backend error -> client error state | Resilience UX |

### Resolved Design Decision: Seek Support via Temp-File Transcoding

Per architecture decision #5: **full seek support is implemented via temp-file transcoding**.

- **Passthrough** (source is MP3 at/below requested bitrate): served directly with standard HTTP Range headers.
- **Transcoding needed**: ffmpeg transcodes to `/tmp/bimusic/<hash>.mp3` (keyed by source path + bitrate), then the temp file is served with HTTP Range headers. Brief initial delay on first request.
- Temp files are cached for reuse and auto-cleaned after 24 hours. `/tmp/bimusic/` is cleared on server startup.
- All streaming tests (scenarios #22, #22a, #22b, E11, E11a) validate `206 Partial Content`, `Content-Range`, and `Accept-Ranges: bytes`.

### Implementation Order Summary

```
Phase 1 (P0):  Scenarios 1-20   -- Health, bootstrap, auth, streaming, browse, basic UI
Phase 2 (P1):  Scenarios 21-43  -- Full features, requests/polling, error handling, E2E
Phase 3 (P2):  Scenarios 44-56  -- Hardening, edge cases, polish
```

---

## 8. File Organization

### Backend Test Structure
```
backend/
  src/
    auth/
      auth.service.ts
      auth.controller.ts
      auth.middleware.ts
      __tests__/
        auth.service.test.ts
        auth.middleware.test.ts
    streaming/
      streaming.service.ts
      transcoding.service.ts
      __tests__/
        streaming.service.test.ts
        transcoding.service.test.ts
    lidarr/
      lidarr.client.ts
      __tests__/
        lidarr.client.test.ts
    playlists/
      playlist.service.ts
      __tests__/
        playlist.service.test.ts
    users/
      user.service.ts
      __tests__/
        user.service.test.ts
  test/
    integration/
      health.integration.test.ts
      auth.integration.test.ts
      auth-me.integration.test.ts
      bootstrap.integration.test.ts
      streaming.integration.test.ts
      streaming-seek.integration.test.ts   # Range header / seek validation (passthrough + temp-file)
      streaming-tempfile.integration.test.ts  # temp file caching, reuse, and cleanup
      playlists.integration.test.ts
      library-proxy.integration.test.ts
      cover-art.integration.test.ts
      requests.integration.test.ts         # /requests/search, /requests/artist, /requests/album
      requests-polling.integration.test.ts # request-then-poll lifecycle
      downloads.integration.test.ts
      users.integration.test.ts
    contract/
      lidarr-contract.test.ts
    fixtures/
      audio/
      lidarr/
      db/
    mocks/
      lidarr-server.ts
    helpers/
      test-app.ts          # creates app instance for Supertest
      test-auth.ts         # generates test JWTs
      test-db.ts           # DB setup/teardown helpers
    setup.ts               # global hooks (DB reset, nock cleanup)
```

### Flutter Test Structure
```
client/
  lib/
    services/
    models/
    screens/
    widgets/
  test/
    unit/
      services/
        auth_service_test.dart
        api_client_test.dart
        audio_player_service_test.dart
        download_manager_test.dart
        search_service_test.dart
        connectivity_monitor_test.dart
      models/
        album_test.dart
        track_test.dart
        playlist_test.dart
    widget/
      screens/
        login_screen_test.dart
        home_screen_test.dart
        album_screen_test.dart
        artist_screen_test.dart
        now_playing_screen_test.dart
        playlist_screen_test.dart
        search_screen_test.dart
        settings_screen_test.dart
      widgets/
        mini_player_test.dart
        offline_badge_test.dart
    helpers/
      mock_services.dart   # shared mocktail mocks
      test_data.dart       # factory functions for test models
      pump_app.dart        # helper to wrap widgets with providers
  integration_test/
    login_flow_test.dart
    browse_play_test.dart
    search_test.dart
    playlist_flow_test.dart
    offline_test.dart
```
