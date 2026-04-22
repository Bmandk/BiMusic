# HLS Migration Plan

Replace the current single-MP3-over-HTTP streaming architecture with HLS
(HTTP Live Streaming). This is a structural change to how audio is served,
not a refinement of the existing path.

---

## 1. Why we're doing this

### 1.1 The user-visible problem

Seeking into long non-MP3 tracks (e.g. a 17-minute FLAC) takes many seconds
before playback resumes at the seek target. On a fast LAN, seeks should
respond in well under a second.

### 1.2 Root cause

On Windows/Linux desktop, Flutter audio is provided by
`just_audio` → `just_audio_media_kit` → `media_kit` → libmpv. The chain
hardcodes two MPV properties that are the cause of every seek problem we
tried to solve:

- `cache-on-disk: yes` — tells libmpv's demuxer to spool the entire HTTP
  stream to disk, ignoring `demuxer-max-bytes` (which would otherwise cap
  the cache at 2 MB via `JustAudioMediaKit.bufferSize`).
- `cache: yes` + aggressive readahead — libmpv reads from the HTTP source
  as fast as the server can deliver.

The effect: libmpv opens a single `GET /api/stream/:trackId` request, reads
the full transcoded MP3 (~16 MB for a 17-min track) as fast as the server
produces it (~100× realtime), and **only then** processes the user's seek
by jumping around inside its cached copy. Any user seek issued before the
download completes is queued behind the prefetch.

### 1.3 What we tried and why none of it is kept

The `fix/seek-bar-snap-back` branch and the uncommitted work on it went
through a sequence of workarounds, each of which either fails outright or
papers over the real problem:

| Attempt | Behavior | Why it's discarded |
|---|---|---|
| UI hold-the-slider for up to 3 s after `onChangeEnd` (`_seekTarget` + fallback timer in `full_player.dart`) | Hides the snap-back visually but the *actual* audible seek is still slow. | Pure cosmetics; obsolete once seeks are fast. |
| `Accept-Ranges: bytes` + `-ss` on Range requests (`streamService.ts` tee + `streamSeekedTranscode`) | Turns the single-request prefetch into N sequential Range requests — still full-file prefetch, just chunked. | Same root problem; libmpv still prefetches everything before seeking. |
| Bounded 206 responses (1 MB initial + 512 KB per Range) | libmpv logs `Stream ends prematurely at X, should be Y` and spam-fires sequential Range requests to reconstruct the file. | Treats symptom not cause; libmpv still ends up with the whole file in cache before seeks execute. |
| `ffmpeg -readrate 2.0` throttle | libmpv underruns instead of issuing a new Range at the seek target. Seeking stops playback entirely. | Assumes libmpv falls back to ranged reads under throttle — it doesn't. |
| Vendored `just_audio_media_kit` fork that sets `cache-on-disk=no` after init | Actually works, but the fork exists solely to flip one upstream string and we have to track it forever. | Hacky; HLS removes the need for any client patch. |

### 1.4 Why HLS fixes it properly

With HLS, there is no single long-lived stream for libmpv to prefetch.
The client fetches a short playlist and then small independent segments.
Seek semantics are built into the protocol: libmpv calculates which segment
covers the seek target, fetches that segment, and starts playback. There is
nothing for `cache-on-disk` to misbehave about — each segment is a
self-contained small file.

libmpv, iOS, Android, and modern browsers all understand HLS natively.
It's also the same shape of solution used by every commercial music
streamer, so we stop fighting idiosyncrasies of one playback stack.

---

## 2. Target architecture

### 2.1 New HTTP surface

Replace the single `GET /api/stream/:trackId` endpoint with two HLS
endpoints under `/api/stream`:

```text
GET /api/stream/:trackId/playlist.m3u8?bitrate=128&token=<jwt>
GET /api/stream/:trackId/segment/:index?bitrate=128&token=<jwt>
```

- `playlist.m3u8` returns a static VOD HLS media playlist with one
  `#EXTINF` entry per segment. Content-Type: `application/vnd.apple.mpegurl`.
