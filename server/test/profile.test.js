import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { describe, it } from 'node:test';
import { createCatalog } from '../src/catalog.js';
import { closeDb, getLeaderboard, openDb } from '../src/db.js';
import { renderBoard } from '../src/page.js';
import {
  postScore,
  profileBody,
  putProfile,
  request,
  requestBinary,
  uuid,
  withServer,
} from './helpers.js';

const NATASHA = '11111111-1111-4111-8111-111111111111';
const STEVE = '22222222-2222-4222-8222-222222222222';
const KEY = 'devkey';
const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47]);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

describe('PUT /v1/profile and GET /v1/profile', () => {
  it('round-trips a profile; a second PUT updates in place and leaves one row', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'squish-profile-'));
    const path = join(dir, 'squish.db');
    try {
      await withServer(async ({ port }) => {
        const first = await putProfile(port, {
          player_id: NATASHA,
          name: 'Natasha',
          avatar: 'bear_bounce',
        });
        assert.equal(first.status, 200);
        assert.equal(first.json.player_id, NATASHA);
        assert.equal(first.json.name, 'Natasha');
        assert.equal(first.json.avatar, 'bear_bounce');
        assert.equal(typeof first.json.updated_at, 'string');
        assert.ok(Number.isFinite(Date.parse(first.json.updated_at)));

        const got = await request(port, 'GET', `/v1/profile?player_id=${NATASHA}`);
        assert.equal(got.status, 200);
        assert.deepEqual(got.json, first.json);

        await sleep(10);
        const second = await putProfile(port, {
          player_id: NATASHA,
          name: 'Nat',
          avatar: '',
        });
        assert.equal(second.status, 200);
        assert.equal(second.json.player_id, NATASHA);
        assert.equal(second.json.name, 'Nat');
        assert.equal(second.json.avatar, '');
        assert.notEqual(second.json.updated_at, first.json.updated_at);
        assert.ok(second.json.updated_at > first.json.updated_at);

        const again = await request(port, 'GET', `/v1/profile?player_id=${NATASHA}`);
        assert.deepEqual(again.json, second.json);
      }, { dbPath: path });

      const db = new DatabaseSync(path);
      const count = db.prepare('SELECT COUNT(*) AS n FROM profiles').get();
      assert.equal(count.n, 1);
      db.close();
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it('401 without a key or with a wrong key', async () => {
    await withServer(async ({ port }) => {
      const missing = await request(port, 'PUT', '/v1/profile', {
        body: profileBody({ player_id: NATASHA }),
      });
      assert.equal(missing.status, 401);
      assert.equal(missing.json.error, 'unauthorized');

      const wrong = await request(port, 'PUT', '/v1/profile', {
        key: 'nope',
        body: profileBody({ player_id: NATASHA }),
      });
      assert.equal(wrong.status, 401);
      assert.equal(wrong.json.error, 'unauthorized');
    });
  });

  it('400 on a bad uuid, empty or control-character name, and unknown avatar', async () => {
    await withServer(async ({ port }) => {
      const badUuid = await putProfile(port, { player_id: 'nope', name: 'Natasha', avatar: '' });
      assert.equal(badUuid.status, 400);
      assert.equal(badUuid.json.error, 'invalid_player_id');

      const empty = await putProfile(port, { player_id: NATASHA, name: '   ', avatar: '' });
      assert.equal(empty.status, 400);
      assert.equal(empty.json.error, 'invalid_name');

      const control = await putProfile(port, {
        player_id: NATASHA,
        name: 'Nat\u0001asha',
        avatar: '',
      });
      assert.equal(control.status, 400);
      assert.equal(control.json.error, 'invalid_name');

      const unknown = await putProfile(port, {
        player_id: NATASHA,
        name: 'Natasha',
        avatar: 'not_a_squishy',
      });
      assert.equal(unknown.status, 400);
      assert.equal(unknown.json.error, 'invalid_avatar');
    });
  });

  it('PUT with avatar "" is 200; every catalogued id is accepted', async () => {
    const catalog = createCatalog();
    const ids = catalog.ids();
    assert.ok(ids.length > 0);

    await withServer(async ({ port }) => {
      const empty = await putProfile(port, { player_id: NATASHA, name: 'Natasha', avatar: '' });
      assert.equal(empty.status, 200);
      assert.equal(empty.json.avatar, '');

      for (const id of ids) {
        const res = await putProfile(port, {
          player_id: uuid(),
          name: 'Pip',
          avatar: id,
        });
        assert.equal(res.status, 200, id);
        assert.equal(res.json.avatar, id);
      }
    }, { limiter: { allow: () => true } });
  });

  it('GET unknown player is 404 unknown_profile; malformed id is 400', async () => {
    await withServer(async ({ port }) => {
      const missing = await request(port, 'GET', `/v1/profile?player_id=${NATASHA}`);
      assert.equal(missing.status, 404);
      assert.equal(missing.json.error, 'unknown_profile');

      const bad = await request(port, 'GET', '/v1/profile?player_id=not-a-uuid');
      assert.equal(bad.status, 400);
      assert.equal(bad.json.error, 'invalid_player_id');
    });
  });
});

