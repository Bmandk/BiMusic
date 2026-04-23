# CE Code Review Run Artifact
**Run ID:** 20260423-190149-3c85e097  
**Branch:** feat/hls-streaming → main  
**Date:** 2026-04-23  
**Reviewers:** 12 (correctness, testing, maintainability, project-standards, agent-native, learnings, security, performance, api-contract, reliability, adversarial, kieran-typescript)

## Applied Fixes — safe_auto (Stage 5)

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| 1 | `libraryService.ts` | 57 | `streamUrl` pointed to deleted `/api/stream/:id` endpoint | Changed to `/api/stream/:id/playlist` |
| 2 | `env.ts` | 45 | `HLS_SEGMENT_SECONDS` accepted floats | Added `.int().positive()` to Zod chain |
| 3 | `hlsService.ts` | 64 | `#EXT-X-TARGETDURATION` emitted float value (HLS spec violation) | Wrapped in `Math.ceil()` |
| 4 | `trackFileResolver.ts` | 25 | `lidarrRootPromise` not cleared on rejection → permanent cache poison | Added `.catch()` that clears `lidarrRootPromise = null` |
| 5 | `env.test.ts` | 21 | Phantom `TEMP_DIR` field; `HLS_CACHE_DIR`/`HLS_SEGMENT_SECONDS` missing | Replaced with correct fields |
| 6 | `stream.ts` | 167 | `statSync` ENOENT thrown as unhandled 500 | Wrapped in try/catch → 404 `NOT_FOUND` |

## Applied Fixes — P1 interactive (user requested all P1s)

| # | File | What changed |
|---|------|-------------|
| R2 | `hlsService.ts` | Added `MAX_CONCURRENT_TRANSCODES=4` semaphore (`acquireTranscodeSlot`/`releaseTranscodeSlot`) in `generateSegment` |
| R3 | `hlsService.ts` | Added `SEGMENT_TRANSCODE_TIMEOUT_MS=60_000` — `setTimeout` kills cmd and rejects if ffmpeg exceeds 60s |
| R4 | `hlsService.ts` | `startHlsCacheCleanup` now checks `MAX_CACHE_DIRS=500` and LRU-evicts oldest dirs after age-based eviction; both eviction paths skip dirs with in-flight segments |
| R1 | `stream.ts` | Replaced blocking `statSync` import with `stat` from `fs/promises`; segment handler now awaits `stat()` |
| R5 | `stream.ts` | Added `express-rate-limit` (already in deps): 300 req/min/IP on all stream routes |
| R11 | `stream.ts` | `extractToken()` helper: `?token=` query param preferred, falls back to `Authorization: Bearer` header so playlist auth embeds a non-empty token in all segment URIs |
| R6 | `hlsService.test.ts` (unit) | 5 new `describe("buildPlaylist — startSegment")` tests |
| R6 | `hls.test.ts` (integration) | 5 new `startSegment` integration tests covering first-URI, MEDIA-SEQUENCE, segment count, out-of-range, negative |
| R7 | `health.ts` | Exposed `segmentSeconds: env.HLS_SEGMENT_SECONDS` in health response; Flutter `_segmentDuration` comment updated to reference `/api/health` endpoint |
| R8 | `hls.test.ts` (integration) | 4 new token-via-query-param auth tests on both playlist and segment endpoints |
| R9/R10 | `hls_seek_utils.dart` (new) | Extracted `computeHlsSeekTarget` and `matchHlsUriToQueueIndex` as pure top-level functions |
| R9/R10 | `audio_service.dart` | `_matchUriToQueueIndex` and `seekTo` now delegate to the extracted utils; `_trackIdPattern` removed |
| R9/R10 | `hls_seek_utils_test.dart` (new) | 13 unit tests covering seek math edge cases and URI matching false-positive prevention |
| — | `libraryService.test.ts` | Updated `streamUrl` assertions to match `/playlist` suffix |

## Residual Work (P2 and advisory — not yet fixed)

| ID | File | Title | autofix_class |
|----|------|-------|---------------|
| R12 | `trackFileResolver.ts:52` | `remapPath` no boundary check — potential path traversal | `gated_auto` |
| R13 | `hlsService.ts` | Hourly cleanup uses synchronous FS in `setInterval` | `gated_auto` |
| R14 | `hlsService.ts` | Cleanup race with active ffmpeg writes (partially mitigated — in-flight check added) | `gated_auto` |
| R15 | `stream.ts` | Validation errors bypass `createError+next` pattern | `gated_auto` |
| R16 | `audio_service.dart:245` | `debugPrint` calls — zero production observability | `manual` |
| R17 | `audio_service.dart:~210` | Three parallel mutable lists fragile to partial update | `manual` |
| R7 | `audio_service.dart`, `backend_config_provider.dart`, `player_provider.dart` | `_segmentDuration` fully dynamic — `backendConfigProvider` fetches from `/api/health`, passed via `playQueue(segmentSeconds:)` | ✅ fixed |

## Advisory

| ID | Note |
|----|------|
| A1 | `ffmpeg -output_ts_offset` not implemented — potential PTS discontinuity at segment joins |
| A2 | OGG Vorbis sources: quadratic seek cost per segment |
| A3 | `audio_service.dart` has `// coverage:ignore-file` — audio backend still excluded from coverage |