- `segment/:index` returns the MPEG-TS segment for the given zero-based
  index. Content-Type: `video/mp2t` (standard for MPEG-TS even for
  audio-only). `:index` is a three-digit zero-padded integer (e.g. `000`,
  `042`, `169`); the handler parses it with `parseInt(raw, 10)`, which
  already tolerates leading zeros. The extension is intentionally omitted
  from the route pattern: Express 5 / path-to-regexp v8 no longer parses
  `:index.ts` as `<param>.<literal>`, so keeping the route extension-free
  avoids a silent mismatch. The playlist still advertises segment URIs as
  `segment/000` (no `.ts`); libmpv, ExoPlayer, and AVPlayer all rely on
  `Content-Type: video/mp2t` rather than the URL suffix for format
  detection.
- Both accept `?bitrate=128|320` (default 320) and `?token=<jwt>` (the
  same auth-via-query-param we already use to work around libmpv not
  supporting custom request headers).
- The `authenticate` middleware runs on both. Each segment request carries
  its own token because HLS clients open fresh connections per segment.

MP3 passthrough goes away — every non-cached track now flows through the
HLS path regardless of source format. Simpler backend, one code path.

### 2.2 Segment format

Each segment is MPEG-TS containing a single audio track encoded with
`libmp3lame` at the requested bitrate. Segment duration: 6 seconds.

Why these choices:

- **MP3 audio** keeps feature parity with today's transcoder (same codec,
  same 128 / 320 kbps options, same quality trade-offs). No user-visible
  audio change.
- **MPEG-TS container** is the universally understood HLS segment format.
  `ffmpeg`'s HLS muxer emits MP3-in-TS natively (`aac_adtstoasc` is not
  needed; we're not using AAC).
- **6 seconds** balances seek granularity (worst-case ≤6 s of re-buffering
  on a miss) against playlist size. Apple's HLS spec recommends 6 s as the
  default for VOD.

### 2.3 On-disk cache layout

```text
$HLS_CACHE_DIR/<trackKey>/
    segment000.ts
    segment001.ts
    ...
    segment169.ts            # for a 17-min track at 6 s segments
```

`<trackKey>` is `sha256(sourcePath + ":" + sourceMtimeMs + ":" + sourceSize + ":" + bitrate)` (hex).
Including the source file's mtime and byte-size in the key means the cache
automatically invalidates when the source file is replaced (e.g. Lidarr
re-downloads at higher quality). Different bitrate ⇒ different cache dir.

**Only segments are cached on disk. The playlist is rebuilt fresh on every
request** because it embeds the caller's JWT into each segment URI (see
§ 2.5). Caching the playlist would serve user A's token to user B, so it
is a pure function of `(durationMs, bitrate, token)` computed at request
time. Playlist generation is trivial (string concatenation; no ffmpeg) —
there is nothing to gain by caching it.

Cache dir is configured via `HLS_CACHE_DIR` env var (default
`./data/hls`). Replaces the current `TEMP_DIR`.

### 2.4 When segments are generated

Two options, in order of preference:

**Option A — lazy per-segment (MVP).** Segments are transcoded on demand:

1. Client requests `playlist.m3u8`.
2. Server resolves the track, reads its duration from Lidarr, computes
   `segmentCount = ceil(durationSec / 6)`, and emits a playlist with
   `segmentCount` entries.
3. Client requests segment N.
4. Server checks cache. If missing, spawns `ffmpeg -ss <N*6> -t 6` with
   `libmp3lame` + `-f mpegts` → temp file → `rename()` into the cache.
   Concurrent requests for the same segment are deduplicated via an
   in-flight map keyed on `<trackKey>/segmentNNN.ts`.
5. Serve the segment with `Content-Type: video/mp2t`, `Content-Length`,
   and `Cache-Control: private, max-age=86400`. `private` (not `public`)
   because auth is carried in the URL via `?token=`; a shared/CDN cache
   keyed on the full URL could otherwise serve cached bytes to unrelated
   clients that happen to replay the same URL after the token expires.

