# BiMusic — Team Code Review Issues

Generated: 2026-04-15. All issues found by the five-agent team review (Flutter Dev, Node.js Dev, QA Engineer, Software Architect, UX Designer).

---

## CRITICAL

---

### C-01 — Download status enum mismatch (runtime crash)

**Severity:** Critical  
**Found by:** Software Architect, Flutter Developer  
**Files:**
- `backend/src/services/downloadService.ts`
- `bimusic_app/lib/models/download_task.dart:121`

**Problem:**  
The backend emits four status strings: `"pending"`, `"processing"`, `"ready"`, `"complete"`. The Flutter `DownloadStatus` enum only declares `{ pending, downloading, completed, failed }`. When `DownloadStatus.values.byName("processing")` or `byName("ready")` is called it throws `ArgumentError`, crashing the entire downloads list. Additionally, `"complete"` (backend) does not match `"completed"` (Flutter enum), and `"downloading"` (Flutter) is never written to the DB by the backend.

**Fix:**  
Align the enum values across both layers. Either standardise on `pending | downloading | ready | completed | failed` in the backend DB and Flutter enum, or add a safe mapping function in the Flutter `DownloadTask.fromJson` that translates backend values before passing to the enum.

---

### C-02 — Lidarr queue API returns paginated envelope, not an array

**Severity:** Critical  
**Found by:** Node.js Developer  
**File:** `backend/src/services/lidarrClient.ts:218-224`

**Problem:**  
`lidarrClient.getQueue()` is typed as returning `LidarrQueue[]` and returns `res.data` directly. The real Lidarr v1 `/api/v1/queue` endpoint returns `{ totalRecords: number, records: LidarrQueue[] }`. As a result `requestService.listRequests` iterates over `undefined` when it tries to read queue entries, so `queueAlbumIds` and `queueArtistIds` are always empty and the `"downloading"` status is **never detected** for any request.

**Fix:**  
Update the return type to `{ totalRecords: number; records: LidarrQueue[] }` and change the caller in `requestService.ts` to use `queue.records` instead of `queue`.

---

### C-03 — Refresh token rotation is not atomic (race condition)

**Severity:** Critical  
**Found by:** Node.js Developer  
**File:** `backend/src/services/authService.ts:96-105`

**Problem:**  
The delete-old-token and insert-new-token operations are two separate `db.run()` calls outside any transaction. Two concurrent requests arriving with the same refresh token can both pass the initial `SELECT` check before either executes the `DELETE`, resulting in two valid new token pairs being issued while the original is deleted only once. This breaks the one-time-use guarantee of refresh token rotation.

**Fix:**  
Wrap the `SELECT` + `DELETE` + `INSERT` block in `db.transaction()`.

---

### C-04 — `Platform.isWindows` crashes on Web

**Severity:** Critical  
**Found by:** Flutter Developer  
**File:** `bimusic_app/lib/app.dart:25`

**Problem:**  
`dart:io`'s `Platform` class is not available on the web platform. Accessing `Platform.isWindows` unconditionally throws `UnsupportedError` at runtime when the app is compiled for web.

**Fix:**  
Guard with `!kIsWeb && Platform.isWindows`.

---

## HIGH

---

### H-01 — JWT `isAdmin` decoded with unsafe cast

**Severity:** High  
**Found by:** Flutter Developer, Software Architect  
**File:** `bimusic_app/lib/services/auth_service.dart:132`

**Problem:**  
`map['isAdmin'] as bool` will throw a `TypeError` if the JWT payload ever contains an integer `0` or `1` rather than a Dart `bool`. The current backend encodes `isAdmin: user.isAdmin === 1` (a boolean), so it works today, but the cast is fragile against any alternative token-generation path or hand-crafted JWT.

**Fix:**  
Use `(map['isAdmin'] as bool?) ?? false` or `map['isAdmin'] == true`.

---

### H-02 — `markDownloadComplete` called before file is served

**Severity:** High  
**Found by:** Node.js Developer  
**File:** `backend/src/routes/downloads.ts:102-105`

**Problem:**  
`markDownloadComplete(id)` sets the download status to `"complete"` synchronously before `serveFile` begins streaming bytes. A concurrent `DELETE /api/downloads/:id` request between these two calls will pass the ownership check, delete the file, and then `serveFile` will try to stat a now-missing file and throw.

