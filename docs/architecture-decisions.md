# BiMusic Cross-Plan Conflict Resolutions

This document records the authoritative decisions for every conflict found across the five planning documents (architecture, backend, flutter-client, UX, QA/test-strategy). All plans must align with these decisions. The architecture plan (`docs/architecture-plan.md`) has been updated to reflect all decisions below.

---

## 1. Logging Library: pino (not winston)

**Conflict:** Architecture plan specifies `pino`. Backend plan specifies `winston` with `DailyRotateFile`.

**Decision: Use `pino`.**

**Rationale:** pino is faster, outputs structured JSON natively, and has fewer dependencies. Log rotation is handled by OS-level `logrotate`, keeping the Node process simpler.

**What changes:**
- Backend plan: replace all winston references with pino
- Backend plan: remove `DailyRotateFile` transport, use `pino/file` transport
- Test strategy: logging tests validate pino JSON output format

---

## 2. JWT Secrets: Two Separate Secrets (not one)

**Conflict:** Architecture plan originally used one `JWT_SECRET`. Backend plan uses two (`JWT_ACCESS_SECRET` + `JWT_REFRESH_SECRET`).

**Decision: Use two separate secrets for security isolation.**

- `JWT_ACCESS_SECRET` -- signs access tokens (HS256)
- `JWT_REFRESH_SECRET` -- used as HMAC key when hashing refresh tokens

**Rationale:** If one secret is compromised, the other token type is not affected. Better security isolation with minimal config overhead.

**What changes:**
- Architecture plan: updated to two secrets
- Backend plan: keep two-secret approach (already correct)
- .env template: `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET`

---

## 3. Primary Key Types: UUID TEXT PKs (not INTEGER AUTOINCREMENT)

**Conflict:** Architecture plan originally used `TEXT` UUIDs. Backend plan uses `INTEGER AUTOINCREMENT`.

**Decision: Use UUID TEXT PKs (`lower(hex(randomblob(16)))`) for all BiMusic-owned tables.** Lidarr IDs (track, album, artist) remain integers as they come from Lidarr.

**Rationale:** UUIDs are non-guessable (avoids IDOR if an endpoint is accidentally unprotected) and decouple identity from insertion order. Performance difference is negligible at this scale.

**What changes:**
- Architecture plan: updated -- all BiMusic table PKs use TEXT UUIDs
- Backend plan: change all `INTEGER PRIMARY KEY AUTOINCREMENT` to `TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16))))`
- Backend plan: foreign keys referencing BiMusic tables use TEXT type

---

## 4. Refresh Token Hashing: SHA-256 Hash in DB (never raw)

**Conflict:** Architecture plan stores SHA-256 hash. Backend plan stores raw token.

**Decision: Store SHA-256 hash of the opaque token in the DB. Never store the raw token.**

**Rationale:** If the database is compromised, hashed tokens cannot be used directly. The `JWT_REFRESH_SECRET` is used as an HMAC key for the hash, adding keyed hashing on top.

**Implementation:**
```
Client receives:  <64-byte random hex string>
DB stores:        HMAC-SHA256(JWT_REFRESH_SECRET, <token>)
On refresh:       HMAC-SHA256(JWT_REFRESH_SECRET, incoming_token) → lookup in DB
```

**What changes:**
- Backend plan: change `refresh_tokens.token` to `token_hash TEXT UNIQUE NOT NULL`
- Backend plan: update auth service to hash tokens before DB operations

---

## 5. Seek Support: Temp-File Transcoding with HTTP Range Headers

**Conflict:** Architecture plan originally said "no seek support". Backend plan proposed approximate seeking via `-ss`. UX plan has a draggable progress bar.

**Decision: Transcode to a named temp file, then serve with HTTP Range headers for full seek support.**

**Implementation:**
- **Passthrough** (source is MP3 at/below requested bitrate): serve file directly with standard HTTP Range headers. Full seek.
- **Transcoding needed**: transcode to `/tmp/bimusic/<hash>.mp3` (named by hash of source path + bitrate), then serve the temp file with HTTP Range headers. Brief initial delay on first request, but full seek support.
- Temp files cached for reuse; auto-cleaned after 24 hours; cleared on server startup.

**Rationale:** Users expect to seek within tracks (UX has progress bar). Piping ffmpeg output directly to the response prevents seeking. Temp files add a small delay but deliver a proper music player experience.

