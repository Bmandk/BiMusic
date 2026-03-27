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
- **Transcoding:** `fluent-ffmpeg` for audio format conversion; passthrough Range headers for MP3, temp-file transcoding for other formats
- **Validation:** Zod schemas for env config and request validation

**Request flow:** `index.ts` → boots migrations + admin user → `app.ts` mounts routes → route handlers call services → services use Drizzle ORM

**Route prefixes:** `/api/health`, `/api/auth`, `/api/library`, `/api/stream`, `/api/offline`, `/api/admin`, `/api/users`

### Flutter Client

- **State management:** Riverpod
- **Audio:** just_audio + audio_service
- **Routing:** go_router
- **Offline storage:** Isar local DB
- **Background downloads:** flutter_background_service

Currently in early scaffold stage (basic Material app).

### Testing

**Backend tests use Vitest** with two workspace projects:
- **Unit tests:** `src/**/__tests__/**/*.test.ts` — colocated with source
- **Integration tests:** `tests/integration/**/*.test.ts` — use setup file, run in forked processes, 15s timeout

**Flutter tests:** `test/*_test.dart`

### CI Pipeline (`.github/workflows/ci.yml`)

Two jobs on push/PR to main:
1. `backend-lint` — npm ci → lint → type-check
2. `flutter-analyze` — pub get → build_runner → analyze

## Locked Architecture Decisions

These decisions are final and documented in `docs/architecture-decisions.md`. Do not re-litigate unless the user explicitly requests a design change.