**Fix:**  
Move `markDownloadComplete(id)` into a `res.on('finish', ...)` callback so it only fires after the response has been fully sent.

---

### H-03 — `refreshExpiresAt()` ignores `JWT_REFRESH_EXPIRY` env var

**Severity:** High  
**Found by:** Node.js Developer  
**File:** `backend/src/services/authService.ts:37-39`

**Problem:**  
`env.JWT_REFRESH_EXPIRY` is validated and defaulted to `"30d"` in env config, but `refreshExpiresAt()` always computes `Date.now() + 30 * 24 * 60 * 60 * 1000` (hardcoded 30 days) and never reads the env value. Setting `JWT_REFRESH_EXPIRY=7d` has no effect.

**Fix:**  
Parse `env.JWT_REFRESH_EXPIRY` (e.g. via the `ms` package) and use it in the calculation.

---

### H-04 — `HomeScreen` is a stub

**Severity:** High  
**Found by:** UX Designer  
**File:** `bimusic_app/lib/ui/screens/home_screen.dart`

**Problem:**  
The entire screen body is `Center(child: Text('Home'))`. This is the app's initial route after login (`/home`). A user landing here after authenticating sees a blank page.

**Fix:**  
Implement a meaningful home screen (recently played, continue listening, or quick navigation shortcuts).

---

### H-05 — "Retry" button on failed downloads silently cancels instead

**Severity:** High  
**Found by:** UX Designer  
**File:** `bimusic_app/lib/ui/screens/downloads_screen.dart:419`

**Problem:**  
The button is rendered with `Icons.refresh` and tooltip "Retry", but its `onPressed` calls `downloadProvider.notifier.cancelDownload(task.serverId)`. Tapping "Retry" silently cancels the task.

**Fix:**  
Either implement a `retryDownload(serverId)` method in `DownloadNotifier` and call it here, or re-call `requestDownload` with the original track parameters.

---

### H-06 — CI Flutter coverage gate set to 60%, not the documented 70%

**Severity:** High  
**Found by:** QA Engineer  
**File:** `.github/workflows/ci.yml:57`

**Problem:**  
The CI enforces `≥60%` line coverage for Flutter but `CLAUDE.md` documents the threshold as `≥70%`. Tests can silently slip below the intended standard while the pipeline stays green.

**Fix:**  
Update the CI threshold to `70` to match the documented requirement.

---

## MEDIUM

---

### M-01 — `"processing"` rows stuck permanently after server crash

**Severity:** Medium  
**Found by:** Software Architect  
**File:** `backend/src/services/downloadService.ts`

**Problem:**  
When the download worker picks a `"pending"` row it immediately sets it to `"processing"`. If the server is killed during transcoding, the row stays `"processing"` forever — the worker only queries for `"pending"` rows, and `initTempDir()` clears temp files but not the stuck DB record.

**Fix:**  
On server startup (in `index.ts` after migrations), run a query that resets all `"processing"` rows back to `"pending"` so they are retried on the next worker tick.

---

### M-02 — Lidarr `path` field leaked via search proxy

**Severity:** Medium  
**Found by:** Software Architect  
**File:** `backend/src/routes/requests.ts:59-63`

**Problem:**  
`GET /api/requests/search` forwards raw `LidarrArtist[]` and `LidarrAlbum[]` objects directly from `lidarrClient.lookupArtist/lookupAlbum` to every authenticated client. The `LidarrArtist` type includes a `path` field (the local filesystem path where Lidarr stores music files), leaking internal server layout.

**Fix:**  
Project the response to a safe subset before sending: strip `path`, `statistics`, `qualityProfileId`, and other internal fields.

---

### M-03 — `deleteUser` has no self-deletion guard and returns 204 for missing IDs

**Severity:** Medium  
**Found by:** Node.js Developer, Software Architect  
**File:** `backend/src/routes/users.ts:38`

**Problem:**  
An admin can `DELETE /api/users/:id` using their own ID. SQLite cascades the deletion through all refresh tokens, playlists, and downloads, while the access token remains valid until expiry. Additionally, deleting a nonexistent ID returns 204 silently (the `db.delete` runs with zero rows affected and no error is thrown).

