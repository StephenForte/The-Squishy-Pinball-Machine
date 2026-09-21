# Squish leaderboard server

Node 24 HTTP service for the shared leaderboard (D-026), cloud profiles (D-037),
CORS for a browser build (D-044), and admin cleanup (D-046).
Zero npm dependencies: `node:http` + `node:sqlite`. Schema and indexes are
created on boot. `scores` is never altered; `profiles` is added with
`CREATE TABLE IF NOT EXISTS`.

## Local run (memory mode)

T13's test runner uses this exact command:

```bash
DB_PATH=:memory: SQUISH_KEY=devkey PORT=8787 npm start
```

Then:

```bash
curl -s localhost:8787/healthz
```

## File database

```bash
DB_PATH=./squish.db SQUISH_KEY=devkey PORT=8787 npm start
```

`DB_PATH` must point at a file whose parent directory already exists. Production
(T11.1) uses `/var/data/squish.db` on the Render disk.

## Tests

```bash
npm test                         # in-memory
DB_PATH=/tmp/squish.db npm test  # same suite against a file DB
```

## Env

| Name | Default | Purpose |
|------|---------|---------|
| `PORT` | `8787` | Listen port (binds `0.0.0.0`) |
| `DB_PATH` | `:memory:` | SQLite file, or `:memory:` |
| `SQUISH_KEY` | (none) | Shared write key; required on `POST /v1/scores` and `PUT /v1/profile` as `X-Squish-Key` |
| `SQUISH_ALLOWED_ORIGINS` | (empty) | Comma-separated exact origins for CORS (D-044). Empty = no CORS headers. `*` is never a wildcard. |
| `SQUISH_ADMIN_KEY` | (empty) | Admin key for cleanup routes as `X-Squish-Admin` (D-046). Empty **disables** every admin route (404). |

See `.env.example`. Do not commit `.env`.

## CORS (D-044)

Fail closed. A request whose `Origin` is on `SQUISH_ALLOWED_ORIGINS` gets that
exact origin echoed in `Access-Control-Allow-Origin` plus `Vary: Origin`.
Allowed methods/headers are the ones the client uses: `GET`, `POST`, `PUT` and
`Content-Type`, `X-Squish-Key`. An unlisted origin, a missing origin, or `*` in
the env var produces no CORS header. `OPTIONS` on the public routes answers
`204` with the same allowlist. Admin routes never send CORS headers and do not
answer a preflight.

## Rate limits

- Per `player_id`: 30 writes / 60 s on `POST /v1/scores` and `PUT /v1/profile` (D-026).
- Per IP: 60 writes / 60 s on the same two routes (D-046). Address is the
  left-most `X-Forwarded-For` entry when present, otherwise the socket;
  a missing address shares one `unknown` bucket. This is a speed bump, not
  authorization — `X-Forwarded-For` is client-controlled on a direct connection.

## Routes (D-026, amended by D-037, D-044, D-046)

- `GET /` → HTML top-10 board (same data as `/v1/leaderboard`; `Cache-Control: no-store`). Each row's avatar is a same-origin `<img src="/avatars/<id>.png">` when set.
- `GET /healthz` → `{ ok, store }` (`memory` when `DB_PATH=:memory:`, otherwise `sqlite`)
- `POST /v1/scores` → `201` `{ rank, best, is_personal_best, total_players }`
- `GET /v1/leaderboard?limit=10` → `{ entries, total_players }` (limit 1..50). Each entry includes `avatar` (`""` when the player has no profile).
- `GET /v1/leaderboard/me?player_id=<uuid>` → `{ rank, best, name, avatar }` or `404`
- `PUT /v1/profile` → `200` `{ player_id, name, avatar, updated_at }` (key + limiter, same 30/min per `player_id` as scores). `avatar` is `""` or a D-020 catalog id.
- `GET /v1/profile?player_id=<uuid>` → the same object, or `404` `unknown_profile`. No key.
- `GET /avatars/<id>.png` → catalogued art only (`image/png`, `Cache-Control: public, max-age=86400`). The id is looked up in `assets/design/squishes/squishies_catalog.json`; the file path comes from that entry, never from the URL segment. PNGs stay in the repo — they are not copied into `server/`.

- `OPTIONS` on the public routes above → `204` when CORS applies (or without CORS headers for an unlisted origin).
- `DELETE /v1/scores/:id` → `200` `{ ok: true }` (admin). `404` if the row does not exist.
- `DELETE /v1/profile/:player_id` → `200` `{ ok: true }` (admin). `404` unknown; `400` `invalid_player_id` for a malformed uuid. Scores for that player stay.
- `POST /v1/admin/reset` → `200` `{ ok: true }` (admin). Body must include `"confirm":"RESET"` or the request is `400` `confirmation_required` and nothing is deleted.

Admin routes require `X-Squish-Admin` matching `SQUISH_ADMIN_KEY` (timing-safe, same as the write key). The write key does not grant admin. A blank `SQUISH_ADMIN_KEY` makes every admin path `404` `not_found`, indistinguishable from an unknown route.

If the catalog or art directory is missing the server still boots, logs once, serves the board without avatars, and rejects non-empty avatars as `invalid_avatar`.

<!-- deploy probe 2026-09-09T03:10Z: this line exists to test Render auto-deploy on server/** -->
<!-- deploy probe 2 2026-09-09T18:53Z: after repo reconnect -->
