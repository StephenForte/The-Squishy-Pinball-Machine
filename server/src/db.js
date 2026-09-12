import { existsSync, statSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

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
      updated_at text not null
    )
  `);
  return db;
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
  const previousBest = playerBest(db, player_id);
  const created_at = new Date().toISOString();
  db.prepare(
    'INSERT INTO scores (player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?)',
  ).run(player_id, name, score, client, created_at);

  const best = previousBest === null ? score : Math.max(previousBest, score);
  const is_personal_best = previousBest === null || score > previousBest;
  const { rank, total_players } = playerStanding(db, player_id);
  return { rank, best, is_personal_best, total_players };
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
  const updated_at = new Date().toISOString();
  db.prepare(
    `
    INSERT INTO profiles (player_id, name, avatar, updated_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(player_id) DO UPDATE SET
      name = excluded.name,
      avatar = excluded.avatar,
      updated_at = excluded.updated_at
  `,
  ).run(player_id, name, avatar, updated_at);
  return getProfile(db, player_id);
}