describe('avatar on the leaderboard', () => {
  it('a profile shows its id; a player without a profile shows ""; other fields stay', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 4800 });
      await postScore(port, { player_id: STEVE, name: 'Dad', score: 9200 });
      await putProfile(port, { player_id: NATASHA, name: 'Natasha', avatar: 'bear_bounce' });

      const board = await request(port, 'GET', '/v1/leaderboard?limit=10');
      assert.equal(board.status, 200);
      assert.equal(board.json.total_players, 2);
      const dad = board.json.entries.find((row) => row.player_id === STEVE);
      const natasha = board.json.entries.find((row) => row.player_id === NATASHA);
      assert.equal(dad.avatar, '');
      assert.equal(dad.name, 'Dad');
      assert.equal(dad.score, 9200);
      assert.equal(dad.rank, 1);
      assert.equal(typeof dad.at, 'string');
      assert.equal(natasha.avatar, 'bear_bounce');
      assert.equal(natasha.name, 'Natasha');
      assert.equal(natasha.score, 4800);
      assert.equal(natasha.rank, 2);

      const meWith = await request(port, 'GET', `/v1/leaderboard/me?player_id=${NATASHA}`);
      assert.equal(meWith.status, 200);
      assert.equal(meWith.json.rank, 2);
      assert.equal(meWith.json.best, 4800);
      assert.equal(meWith.json.name, 'Natasha');
      assert.equal(meWith.json.avatar, 'bear_bounce');

      const meWithout = await request(port, 'GET', `/v1/leaderboard/me?player_id=${STEVE}`);
      assert.equal(meWithout.json.avatar, '');
      assert.equal(meWithout.json.best, 9200);
      assert.equal(meWithout.json.name, 'Dad');
    });
  });

  it('renaming still shows the newest name against the best score, with the avatar', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Old', score: 5000 });
      await postScore(port, { player_id: NATASHA, name: 'New', score: 100 });
      await putProfile(port, { player_id: NATASHA, name: 'ProfileName', avatar: 'frog_gus' });

      const board = await request(port, 'GET', '/v1/leaderboard?limit=5');
      assert.equal(board.json.entries.length, 1);
      assert.equal(board.json.entries[0].name, 'New');
      assert.equal(board.json.entries[0].score, 5000);
      assert.equal(board.json.entries[0].avatar, 'frog_gus');

      const me = await request(port, 'GET', `/v1/leaderboard/me?player_id=${NATASHA}`);
      assert.equal(me.json.name, 'New');
      assert.equal(me.json.best, 5000);
      assert.equal(me.json.avatar, 'frog_gus');
    });
  });
});