**Fix:**  
Add a guard rejecting deletion of `req.user.id === req.params['id'] as string` with a 400. Add an existence check and return 404 if no rows were deleted.

---

### M-04 — `listPlaylists` fires N+1 count queries

**Severity:** Medium  
**Found by:** Node.js Developer  
**File:** `backend/src/services/playlistService.ts:36-47`

**Problem:**  
For every playlist row returned, a separate `SELECT count(*) FROM playlist_tracks WHERE playlistId = ?` query is executed inside a loop. With many playlists this creates N+1 database round trips.

**Fix:**  
Replace with a single query using a `LEFT JOIN` and `GROUP BY playlistId` to compute all counts in one pass.

---

### M-05 — MP3 downloads always re-transcoded (lossy-to-lossy)

**Severity:** Medium  
**Found by:** Node.js Developer  
**File:** `backend/src/services/downloadService.ts:221-231`

**Problem:**  
`processOnePendingDownload` always invokes `transcodeToFile()` via ffmpeg regardless of the source file format. The streaming route uses `isPassthrough()` to skip re-encoding MP3 sources, but no equivalent check exists in the download path. MP3 sources are needlessly re-encoded lossy-to-lossy, degrading quality.

**Fix:**  
Call `isPassthrough(sourcePath)` before transcoding; if true, copy the file directly (e.g. `fs.copyFile`) instead of invoking ffmpeg.

---

### M-06 — Cover-art proxy has no error handler mid-stream

**Severity:** Medium  
**Found by:** Node.js Developer  
**File:** `backend/src/routes/library.ts:51-58, 111-118`

**Problem:**  
`imageRes.data.pipe(res)` has no `imageRes.data.on('error', ...)` handler. If Lidarr drops the connection while piping cover art, the response is left half-written with no error status and no way to signal the failure to the client.

**Fix:**  
Add `.on('error', (err) => { if (!res.headersSent) res.status(502).end(); else res.destroy(); })` to the readable stream.

---

### M-07 — Downloads tab unreachable on mobile

**Severity:** Medium  
**Found by:** UX Designer  
**File:** `bimusic_app/lib/ui/layouts/mobile_layout.dart:10`

**Problem:**  
`_mobileToBranchIndex` maps to `[0, 1, 2, 3, 5]`, skipping branch index 4 (Downloads). The mobile `NavigationBar` has 5 tabs (Home/Library/Search/Playlists/Settings). A user who downloads tracks on mobile has no way to view download status, retry failures, or manage storage.

**Fix:**  
Either add Downloads as a 6th tab on mobile, or add a "View Downloads" entry point from the Album detail screen and/or a notification banner.

---

### M-08 — Requests list shows numeric Lidarr ID instead of artist/album name

**Severity:** Medium  
**Found by:** UX Designer  
**File:** `bimusic_app/lib/ui/screens/search_screen.dart:565`

**Problem:**  
Request tile titles are constructed as `'Artist #${request.lidarrId}'` / `'Album #${request.lidarrId}'`. Users cannot identify what they requested without memorising Lidarr integer IDs.

**Fix:**  
Store and display the artist/album name. This requires either persisting `name` in the `requests` table (see issue A-01) or looking it up from Lidarr on display.

---

### M-09 — `getLidarrDefaults` auto-fetch path completely untested

**Severity:** Medium  
**Found by:** QA Engineer  
**File:** `backend/src/routes/requests.ts`

**Problem:**  
Every `POST /api/requests/artist` integration test supplies `qualityProfileId`, `metadataProfileId`, and `rootFolderPath` explicitly. The `getLidarrDefaults()` code path — which auto-fetches these from Lidarr when they are omitted — and its three distinct error branches (no quality profiles, no metadata profiles, no root folders) have zero test coverage.

**Fix:**  
Add integration test cases for `POST /api/requests/artist` with each field omitted, and nock the corresponding Lidarr endpoints.

---

### M-10 — `admin.test.ts` non-deterministic assertion

**Severity:** Medium  
**Found by:** QA Engineer  
**File:** `backend/tests/integration/admin.test.ts:55`

**Problem:**  
`expect([200, 404]).toContain(res.status)` always passes regardless of what the server returns — this is a no-op assertion that masks real failures in the admin logs endpoint.

**Fix:**  
Make the log file path deterministic in tests (set `LOG_PATH` to a temp directory in the test setup) and assert a specific status code.

