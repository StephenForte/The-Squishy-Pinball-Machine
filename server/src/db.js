import { randomUUID } from 'node:crypto';
import { existsSync, statSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { nameKey } from './validate.js';

export function storeLabel(dbPath) {
  return dbPath === ':memory:' ? 'memory' : 'sqlite';
}

export function openDb(dbPath) {
  if (dbPath !== ':memory:') {
    const dir = dirname(dbPath);
    if (dir && dir !== '.') {
      if (!existsSync(dir)) {
        throw new Error(
          `DB_PATH directory does not exist: ${dir}. Create the mount or directory before starting.`,
        );
      }
      if (!statSync(dir).isDirectory()) {
        throw new Error(`DB_PATH parent is not a directory: ${dir}`);
      }
    }
  }

  const db = new DatabaseSync(dbPath);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec(`
    CREATE TABLE IF NOT EXISTS scores (
      id integer primary key,
      player_id text not null,
      name text not null,
      score integer not null,
      client text,
      created_at text not null
    )
  `);
  db.exec(
    'CREATE INDEX IF NOT EXISTS scores_player_score ON scores (player_id, score DESC)',
  );
  db.exec(`
    CREATE TABLE IF NOT EXISTS profiles (
      player_id text primary key,
      name text not null,
      avatar text not null default '',
      updated_at text not null,
      name_key text not null default ''
    )
  `);
  // Existing databases were created without name_key. CREATE TABLE IF NOT EXISTS
  // will not add it, and a UNIQUE index built while duplicate names are still
  // stored would throw here and take the whole service down.
  migrateProfiles(db);
  return db;
}

function nameTaken() {
  const err = new Error('name_taken');
  err.code = 'name_taken';
  return err;
}

function rethrowConstraint(err) {
  const message = err && typeof err.message === 'string' ? err.message : '';
  if (message.includes('UNIQUE constraint failed')) throw nameTaken();
  throw err;
}

function withImmediate(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const value = fn();
    db.exec('COMMIT');
    return value;
  } catch (err) {
    try {
      db.exec('ROLLBACK');
    } catch {
      // already closed or not in a transaction
    }
    rethrowConstraint(err);
  }
}

/**
 * Add name_key to a pre-change profiles table, backfill it, and install the
 * unique index only when every key is already unique. Duplicate rows are left
 * in place for an explicit merge; startup must still succeed.
 */
function migrateProfiles(db) {
  const cols = db.prepare('PRAGMA table_info(profiles)').all();
  if (!cols.some((col) => col.name === 'name_key')) {
    db.exec(`ALTER TABLE profiles ADD COLUMN name_key TEXT NOT NULL DEFAULT ''`);
  }
  const rows = db.prepare('SELECT player_id, name, name_key FROM profiles').all();
  const update = db.prepare('UPDATE profiles SET name_key = ? WHERE player_id = ?');
  for (const row of rows) {
    const key = nameKey(row.name);
    if (row.name_key !== key) update.run(key, row.player_id);
  }
  ensureUniqueNameIndex(db, { log: true });
}

function duplicateNameKeys(db) {
  return db
    .prepare(
      `
      SELECT name_key FROM profiles
      WHERE name_key != ''
      GROUP BY name_key
      HAVING COUNT(*) > 1
    `,
    )
    .all();
}

function ensureUniqueNameIndex(db, { log = false } = {}) {
  const dupes = duplicateNameKeys(db);
  if (dupes.length > 0) {
    if (log) {
      console.error(
        `profiles name_key not unique (${dupes.length} key${dupes.length === 1 ? '' : 's'}); serving without the unique index until they are merged`,
      );
    }
    return false;
  }
  db.exec(
    `CREATE UNIQUE INDEX IF NOT EXISTS profiles_name_key ON profiles (name_key) WHERE name_key != ''`,
  );
  return true;
}

function latestScoreName(db, playerId) {
  const row = db
    .prepare(
      `
      SELECT name FROM scores
      WHERE player_id = ?
      ORDER BY created_at DESC, id DESC
      LIMIT 1
    `,
    )
    .get(playerId);
  return row ? row.name : null;
}

/**
 * A player holds a name while their profile key matches, or any of their
 * score rows still carries it. The board shows only the latest score name;
 * older rows keep the name reserved so a second player cannot take it.
 */
function holdersOf(db, key) {
  const ids = new Set();
  const profiles = db
    .prepare('SELECT player_id FROM profiles WHERE name_key = ?')
    .all(key);
  for (const row of profiles) ids.add(row.player_id);
  const scores = db.prepare('SELECT player_id, name FROM scores').all();
  for (const row of scores) {
    if (nameKey(row.name) === key) ids.add(row.player_id);
  }
  return [...ids];
}

function holdsName(db, playerId, key) {
  const profile = db
    .prepare('SELECT name_key FROM profiles WHERE player_id = ?')
    .get(playerId);
  if (profile && profile.name_key === key) return true;
  const scores = db.prepare('SELECT name FROM scores WHERE player_id = ?').all(playerId);
  return scores.some((row) => nameKey(row.name) === key);
}