Pros: simple; seek is always fast (one ffmpeg spawn, ~100–200 ms to produce
a 6 s segment); no wasted work if a user skips a track.

Cons: ffmpeg spawn per 6 s of audio during sequential playback
(~170 spawns for a 17-min track). On a modern box this is trivial — each
spawn is ~50 ms CPU — but it's more process churn than Option B.

Cons (format-specific): OGG Vorbis sources without an embedded seek index
require a linear scan from file start on every `-ss` invocation. Under
Option A this multiplies: 170 segments × full-file scan ≈ quadratic cost.

**Mitigation (preferred — pre-transcode to seekable MP3):** on first
playlist request, detect `format_name === "ogg"` via
`ffprobe -v quiet -of json -show_entries format=format_name`. If the
source is OGG, kick off a background full-transcode to
`<cacheDir>/<trackKey>/source.mp3` (a single `ffmpeg -i <source>
-c:a libmp3lame -b:a <bitrate>k source.mp3`). While that runs, serve
any requested segments using Option B catch-up from the growing MP3
intermediate — or simply queue segments until the MP3 is ready if no
user seek has been issued. Once `source.mp3` exists, all subsequent
segment requests run Option A against the seekable MP3. This avoids
the Option B bookkeeping entirely after the first access and requires
no ffprobe seek-index introspection beyond the format name check.

**Alternative (Option B fallback):** if the pre-transcode approach
proves hard to integrate, fall back to spawning a single continuous
`ffmpeg ... -f segment -segment_time 6 ...` that fills the cache dir
sequentially, with on-demand spawns only used for seeks ahead of the
transcoder. More bookkeeping; prefer the pre-transcode path.

All other formats (MP3, FLAC, AAC, ALAC, Opus) have reliable seek
tables and stay on Option A with no pre-processing.

**Option B — eager background transcode + lazy catch-up.** Same as A, but
on first playlist request also kick off a single background ffmpeg that
sequentially produces all segments. On-demand generation only runs if a
segment is requested before the background job has reached it (i.e. a
seek ahead of the current transcode position).

Pros: fewer total ffmpeg spawns; cache is complete sooner for re-plays.

Cons: more bookkeeping (track per-track background jobs; reconcile with
on-demand spawns; decide cancellation rules).

**Recommendation: start with Option A.** It's the minimum viable thing that
makes seeks fast. If profiling shows per-segment spawn overhead is a real
cost, add Option B as a follow-up — it's purely a backend optimization and
the wire protocol doesn't change.

### 2.5 Playlist template

Rebuilt on every request (not cached — see § 2.3):

```m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:6.000,
segment/000?bitrate=128&token=<client's JWT>
#EXTINF:6.000,
segment/001?bitrate=128&token=<client's JWT>
...
#EXTINF:3.456,
segment/169?bitrate=128&token=<client's JWT>
#EXT-X-ENDLIST
```

Three details worth calling out:

- **Segment URIs are relative to the playlist URI.** libmpv will resolve
  `segment/000` against the request URL, so we don't need absolute URLs.
  Clients detect the format from the `Content-Type: video/mp2t` response
  header, not the URL suffix — the `.ts` extension is deliberately absent
  (see § 2.1).
- **Token propagation.** The JWT that authenticated the playlist request
  is embedded into each segment URI. This is the same trick we use today
  for the live stream URL and works with libmpv's HTTP client. If the
  token expires mid-playback, segment requests will 401 and playback will
  stall. Mitigation reuses the existing
  `BiMusicAudioHandler.updateToken(newToken)` (already introduced on
  `fix/token-refresh-audio-stream`): on refresh it rebuilds the audio
  source with a fresh playlist URL, which now embeds the new token into
  every segment URI transparently. Within one access-token lifetime
  (15 min today) the token is stable and segments just work.