---

## LOW

---

### L-01 — Error states missing Retry buttons in album/track screens

**Severity:** Low  
**Found by:** UX Designer  
**Files:**
- `bimusic_app/lib/ui/screens/artist_detail_screen.dart:92-94`
- `bimusic_app/lib/ui/screens/album_detail_screen.dart:121-122`

**Problem:**  
Both screens render `Center(child: Text('Failed to load ...'))` with no Retry button and no `ref.invalidate()` call on error. Every other error state in the app has a Retry. The user is stuck.

**Fix:**  
Add a `TextButton('Retry', onPressed: () => ref.invalidate(provider))` in both error branches.

---

### L-02 — Empty state messages missing on artist and album screens

**Severity:** Low  
**Found by:** UX Designer  
**Files:**
- `bimusic_app/lib/ui/screens/artist_detail_screen.dart:95-118`
- `bimusic_app/lib/ui/screens/album_detail_screen.dart` (data branch)

**Problem:**  
When `albums` or `tracks` is an empty list, the sliver renders with zero children and the screen shows only the header. The user cannot tell if the data is genuinely empty or if loading silently failed.

**Fix:**  
Add an empty-state widget (e.g. `SliverFillRemaining(child: Center(child: Text('No albums yet')))`) for each zero-item case.

---

### L-03 — FullPlayer no queue view; desktop FullPlayer is not idiomatic

**Severity:** Low  
**Found by:** UX Designer  
**Files:**
- `bimusic_app/lib/ui/widgets/full_player.dart`
- `bimusic_app/lib/ui/layouts/desktop_layout.dart:87-95`

**Problem:**  
(a) There is no "Up Next" or queue view anywhere — the play queue is invisible to the user after `playQueue()` is called. (b) On desktop the `PlayerBar` opens `FullPlayer` as a bottom sheet, which is not idiomatic at full desktop width.

**Fix:**  
(a) Add a queue sheet/panel to `FullPlayer`. (b) Replace the bottom-sheet approach on desktop with an expanded panel or a side drawer.

---

### L-04 — Library grid `crossAxisCount` hardcoded at 2 for all screen widths

**Severity:** Low  
**Found by:** UX Designer  
**Files:**
- `bimusic_app/lib/ui/screens/library_screen.dart:42`
- `bimusic_app/lib/ui/screens/artist_detail_screen.dart:99`

**Problem:**  
`crossAxisCount: 2` is used unconditionally on both mobile and desktop. On a 1440 px monitor this produces two very large cards per row despite `breakpoints.dart` providing the breakpoint infrastructure.

**Fix:**  
Use `LayoutBuilder` or `MediaQuery` to set `crossAxisCount` based on available width (e.g. 2 on mobile, 4–5 on desktop).

---

### L-05 — Icon-only player buttons have no tooltips or semantic labels

**Severity:** Low  
**Found by:** UX Designer  
**Files:**
- `bimusic_app/lib/ui/widgets/player_bar.dart:117, 134`
- `bimusic_app/lib/ui/widgets/full_player.dart`

**Problem:**  
Play/pause and skip icons in `PlayerBar` have no `tooltip` or `semanticsLabel`. `ArtistCard` and `AlbumCard` use `GestureDetector` with no `Semantics` wrapper, making them invisible to screen readers.

**Fix:**  
Add `tooltip:` to all `IconButton` widgets. Wrap `GestureDetector` tap targets in `Semantics(label: ..., button: true)` or switch to `InkWell`.

---

### L-06 — `_LogViewerDialog` stores `WidgetRef` as a field

**Severity:** Low  
**Found by:** Flutter Developer  
**File:** `bimusic_app/lib/ui/screens/settings_screen.dart:407-409`

**Problem:**  
The dialog stores the outer `WidgetRef` as a constructor parameter field. The stored ref can become invalid after the parent widget rebuilds or is disposed, causing use-after-dispose crashes. The field is only used inside `build()` where a fresh `widgetRef` argument is already available.

**Fix:**  
Remove the `ref` constructor parameter and use the `widgetRef` parameter passed to `build()` directly.

---

### L-07 — `DownloadTask` fields are mutable

**Severity:** Low  
**Found by:** Flutter Developer  
**File:** `bimusic_app/lib/models/download_task.dart:32-37`