function playerExists(db, playerId) {
  const profile = db
    .prepare('SELECT 1 AS ok FROM profiles WHERE player_id = ?')
    .get(playerId);
  if (profile) return true;
  const score = db
    .prepare('SELECT 1 AS ok FROM scores WHERE player_id = ?')
    .get(playerId);
  return Boolean(score);
}

export function closeDb(db) {
  db.close();
}

export function playerBest(db, playerId) {
  const row = db
    .prepare('SELECT MAX(score) AS best FROM scores WHERE player_id = ?')
    .get(playerId);
  return row?.best ?? null;
}

export function insertScore(db, { player_id, name, score, client }) {
  const key = nameKey(name);
  return withImmediate(db, () => {
    if (!holdsName(db, player_id, key) && holdersOf(db, key).length > 0) {
      throw nameTaken();
    }
    const previousBest = playerBest(db, player_id);
    const created_at = new Date().toISOString();
    db.prepare(
      'INSERT INTO scores (player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?)',
    ).run(player_id, name, score, client, created_at);

    const best = previousBest === null ? score : Math.max(previousBest, score);
    const is_personal_best = previousBest === null || score > previousBest;
    const { rank, total_players } = playerStanding(db, player_id);
    return { rank, best, is_personal_best, total_players };
  });
}

/**
 * One row per player: best score (earliest created_at of that best) joined
 * with the player's latest name — those come from different rows.
 * Avatar is a LEFT JOIN on profiles after that; it must not replace the name.
 */
function boardRows(db) {
  return db
    .prepare(
      `
      SELECT
        b.player_id,
        (
          SELECT s.name
          FROM scores s
          WHERE s.player_id = b.player_id
          ORDER BY s.created_at DESC, s.id DESC
          LIMIT 1
        ) AS name,
        b.score,
        b.at,
        COALESCE(p.avatar, '') AS avatar
      FROM (
        SELECT s.player_id, s.score, MIN(s.created_at) AS at
        FROM scores s
        INNER JOIN (
          SELECT player_id, MAX(score) AS best
          FROM scores
          GROUP BY player_id
        ) m ON m.player_id = s.player_id AND s.score = m.best
        GROUP BY s.player_id, s.score
      ) b
      LEFT JOIN profiles p ON p.player_id = b.player_id
      ORDER BY b.score DESC, b.at ASC, b.player_id ASC
    `,
    )
    .all();
}

function withRanks(rows) {
  return rows.map((row) => ({
    rank: rows.filter((other) => other.score > row.score).length + 1,
    player_id: row.player_id,
    name: row.name,
    score: row.score,
    at: row.at,
    avatar: row.avatar ?? '',
  }));
}

function playerStanding(db, playerId) {
  const ranked = withRanks(boardRows(db));
  const mine = ranked.find((row) => row.player_id === playerId);
  return {
    rank: mine ? mine.rank : null,
    total_players: ranked.length,
  };
}

export function getLeaderboard(db, limit) {
  const ranked = withRanks(boardRows(db));
  return {
    entries: ranked.slice(0, limit).map((row) => ({
      rank: row.rank,
      player_id: row.player_id,
      name: row.name,
      score: row.score,
      at: row.at,
      avatar: row.avatar,
    })),
    total_players: ranked.length,
  };
}

export function getMe(db, playerId) {
  const ranked = withRanks(boardRows(db));
  const mine = ranked.find((row) => row.player_id === playerId);
  if (!mine) return null;
  return { rank: mine.rank, best: mine.score, name: mine.name, avatar: mine.avatar };
}

export function getProfile(db, playerId) {
  const row = db
    .prepare(
      'SELECT player_id, name, avatar, updated_at FROM profiles WHERE player_id = ?',
    )
    .get(playerId);
  if (!row) return null;
  return {
    player_id: row.player_id,
    name: row.name,
    avatar: row.avatar,
    updated_at: row.updated_at,
  };
}

export function upsertProfile(db, { player_id, name, avatar }) {
  const key = nameKey(name);
  return withImmediate(db, () => {
    if (!holdsName(db, player_id, key) && holdersOf(db, key).length > 0) {
      throw nameTaken();
    }
    const updated_at = new Date().toISOString();
    db.prepare(
      `
      INSERT INTO profiles (player_id, name, avatar, updated_at, name_key)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(player_id) DO UPDATE SET
        name = excluded.name,
        avatar = excluded.avatar,
        updated_at = excluded.updated_at,
        name_key = excluded.name_key
    `,
    ).run(player_id, name, avatar, updated_at, key);
    return getProfile(db, player_id);
  });
}

/**
 * Resolve a normalized name to its one player, or claim it.
 * More than one current holder is ambiguous — the caller must merge, not guess.
 */