- **Token redaction in logs.** Segment and playlist URLs contain
  `?token=<jwt>` as a query parameter. This value must be stripped before
  any URL is emitted to HTTP access logs, reverse-proxy logs, application
  request/response logs, or error telemetry. Implement this in Pino's
  `serializers` or in Express middleware (redact `req.url` and
  `req.query.token` before logging) so the rule applies uniformly to both
  the playlist and segment routes. Failure to redact leaks valid JWTs into
  log files, which are often stored with weaker access controls than the
  secrets they contain.
- **Last segment's `EXTINF`** reflects the *actual* remaining duration, not
  6 s, so the computed duration matches Lidarr's metadata.

### 2.6 ffmpeg invocation for a single segment

```bash
ffmpeg -nostdin -hide_banner -loglevel warning \
       -ss <N*6> -i <sourcePath> \
       -t 6 \
       -vn -c:a libmp3lame -b:a <bitrate>k \
       -output_ts_offset <N*6> \
       -muxdelay 0 -muxpreload 0 \
       -f mpegts <cacheDir>/segment<NNN>.ts.part
```

Then `rename()` `.part` → final. Input-side `-ss` is fast for both FLAC
(seek table) and MP3 (CBR or Xing header). For OGG Vorbis sources,
use the pre-transcode-to-MP3 path described in § 2.4 (preferred) rather
than paying the linear-scan cost per segment; Option B is the fallback
only when pre-transcoding is not feasible.

**Timestamp strategy.** Each segment is an independent ffmpeg run. Without
`-output_ts_offset <N*6>` every segment's PTS would restart near zero;
strict HLS clients (notably AVPlayer) then either need `EXT-X-DISCONTINUITY`
tags or produce audible glitches at segment joins. With the offset, PTS
are continuous across segments as if they came from one muxer, no
discontinuity markers needed. `-muxdelay 0 -muxpreload 0` keeps TS
packaging tight so segment boundaries align exactly with the 6 s grid.

Exactly one segment is produced per ffmpeg invocation, which avoids the
"partial segment on error" class of bugs.

---

## 3. Backend changes

### 3.1 New files

- `backend/src/services/hlsService.ts` — the whole HLS story:
  - `getHlsCacheDir(trackKey)` — resolves cache dir path.
  - `computeTrackKey(sourcePath, bitrate)` — sha256 hash (mirrors the
    current `getTempFilePath` helper).
  - `buildPlaylist(durationMs, segmentCount, bitrate, token)` — pure
    function that returns playlist text.
  - `generateSegment({ sourcePath, bitrate, segmentIndex })` — spawns
    ffmpeg for exactly one 6 s segment, writes to `<cacheDir>/<index>.ts`.
    Deduplicates concurrent callers via a `Map<segmentKey, Promise<string>>`.
    Registers the ffmpeg command with `registerFfmpegCommand` for graceful
    shutdown (same mechanism as today).
  - `ensureSegment(...)` — returns the path to a ready segment, generating
    on demand if missing.
  - `initHlsCacheDir()` — called at boot; clears stale `.part` files.
  - `startHlsCacheCleanup()` — hourly prune of cache dirs not touched in
    24 h. (Mirrors the current `startTempFileCleanup`.)
- `backend/src/routes/stream.ts` — rewritten (see § 4.2).

### 3.2 Route handlers

Two small handlers replace the one existing `GET /api/stream/:trackId`:

```ts
// GET /api/stream/:trackId/playlist.m3u8
//  - auth via existing authenticate middleware
//  - resolveFilePath → { sourcePath, durationMs } (restore the branch's
//    object-returning signature, because the playlist needs the duration)
//  - compute segmentCount = Math.ceil(durationMs / 6000)
//  - build playlist text, serve with Content-Type application/vnd.apple.mpegurl
//    and Cache-Control: no-store (the playlist is tiny; simplest to not cache
//    at the HTTP layer)
```