**What changes:**
- Architecture plan: updated streaming pipeline section
- Backend plan: implement temp-file transcoding in streamService
- Backend plan: add temp cleanup task (hourly, 24h expiry)

---

## 6. Health Check Endpoint: `GET /api/health`

**Previously missing from all plans.**

**Decision: Add `GET /api/health`.**

```
GET /api/health
Auth: None
Response 200: { "status": "ok", "version": "1.0.0" }
```

No auth required. Used by reverse proxy health checks and monitoring.

**What changes:**
- Architecture plan: added to endpoint table
- Backend plan: add health route

---

## 7. `GET /api/auth/me`: Returns JWT Payload Fields

**Present in architecture plan, missing from backend plan.**

**Decision: Include `GET /api/auth/me`. Returns `{ id, username, isAdmin }` extracted from the JWT payload.**

**Rationale:** Used by the Flutter client on app resume after restoring tokens from secure storage. Avoids encoding the full user profile in the JWT.

**What changes:**
- Backend plan: add `GET /api/auth/me` route that reads from `req.user` (JWT payload)

---

## 8. Pending Requests: New `requests` Table + `GET /api/requests`

**Previously missing. UX plan has a Pending Requests screen but no API or schema existed.**

**Decision: Add a `requests` table and `GET /api/requests` endpoint.**

**Schema:**
```sql
CREATE TABLE requests (
  id           TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type         TEXT NOT NULL,            -- 'artist' or 'album'
  lidarr_id    INTEGER NOT NULL,         -- Lidarr artist/album ID after adding
  name         TEXT NOT NULL,
  cover_url    TEXT,
  requested_at TEXT NOT NULL DEFAULT (datetime('now')),
  status       TEXT NOT NULL DEFAULT 'pending'  -- pending | downloading | available
);
```

**Endpoints:**
- `GET /api/requests` -- list current user's requests, enriched with live Lidarr status
- `POST /api/requests/artist` -- creates request row + adds artist to Lidarr
- `POST /api/requests/album` -- creates request row + monitors album in Lidarr

**What changes:**
- Architecture plan: added `requests` table (section 4.5) and updated endpoint table
- Backend plan: add requests table, route, and lidarrClient methods for queue/wanted
- Flutter client plan: add requests status screen/section

---

## 9. Device ID for Offline Downloads: Confirmed

**Already in architecture plan's schema. Confirming the API contract explicitly.**

- `POST /api/downloads` body must include `deviceId: string`
- `GET /api/downloads` requires `?deviceId=` query parameter to filter
- `device_id` is a client-generated stable identifier stored in secure storage on first launch

**What changes:** Architecture plan updated to make deviceId explicit in endpoint descriptions. No schema changes needed.

---

## 10. Background Download Package: `flutter_background_service` (not `workmanager`)

**Conflict:** Architecture plan specified `workmanager`. Flutter dev chose `flutter_background_service`.

**Decision: Use `flutter_background_service`.**

**Rationale:** `flutter_background_service` is designed for continuous background work (like active downloads). `workmanager` is better for deferred/scheduled tasks. Since downloads are long-running continuous operations, `flutter_background_service` is the better fit.

**What changes:**
- Architecture plan: updated to reference `flutter_background_service`
- Flutter client plan: already uses `flutter_background_service` (correct)

---

## Summary Table

| # | Topic | Decision |
|---|-------|----------|
| 1 | Logging library | pino (not winston) |
| 2 | JWT secrets | Two secrets: `JWT_ACCESS_SECRET` + `JWT_REFRESH_SECRET` |
| 3 | Primary keys | UUID TEXT PKs for BiMusic tables; Lidarr IDs stay integer |
| 4 | Refresh token storage | SHA-256 hash (HMAC-keyed), never raw |
| 5 | Seek support | Temp-file transcoding + HTTP Range headers |
| 6 | Health endpoint | `GET /api/health` (no auth) |
| 7 | `/auth/me` | Returns `{ id, username, isAdmin }` from JWT payload |
| 8 | Pending requests | New `requests` table + `GET /api/requests` |
| 9 | Device ID | `deviceId` required in download POST body and GET query |
| 10 | Background downloads | `flutter_background_service` (not `workmanager`) |
