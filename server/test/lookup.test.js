import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { describe, it } from 'node:test';
import { createRateLimiter } from '../src/index.js';
import { request, withServer } from './helpers.js';

const KEY = 'devkey';
const GHOST = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const DAD_A = 'b8aa808f-6d01-439e-87be-664baf0ead85';
const DAD_B = '86f2ea8f-40ab-4141-8411-0db7c837bc47';

const SCORES_SQL = `
  CREATE TABLE scores (
    id integer primary key,
    player_id text not null,
    name text not null,
    score integer not null,
    client text,
    created_at text not null
  )
`;

function lookupPath(name) {
  return `/v1/players/lookup?name=${encodeURIComponent(name)}`;
}

function snapshot(path) {
  const db = new DatabaseSync(path, { readOnly: true });
  try {
    const profiles = db
      .prepare(
        'SELECT player_id, name, avatar, updated_at, name_key FROM profiles ORDER BY player_id',
      )
      .all();
    const scores = db
      .prepare(
        'SELECT id, player_id, name, score, client, created_at FROM scores ORDER BY id',
      )
      .all();
    const index = db
      .prepare(
        `SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'profiles_name_key'`,
      )
      .get();
    return { profiles, scores, indexSql: index ? index.sql : null };
  } finally {
    db.close();
  }
}

function initEmpty(path) {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec(SCORES_SQL);
  db.exec(`
    CREATE TABLE profiles (
      player_id text primary key,
      name text not null,
      avatar text not null default '',
      updated_at text not null,
      name_key text not null default ''
    )
  `);
  db.close();
}

function seedScoreOnly(path) {
  initEmpty(path);
  const db = new DatabaseSync(path);
  const insert = db.prepare(
    'INSERT INTO scores (player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?)',
  );
  insert.run(GHOST, 'ghost', 10, 'squish/1.0', '2026-09-01T00:00:00.000Z');
  insert.run(GHOST, 'GHOST', 20, 'squish/1.0', '2026-09-02T00:00:00.000Z');
  db.close();
}

function seedAmbiguous(path) {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec(SCORES_SQL);
  db.exec(`
    CREATE TABLE profiles (
      player_id text primary key,
      name text not null,
      avatar text not null default '',
      updated_at text not null
    )
  `);
  const insert = db.prepare(
    'INSERT INTO profiles (player_id, name, avatar, updated_at) VALUES (?, ?, ?, ?)',
  );
  insert.run(DAD_A, 'Dad', '', '2026-01-01T00:00:00.000Z');
  insert.run(DAD_B, 'Dad', '', '2026-01-02T00:00:00.000Z');
  db.close();
}