```ts
// GET /api/stream/:trackId/segment/:index
//  - auth
//  - parse :index as int (parseInt tolerates leading zeros like "000"),
//    reject >= segmentCount or < 0 (indices are zero-based; last valid
//    index is segmentCount - 1)
//  - resolveFilePath + bitrate parsing (same as playlist)
//  - ensureSegment() → absolute file path
//  - serve the .ts file with Content-Type: video/mp2t; add an optional
//    contentType parameter to serveFile() in trackFileResolver.ts so
//    both the download route (audio/mpeg) and the HLS segment route
//    (video/mp2t) can share the same Range-capable helper without
//    hardcoding the MIME type
```

Remove from the current route file:

- `isPassthrough` branch (no MP3 shortcut — every track goes through HLS).
- `streamTranscoded` call (the blocking full-file transcoder is gone).

### 3.3 Files to delete / change

Rename the trimmed `streamService.ts` → `trackFileResolver.ts` so its
purpose (resolve Lidarr track → local file + Lidarr-root remap + shared
ffmpeg-process registry) is clear and unrelated to HTTP streaming. Update
the two consumers to import from the new path:

- `backend/src/services/downloadService.ts` — currently imports
  `resolveFilePath`, `isPassthrough`, `registerFfmpegCommand`,
  `unregisterFfmpegCommand` from `./streamService.js`. Change imports to
  `./trackFileResolver.js`. **Keep `isPassthrough`** — downloads still
  use it to skip re-encoding MP3 sources. The "delete `isPassthrough`"
  note applies only to the HLS path, which no longer has a passthrough
  branch.
- `backend/src/routes/downloads.ts` — currently imports `serveFile` from
  `./streamService.js` for serving the finished offline MP3. The download
  route needs full HTTP Range semantics (clients may resume interrupted
  downloads via Range), so **keep `serveFile`** in `trackFileResolver.ts`
  and update the import path. Add an optional `contentType` parameter
  (default `'audio/mpeg'`) so the HLS segment route can call
  `serveFile(res, segmentPath, { contentType: 'video/mp2t' })` without
  a dedicated wrapper — no need for a separate `serveStaticFile`.

Helpers retained in `trackFileResolver.ts`:

- `resolveFilePath`
- `isPassthrough` (used by downloads only)
- `serveFile` (used by downloads, and by the HLS segment route)
- `registerFfmpegCommand` / `unregisterFfmpegCommand` /
  `killAllActiveTranscodes`
- The Lidarr root-folder remap logic used by `resolveFilePath`
- `resetLidarrRootCache` (test helper)

Deleted outright: `ensureTranscoded`, `streamTranscoded`,
`getTempFilePath`, `initTempDir`, `startTempFileCleanup`, all the tee /
`.part` / in-progress-transcodes plumbing.

Test file moves:

- `backend/src/services/__tests__/streamService.test.ts` — split: the
  helpers that survive move to `trackFileResolver.test.ts`; everything
  about `streamTranscoded` / `ensureTranscoded` is rewritten as
  `hlsService.test.ts` covering the new surface.
- `backend/tests/integration/stream.test.ts` — rewrite as
  `tests/integration/hls.test.ts`.
- `backend/src/services/__tests__/downloadService.test.ts` — already
  uses `import * as streamService from "../streamService.js"`; update
  the path to `../trackFileResolver.js`. No logic changes.

### 3.4 Config

New env variables in `backend/.env.example` and `backend/src/config/env.ts`:

- `HLS_CACHE_DIR` — path to the segment cache directory (absolute or relative; relative paths are resolved against the application working directory). Default `./data/hls`.
- `HLS_SEGMENT_SECONDS` — default `6`. Exposed for experimentation; the
  default is what ships.

Remove `TEMP_DIR`.

### 3.5 Downloads

Downloads already produce a single MP3 file at a fixed bitrate and are
unrelated to the streaming path. They continue to use `libmp3lame`
directly via `fluent-ffmpeg` and keep the `isPassthrough` shortcut for
MP3 sources. **No logic changes** to `downloadService.ts` — only the
one-line import path change from `./streamService.js` to
`./trackFileResolver.js` described in § 3.3.

