# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BiMusic is a self-hosted music streaming app with a **Node.js/TypeScript backend** (`backend/`) and a **Flutter client** (`bimusic_app/`). The backend integrates with Lidarr for music library management and uses FFmpeg for audio transcoding.

## Build & Development Commands

### Backend (`backend/`)

Node.js is managed via nvm and is **not on the default PATH**. Prefix all node/npm commands:

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use --lts
```

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
| Single test file | `npx vitest run path/to/file.test.ts` |
| Single test by name | `npx vitest run -t "test name pattern"` |

Copy `.env.example` to `.env` for local development. Requires `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET` (≥32 chars each).

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

- **Framework:** Express 5 with TypeScript strict mode
- **Database:** SQLite via `better-sqlite3` + Drizzle ORM. Schema in `src/db/schema.ts`, migrations in `src/db/migrations/`
- **Auth:** JWT with separate access/refresh secrets. Refresh tokens stored as HMAC-SHA256 hashes
- **Primary keys:** UUID TEXT via `lower(hex(randomblob(16)))` for all BiMusic tables; Lidarr IDs stay INTEGER
- **Logging:** Pino with structured JSON output to file
- **Lidarr client:** `src/services/lidarrClient.ts` — typed axios wrapper for all Lidarr API calls. Routes must call lidarrClient methods, never axios directly. Lidarr errors are mapped: 404 → 404 `NOT_FOUND`, 5xx → 502 `LIDARR_ERROR`, timeout → 504 `LIDARR_TIMEOUT`. Cover art methods return `AxiosResponse<Readable>` for pipe-through (no buffering). Lidarr types are in `src/types/lidarr.ts`.
- **Transcoding:** `fluent-ffmpeg` for audio format conversion; passthrough Range headers for MP3, temp-file transcoding for other formats
- **Validation:** Zod schemas for env config and request validation

**Request flow:** `index.ts` → boots migrations + admin user → `app.ts` mounts routes → route handlers call services → `lidarrClient` (Lidarr API) or Drizzle ORM (SQLite)

**Route prefixes:** `/api/health`, `/api/auth`, `/api/library`, `/api/stream`, `/api/offline`, `/api/admin`, `/api/users`

### Flutter Client

- **State management:** Riverpod (flutter_riverpod ^2.6, riverpod_annotation ^2.6, riverpod_generator ^2.6)
- **Audio:** just_audio ^0.9 + audio_service ^0.18 + audio_session ^0.1
- **Routing:** go_router ^14.6 — `StatefulShellRoute.indexedStack` with 6 branches; shell builder delegates to `AdaptiveScaffold`
- **Offline storage:** Isar 3.1.0 (pinned — 4.x not yet on pub.dev)
- **Background downloads:** flutter_background_service ^5.0
- **HTTP:** Dio ^5.7 with auth interceptor (future phase)
- **Code gen:** freezed ^2.5 + json_serializable ^6.8 + riverpod_generator. Run `dart run build_runner build --delete-conflicting-outputs` after model changes.
- **Theme:** Material 3, `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`, light + dark, `ThemeMode.system`
- **API config:** `lib/config/api_config.dart` — base URL via `--dart-define=API_BASE_URL=...` (default `http://localhost:3000`)

**Layout:** `AdaptiveScaffold` (`lib/ui/widgets/adaptive_scaffold.dart`) switches at 1024 px:
- `< 1024` → `MobileLayout` — 5-tab `NavigationBar` (Home/Library/Search/Playlists/Settings); Downloads tab omitted on mobile
- `≥ 1024` → `DesktopLayout` — 220 px fixed sidebar with all 6 nav items + 80 px bottom player bar

**Entry point:** `main.dart` wraps `ProviderScope(child: BiMusicApp())`. `BiMusicApp` lives in `lib/app.dart`.

### Testing

**Backend tests use Vitest** with two workspace projects:
- **Unit tests:** `src/**/__tests__/**/*.test.ts` — colocated with source. Mock env with `vi.mock('../../config/env.js', ...)`. Use `nock` to stub outbound HTTP (lidarrClient tests); use `vi.mock` for DB/logger.
- **Integration tests:** `tests/integration/**/*.test.ts` — use setup file, run in forked processes, 15s timeout

**Flutter tests:** `test/*_test.dart`

### CI Pipeline (`.github/workflows/ci.yml`)

Two jobs on push/PR to main:
1. `backend-lint` — npm ci → lint → type-check
2. `flutter-analyze` — pub get → build_runner → analyze

## Locked Architecture Decisions

These decisions are final and documented in `docs/architecture-decisions.md`. Do not re-litigate unless the user explicitly requests a design change.