**Problem:**  
`status`, `progress`, `filePath`, `fileSizeBytes`, `completedAt`, and `errorMessage` are not `final`. `DownloadNotifier` correctly uses `copyWith` to produce new instances, but nothing prevents external code from mutating tasks in-place, bypassing state notification.

**Fix:**  
Mark all fields `final`.

---

### L-08 — No login rate limiting

**Severity:** Low  
**Found by:** Software Architect  
**File:** `backend/src/routes/auth.ts:22`

**Problem:**  
`POST /api/auth/login` has no rate limiting. On a self-hosted instance exposed to a network, this permits unlimited password guessing.

**Fix:**  
Add `express-rate-limit` keyed by IP on the login endpoint (e.g. 10 attempts per minute).

---

### L-09 — `requests` table missing `name` and `cover_url` columns from ADR

**Severity:** Low  
**Found by:** Software Architect  
**Files:**
- `docs/architecture-decisions.md`
- `backend/src/db/schema.ts:98-112`

**Problem:**  
The architecture decision record specifies `name TEXT NOT NULL` and `cover_url TEXT` on the `requests` table. Neither is implemented. The requests list UI cannot show artist/album names without a separate Lidarr round-trip per item (see also M-08).

**Fix:**  
Add `name` and `cover_url` columns to the `requests` schema and migration, populate them on insert, and include them in `MusicRequest` API type and Flutter model.

---

### L-10 — `playQueue` offline `AudioSource.file()` path untested

**Severity:** Low  
**Found by:** QA Engineer  
**File:** `bimusic_app/test/providers/player_provider_test.dart`

**Problem:**  
`PlayerNotifier.play()` resolves local file paths from `downloadProvider` and passes them to `BiMusicAudioHandler.playQueue()` as `localFilePaths`. The logic that selects `AudioSource.file()` over the stream URL for downloaded tracks has no test coverage — a regression here would silently break offline playback.

**Fix:**  
Add a test that seeds `downloadProvider` with a completed task and asserts that `playQueue` is called with a non-empty `localFilePaths` map containing the expected `trackId → filePath` entry.

---

### L-11 — `reorderTracks` does not call `refresh()` on the playlist list

**Severity:** Low  
**Found by:** Flutter Developer  
**File:** `bimusic_app/lib/providers/playlist_provider.dart:50-53`

**Problem:**  
Every other mutation (`addTracks`, `removeTrack`, `updatePlaylist`, `deletePlaylist`) calls `await refresh()` after the service call. `reorderTracks` only invalidates `playlistDetailProvider` but never refreshes the list provider, leaving the summary list in a potentially inconsistent state.

**Fix:**  
Add `await refresh()` after `ref.invalidate(playlistDetailProvider(playlistId))` in `reorderTracks`.

---

## INFORMATIONAL

---

### I-01 — `isAdmin` JWT claim type — defensive hardening note

**Severity:** Informational  
**Found by:** Software Architect  
**File:** `bimusic_app/lib/services/auth_service.dart:132`

The backend correctly encodes `isAdmin` as a boolean in the JWT payload (`user.isAdmin === 1`). This is already safe, but the Flutter decode `map['isAdmin'] as bool` should be `(map['isAdmin'] as bool?) ?? false` to guard against null or unexpected types from hand-crafted tokens. Overlaps with H-01; addressed there.

---

### I-02 — Admin logs endpoint returns raw log lines

**Severity:** Informational  
**Found by:** Software Architect  
**File:** `backend/src/routes/admin.ts`

`GET /api/admin/logs` returns the last 200 raw Pino JSON log lines. Pino logs may include user-supplied values (search terms, track titles). Given the trust model (admin-only endpoint) this is low risk, but if any log line contains PII it would be surfaced verbatim.

---

### I-03 — `trackCount` bigint coercion in playlist list

**Severity:** Informational  
**Found by:** Software Architect  
**Files:**
- `backend/src/services/playlistService.ts:42`
- `bimusic_app/lib/models/playlist.dart:17`

`COUNT(*)` via Drizzle/better-sqlite3 returns a JS number in practice. `PlaylistSummary.fromJson` reads `json['trackCount'] as int`. This is not a current bug but is worth confirming if the SQLite driver version changes bigint behaviour.