Similarly, `backend/src/routes/downloads.ts` keeps using `serveFile` for
Range-capable delivery of the finished offline MP3; only its import path
updates.

The link between HLS and downloads is that both spawn ffmpeg processes
and must be tracked for graceful shutdown. That mechanism
(`registerFfmpegCommand` / `unregisterFfmpegCommand` /
`killAllActiveTranscodes`) lives in `trackFileResolver.ts` and is
imported by both services.

---

## 4. Client changes (Flutter)

### 4.1 `lib/services/audio_service.dart`

One URL change. `_sourceForTrack` currently builds:

```dart
'$_baseUrl/api/stream/${t.id}?bitrate=$_bitrate&token=$_accessToken'
```

Replace with:

```dart
'$_baseUrl/api/stream/${t.id}/playlist.m3u8?bitrate=$_bitrate&token=$_accessToken'
```

`AudioSource.uri(...)` with an `.m3u8` URL is recognized by libmpv, iOS
AVPlayer, and Android ExoPlayer as HLS automatically. No extra code.

### 4.2 `lib/ui/widgets/full_player.dart`

Remove the seek-bar snap-back workaround introduced on the current branch:
`_seekTarget`, `_seekReleaseTimer`, the 2 s catch-up tolerance, the 3 s
fallback timer. With HLS the audible seek lands within one segment fetch
(~100–300 ms), so the position stream catches up before the user can
perceive the bar moving. Restore the simpler `onChangeEnd: seekTo()` path
that was there before.

### 4.3 `lib/main.dart` and the vendored fork

- **Delete `bimusic_app/packages/just_audio_media_kit_patched/` entirely.**
  The patch existed only to flip `cache-on-disk` off. Under HLS there is
  no long-lived stream for the demuxer to aggressively cache, so the
  upstream default (`cache-on-disk: yes`) becomes harmless.
- Remove the `dependency_overrides: just_audio_media_kit:` block from
  `bimusic_app/pubspec.yaml`.
- Remove the `analyzer.exclude: packages/**` entry from
  `analysis_options.yaml`.
- In `main.dart` the `JustAudioMediaKit.bufferSize = 2 * 1024 * 1024` line
  can stay or revert — it doesn't matter for HLS. Suggest reverting (to
  upstream default) so we're not carrying magic numbers we don't need.

### 4.4 Nothing else

`player_provider.dart`, `download_provider.dart`, `BiMusicAudioHandler`
control surface, etc. all operate on the just_audio API. Switching the
underlying source from "one MP3 URL" to "an m3u8 URL" is invisible above
the AudioSource boundary.

---

## 5. Tests

### 5.1 Backend

- `backend/src/services/__tests__/hlsService.test.ts` (new):
  - `computeTrackKey` stability and per-bitrate differentiation.
  - `buildPlaylist` output — correct `EXTINF` durations, final segment
    length, `#EXT-X-ENDLIST`, token in URIs.
  - `generateSegment` dedup (two concurrent calls → one ffmpeg spawn) via
    the same `fluent-ffmpeg` mock pattern used today.
  - `ensureSegment` cache-hit path (no ffmpeg call when file exists).

- `backend/tests/integration/hls.test.ts` (new):
  - `GET /api/stream/:id/playlist.m3u8` — 200, correct `Content-Type`,
    correct segment count for a stubbed Lidarr track duration.
  - `GET /api/stream/:id/segment/000` — 200, `Content-Type: video/mp2t`,
    non-empty body (mock ffmpeg writes a fake TS payload).
  - Out-of-range index → 416 or 400.
  - Missing auth → 401 on both endpoints.

- Delete `streamService.test.ts` and the old `stream.test.ts` integration
  suite — they test code that no longer exists.

### 5.2 Flutter