async function withFile(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'squish-lookup-'));
  const path = join(dir, 'squish.db');
  try {
    await fn(path);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

describe('GET /v1/players/lookup is read-only (D-059)', () => {
  it('a free name is held:false and writes nothing, including the name index', async () => {
    await withFile(async (path) => {
      initEmpty(path);
      await withServer(async ({ port }) => {
        const installed = snapshot(path);
        assert.ok(installed.indexSql);
        const db = new DatabaseSync(path);
        db.exec('DROP INDEX profiles_name_key');
        db.close();
        const before = snapshot(path);
        assert.equal(before.indexSql, null);
        assert.equal(before.profiles.length, 0);
        assert.equal(before.scores.length, 0);

        const looked = await request(port, 'GET', lookupPath('Nobody Here'));
        assert.equal(looked.status, 200);
        assert.deepEqual(looked.json, { held: false });
        assert.deepEqual(snapshot(path), before);

        const claimed = await request(port, 'POST', '/v1/players/resolve', {
          body: { name: 'Nobody Here' },
        });
        assert.equal(claimed.status, 201);
        assert.equal(claimed.json.created, true);
        assert.equal(claimed.json.name, 'Nobody Here');
      }, { dbPath: path, key: KEY });
    });
  });

  it('a profile holder answers the stored display and writes nothing', async () => {
    await withFile(async (path) => {
      initEmpty(path);
      await withServer(async ({ port }) => {
        const claimed = await request(port, 'POST', '/v1/players/resolve', {
          body: { name: 'Dad' },
        });
        assert.equal(claimed.status, 201);
        assert.equal(claimed.json.name, 'Dad');
        const before = snapshot(path);
        assert.equal(before.profiles.length, 1);

        const looked = await request(port, 'GET', lookupPath('dad'));
        assert.equal(looked.status, 200);
        assert.deepEqual(looked.json, { held: true, name: 'Dad' });
        assert.deepEqual(snapshot(path), before);
      }, { dbPath: path, key: KEY });
    });
  });

  it('a score-only holder answers the latest score name and creates no profile', async () => {
    await withFile(async (path) => {
      seedScoreOnly(path);
      await withServer(async ({ port }) => {
        const before = snapshot(path);
        assert.equal(before.profiles.length, 0);
        assert.equal(before.scores.length, 2);
        assert.equal(before.scores[1].name, 'GHOST');

        const looked = await request(port, 'GET', lookupPath('ghost'));
        assert.equal(looked.status, 200);
        assert.deepEqual(looked.json, { held: true, name: 'GHOST' });
        assert.deepEqual(snapshot(path), before);

        const profile = await request(port, 'GET', `/v1/profile?player_id=${GHOST}`);
        assert.equal(profile.status, 404);
        assert.equal(profile.json.error, 'unknown_profile');
      }, { dbPath: path, key: KEY });
    });
  });

  it('two holders are held:true, write nothing, and resolve is still 409', async () => {
    await withFile(async (path) => {
      seedAmbiguous(path);
      await withServer(async ({ port }) => {
        const before = snapshot(path);
        assert.equal(before.profiles.length, 2);
        assert.equal(before.indexSql, null);
        assert.deepEqual(
          before.profiles.map((row) => row.name_key).sort(),
          ['dad', 'dad'],
        );

        const looked = await request(port, 'GET', lookupPath('dad'));
        assert.equal(looked.status, 200);
        assert.equal(looked.json.held, true);
        assert.deepEqual(snapshot(path), before);

        const claimed = await request(port, 'POST', '/v1/players/resolve', {
          body: { name: 'Dad' },
        });
        assert.equal(claimed.status, 409);
        assert.equal(claimed.json.error, 'name_ambiguous');
        assert.equal(claimed.json.player_id, undefined);
      }, { dbPath: path, key: KEY });
    });
  });

  it('control characters, empty, and a missing name are 400 invalid_name', async () => {
    await withServer(async ({ port }) => {
      const paths = [
        '/v1/players/lookup',
        '/v1/players/lookup?name=',
        '/v1/players/lookup?name=%20%20',
        `/v1/players/lookup?name=${encodeURIComponent('bad\nname')}`,
        `/v1/players/lookup?name=${encodeURIComponent('\u0000Dad')}`,
      ];
      for (const path of paths) {
        const got = await request(port, 'GET', path);
        assert.equal(got.status, 400, path);
        assert.equal(got.json.error, 'invalid_name', path);
      }
    });
  });

  it('encoded names look up the same holder resolve would claim', async () => {
    await withServer(async ({ port }) => {
      const names = ['Mary Jo', 'A&B', 'C+D', 'E#F', '50%', 'Zoë'];
      for (const name of names) {
        const claimed = await request(port, 'POST', '/v1/players/resolve', {
          body: { name },
        });
        assert.equal(claimed.status, 201, name);
        assert.equal(claimed.json.name, name, name);

        const looked = await request(port, 'GET', lookupPath(name));
        assert.equal(looked.status, 200, name);
        assert.deepEqual(looked.json, { held: true, name }, name);

        const again = await request(port, 'POST', '/v1/players/resolve', {
          body: { name },
        });
        assert.equal(again.status, 200, name);
        assert.equal(again.json.created, false, name);
        assert.equal(again.json.player_id, claimed.json.player_id, name);
      }

      // A raw "+" is a space in the query parser. It must not find "C+D".
      const plus = await request(port, 'GET', '/v1/players/lookup?name=C+D');
      assert.equal(plus.status, 200);
      assert.deepEqual(plus.json, { held: false });
      const encoded = await request(port, 'GET', lookupPath('C+D'));
      assert.deepEqual(encoded.json, { held: true, name: 'C+D' });
    });
  });

  it('lookup shares the per-IP resolve limiter', async () => {
    await withServer(async ({ port }) => {
      const first = await request(port, 'GET', lookupPath('One'));
      const second = await request(port, 'GET', lookupPath('Two'));
      const claim = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: 'Three' },
      });
      assert.equal(first.status, 200);
      assert.deepEqual(first.json, { held: false });
      assert.equal(second.status, 429);
      assert.equal(second.json.error, 'rate_limited');
      assert.equal(claim.status, 429);
      assert.equal(claim.json.error, 'rate_limited');
    }, { resolveLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }) });
  });
});