export function resolvePlayer(db, name) {
  const display = name;
  const key = nameKey(name);
  return withImmediate(db, () => {
    const holders = holdersOf(db, key);
    if (holders.length > 1) {
      return { ok: false, status: 409, error: 'name_ambiguous' };
    }
    if (holders.length === 1) {
      const player_id = holders[0];
      let profile = getProfile(db, player_id);
      if (!profile) {
        const stored = latestScoreName(db, player_id) || display;
        const updated_at = new Date().toISOString();
        db.prepare(
          `
          INSERT INTO profiles (player_id, name, avatar, updated_at, name_key)
          VALUES (?, ?, '', ?, ?)
        `,
        ).run(player_id, stored, updated_at, nameKey(stored));
        profile = getProfile(db, player_id);
        ensureUniqueNameIndex(db);
      }
      return { ok: true, status: 200, created: false, profile };
    }
    const player_id = randomUUID();
    const updated_at = new Date().toISOString();
    db.prepare(
      `
      INSERT INTO profiles (player_id, name, avatar, updated_at, name_key)
      VALUES (?, ?, '', ?, ?)
    `,
    ).run(player_id, display, updated_at, key);
    ensureUniqueNameIndex(db);
    return { ok: true, status: 201, created: true, profile: getProfile(db, player_id) };
  });
}

/**
 * Read-only "is this name held?" (D-059).
 * Same holder rule as resolvePlayer (profile name_key or any score row).
 * Display is that holder's profile name, otherwise its latest score name.
 * Two or more holders are held, with no single display — the claim still
 * gets resolve's 409 name_ambiguous.
 * This function must not insert a profile, rebuild profiles_name_key, or
 * change a score. resolvePlayer's score-only branch writes a profile;
 * this one only reads.
 */
export function lookupPlayer(db, name) {
  const key = nameKey(name);
  const holders = holdersOf(db, key);
  if (holders.length === 0) {
    return { held: false };
  }
  if (holders.length > 1) {
    return { held: true };
  }
  const player_id = holders[0];
  const profile = getProfile(db, player_id);
  if (profile) {
    return { held: true, name: profile.name };
  }
  const stored = latestScoreName(db, player_id);
  return { held: true, name: stored || name };
}

/**
 * Absorb `drop` into `keep`. Survivor profile fields stay as they are.
 * Moved score rows take the survivor's display name so the board, which reads
 * scores.name, cannot keep showing the merged-away player.
 */
export function mergePlayers(db, { keep, drop }) {
  return withImmediate(db, () => {
    if (!playerExists(db, keep) || !playerExists(db, drop)) {
      return { ok: false, status: 404, error: 'not_found' };
    }
    const keepProfile = db
      .prepare('SELECT player_id, name, avatar, updated_at FROM profiles WHERE player_id = ?')
      .get(keep);
    const canonical =
      keepProfile?.name || latestScoreName(db, keep) || latestScoreName(db, drop);
    if (!canonical) {
      return { ok: false, status: 404, error: 'not_found' };
    }

    db.prepare('DELETE FROM profiles WHERE player_id = ?').run(drop);
    if (!keepProfile) {
      const updated_at = new Date().toISOString();
      db.prepare(
        `
        INSERT INTO profiles (player_id, name, avatar, updated_at, name_key)
        VALUES (?, ?, '', ?, ?)
      `,
      ).run(keep, canonical, updated_at, nameKey(canonical));
    }
    db.prepare('UPDATE scores SET player_id = ?, name = ? WHERE player_id = ?').run(
      keep,
      canonical,
      drop,
    );
    ensureUniqueNameIndex(db);
    return { ok: true };
  });
}

/**
 * Raw score rows, newest first (created_at then id). `total` is the matching
 * row count, not the page size — deletion targets a row, not a board entry.
 */
export function listScores(db, { playerId = null, limit } = {}) {
  const count = playerId
    ? db.prepare('SELECT COUNT(*) AS total FROM scores WHERE player_id = ?').get(playerId)
    : db.prepare('SELECT COUNT(*) AS total FROM scores').get();
  const stmt = playerId
    ? db.prepare(
        `
        SELECT id, player_id, name, score, client, created_at
        FROM scores
        WHERE player_id = ?
        ORDER BY created_at DESC, id DESC
        LIMIT ?
      `,
      )
    : db.prepare(
        `
        SELECT id, player_id, name, score, client, created_at
        FROM scores
        ORDER BY created_at DESC, id DESC
        LIMIT ?
      `,
      );
  const raw = playerId ? stmt.all(playerId, limit) : stmt.all(limit);
  return {
    rows: raw.map((row) => ({
      id: Number(row.id),
      player_id: row.player_id,
      name: row.name,
      score: Number(row.score),
      client: row.client,
      created_at: row.created_at,
    })),
    total: Number(count.total),
  };
}

export function deleteScore(db, id) {
  const row = db.prepare('SELECT id FROM scores WHERE id = ?').get(id);
  if (!row) return false;
  db.prepare('DELETE FROM scores WHERE id = ?').run(id);
  return true;
}

export function deleteProfile(db, playerId) {
  const row = db
    .prepare('SELECT player_id FROM profiles WHERE player_id = ?')
    .get(playerId);
  if (!row) return false;
  db.prepare('DELETE FROM profiles WHERE player_id = ?').run(playerId);
  return true;
}

export function resetAll(db) {
  db.exec('DELETE FROM scores');
  db.exec('DELETE FROM profiles');
}
