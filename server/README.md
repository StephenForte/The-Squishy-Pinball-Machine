# Squish leaderboard server

Node 24 HTTP service for the shared leaderboard (D-026). Zero npm dependencies:
`node:http` + `node:sqlite`. Schema and index are created on boot.

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
| `SQUISH_KEY` | (none) | Shared write key; required on `POST /v1/scores` as `X-Squish-Key` |

See `.env.example`. Do not commit `.env`.

## Routes (D-026)

- `GET /healthz` → `{ ok, store }` (`memory` when `DB_PATH=:memory:`, otherwise `sqlite`)
- `POST /v1/scores` → `201` `{ rank, best, is_personal_best, total_players }`
- `GET /v1/leaderboard?limit=10` → `{ entries, total_players }` (limit 1..50)
- `GET /v1/leaderboard/me?player_id=<uuid>` → `{ rank, best, name }` or `404`