describe('GET /avatars/<id>.png', () => {
  it('returns 200 image/png for a catalogued id with art', async () => {
    const catalog = createCatalog();
    const id = catalog.ids()[0];
    assert.ok(id);

    await withServer(async ({ port }) => {
      const res = await requestBinary(port, 'GET', `/avatars/${id}.png`);
      assert.equal(res.status, 200);
      assert.equal(res.headers.get('content-type'), 'image/png');
      assert.equal(res.headers.get('cache-control'), 'public, max-age=86400');
      assert.ok(res.body.subarray(0, 4).equals(PNG_MAGIC));
    });
  });

  it('404 for an unknown id, traversal, and a catalogued id whose file is missing', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'squish-catalog-'));
    const catalogPath = join(dir, 'catalog.json');
    await writeFile(
      catalogPath,
      JSON.stringify({
        squishies: [
          {
            id: 'ghost_squish',
            assets: { sprite: 'res://assets/design/squishes/art/ghost_squish.png' },
          },
        ],
      }),
    );

    try {
      await withServer(async ({ port }) => {
        const unknown = await requestBinary(port, 'GET', '/avatars/not_a_squishy.png');
        assert.equal(unknown.status, 404);

        const dotdot = await requestBinary(port, 'GET', '/avatars/../package.json');
        assert.equal(dotdot.status, 404);

        const absolute = await requestBinary(port, 'GET', '/avatars/%2Fetc%2Fpasswd.png');
        assert.equal(absolute.status, 404);

        const encoded = await requestBinary(port, 'GET', '/avatars/%2e%2e%2fpackage.json');
        assert.equal(encoded.status, 404);

        const accepted = await putProfile(port, {
          player_id: NATASHA,
          name: 'Ghost',
          avatar: 'ghost_squish',
        });
        assert.equal(accepted.status, 200);

        const missingFile = await requestBinary(port, 'GET', '/avatars/ghost_squish.png');
        assert.equal(missingFile.status, 404);
      }, { catalogPath });
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

describe('missing catalog does not take the service down', () => {
  it('boots, serves the board, and rejects non-empty avatars', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'squish-nocatalog-'));
    const catalogPath = join(dir, 'missing-catalog.json');
    try {
      await withServer(async ({ port }) => {
        const health = await request(port, 'GET', '/healthz');
        assert.equal(health.status, 200);
        assert.equal(health.json.ok, true);

        await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 100 });
        const home = await fetch(`http://127.0.0.1:${port}/`);
        assert.equal(home.status, 200);
        const html = await home.text();
        assert.match(html, /Natasha/);
        assert.doesNotMatch(html, /<img\b/);

        const rejected = await putProfile(port, {
          player_id: NATASHA,
          name: 'Natasha',
          avatar: 'bear_bounce',
        });
        assert.equal(rejected.status, 400);
        assert.equal(rejected.json.error, 'invalid_avatar');
      }, { catalogPath });
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

describe('forward migration on a populated pre-change DB', () => {
  it('openDb adds an empty profiles table and leaves existing scores intact', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'squish-migrate-'));
    const path = join(dir, 'squish.db');
    try {
      const old = new DatabaseSync(path);
      old.exec('PRAGMA journal_mode = WAL');
      old.exec(`
        CREATE TABLE IF NOT EXISTS scores (
          id integer primary key,
          player_id text not null,
          name text not null,
          score integer not null,
          client text,
          created_at text not null
        )
      `);
      old.exec(
        'CREATE INDEX IF NOT EXISTS scores_player_score ON scores (player_id, score DESC)',
      );
      old.prepare(
        'INSERT INTO scores (player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?)',
      ).run(NATASHA, 'Natasha', 14300, 'squish/1.0', '2026-09-09T00:00:00.000Z');
      old.prepare(
        'INSERT INTO scores (player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?)',
      ).run(STEVE, 'Dad', 9200, 'squish/1.0', '2026-09-09T00:01:00.000Z');

      const before = old
        .prepare(
          `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name`,
        )
        .all()
        .map((row) => row.name);
      assert.deepEqual(before, ['scores']);
      old.close();

      const db = openDb(path);
      const cols = db.prepare('PRAGMA table_info(scores)').all().map((col) => col.name);
      assert.deepEqual(cols, ['id', 'player_id', 'name', 'score', 'client', 'created_at']);

      const tables = db
        .prepare(
          `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name`,
        )
        .all()
        .map((row) => row.name);
      assert.deepEqual(tables, ['profiles', 'scores']);

      const scores = db.prepare('SELECT player_id, name, score FROM scores ORDER BY score DESC').all();
      assert.equal(scores.length, 2);
      assert.equal(scores[0].name, 'Natasha');
      assert.equal(scores[0].score, 14300);
      assert.equal(scores[1].name, 'Dad');
      assert.equal(scores[1].score, 9200);

      const profiles = db.prepare('SELECT * FROM profiles').all();
      assert.equal(profiles.length, 0);

      const board = getLeaderboard(db, 10);
      assert.equal(board.total_players, 2);
      assert.equal(board.entries[0].name, 'Natasha');
      assert.equal(board.entries[0].score, 14300);
      assert.equal(board.entries[0].avatar, '');
      assert.equal(board.entries[1].name, 'Dad');
      assert.equal(board.entries[1].avatar, '');

      const html = renderBoard(board);
      assert.match(html, /Natasha/);
      assert.match(html, /Dad/);
      assert.doesNotMatch(html, /<img\b/);
      closeDb(db);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