Widget tests for `FullPlayer` need the `_seekTarget` / fallback-timer
assertions removed. No new widget tests needed — the URL change is
internal to `audio_service.dart` and is already exercised by the existing
`audio_service_test.dart` expectations on `queueFor`/`play` (the stream
URL isn't asserted on specifically; if it is, update the expected URL).

### 5.3 CI gates

Coverage thresholds (80 % backend / 70 % Flutter) are expected to hold
since the HLS service is smaller than the streaming plumbing it replaces
and is well-suited to unit testing (pure playlist builder, mockable
ffmpeg spawn). **Re-measure after step 3 of the rollout** rather than
assuming — if a gap appears, fill it with targeted unit tests on
`hlsService` before landing step 3. No CI config changes required.

---

## 6. Rollout order

Each step below is an independent commit (or small PR) on a fresh branch
`feat/hls-streaming` cut from `main`.

1. **Scaffold.** Add `HLS_CACHE_DIR` / `HLS_SEGMENT_SECONDS` to env;
   create `hlsService.ts` skeleton with `computeTrackKey`, `buildPlaylist`,
   `initHlsCacheDir`. Unit tests for the pure parts. No route changes yet.
2. **Segment generation.** Implement `generateSegment` + `ensureSegment`
   with dedup and ffmpeg-command tracking. Unit tests with mocked ffmpeg.
3. **Route rewrite.** Delete the old `/api/stream/:trackId` handler and
   the tee/passthrough plumbing in `streamService.ts`. Add the two new
   route handlers. Integration tests pass.
4. **Client switch.** Change the URL in `audio_service.dart`. Remove the
   snap-back workaround in `full_player.dart`. Run Flutter tests +
   `flutter analyze`. Smoke-test locally on Windows.
5. **Docs.** Update `CLAUDE.md` sections for Stream service, Audio
   handler, and the removed `TEMP_DIR` env var. Add an entry to
   `docs/architecture-decisions.md` recording the move to HLS.
6. **Remove the just_audio_media_kit fork** (if merging onto a branch that
   still has it). On a fresh branch from `main` this is a no-op.

---

## 7. Risks and open questions

- **MP3-in-TS compatibility.** libmpv and ExoPlayer handle it; iOS AVPlayer
  has historically preferred AAC-in-TS or fMP4. If iOS testing exposes a
  problem, switch the segment codec to AAC (`-c:a aac -b:a 128k`). Segment
  bit-rate semantics and the 128/320 dropdown continue to work; only the
  codec changes.
- **Token expiry mid-playback.** The playlist is built per request with
  the token that authenticated it; that same token is embedded into every
  segment URI. If playback spans a token lifetime, segment requests will
  401 and libmpv will stop. **Primary mitigation already exists:**
  `BiMusicAudioHandler.updateToken(newToken)` (`audio_service.dart`,
  introduced on `fix/token-refresh-audio-stream`) rebuilds the audio
  source on refresh, which under HLS means it requests a fresh
  `playlist.m3u8` with the new token — segments then carry the new token
  automatically. No protocol-level work needed. As a secondary belt-and-
  braces measure, bumping the access-token lifetime from 15 min toward
  1 h would eliminate the common case (tracks longer than the token
  lifetime are rare in music). Signed per-playback URLs remain a future
  option if cross-token playback ever becomes a real problem.
- **Seek precision.** HLS seeks land on segment boundaries, so a click at
  1:03.4 may actually begin playback at 1:00. Acceptable for music (±6 s
  is imperceptible for most use cases; users can nudge). If this becomes a
  complaint, reduce `HLS_SEGMENT_SECONDS` to 3 or 2 — trade playlist size
  for precision.
- **Offline cache invalidation.** If a user downloads segments for track
  X at 128 kbps and the source file is later replaced, the cached
  segments will serve the old audio. Same class of risk the existing temp
  cache has; the 24 h TTL is sufficient for now.
- **Per-segment ffmpeg spawn overhead (Option A).** On a severely
  underpowered server, 170 spawns over 17 minutes could add up. Not
  expected to matter in practice but keep an eye on it; Option B exists
  as a fallback.
