import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { describe, it } from 'node:test';
import { createRateLimiter } from '../src/index.js';
import {
  postScore,
  putProfile,
  request,
  uuid,
  withServer,
} from './helpers.js';

const KEY = 'devkey';
const ADMIN_KEY = 'admin-secret';
const WRITE_KEY = 'devkey';
const ORIGIN = 'https://play.example';

const DAD_KEEP = 'b8aa808f-6d01-439e-87be-664baf0ead85';
const DAD_PHONE = '86f2ea8f-40ab-4141-8411-0db7c837bc47';
const DAD_WEB = '6a7a41f5-f49a-4f42-85e8-01312ef0dfc9';
const NATASHA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
const T13 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2';

const KEEP_UPDATED = '2026-09-21T12:00:00.000Z';

function corsNames(headers) {
  return [...headers.keys()].filter((name) => name.startsWith('access-control-'));
}

function seedLegacy(path, { strayScores }) {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec(`
    CREATE TABLE scores (
      id integer primary key,
      player_id text not null,
      name text not null,
      score integer not null,
      client text,
      created_at text not null
    )
  `);
  db.exec(`
    CREATE TABLE profiles (
      player_id text primary key,
      name text not null,
      avatar text not null default '',
      updated_at text not null
    )
  `);
  const profile = db.prepare(
    'INSERT INTO profiles (player_id, name, avatar, updated_at) VALUES (?, ?, ?, ?)',
  );
  profile.run(DAD_KEEP, 'Dad', 'dumpling_dottie', KEEP_UPDATED);
  profile.run(DAD_PHONE, 'Dad', 'dumpling_dottie', '2026-09-26T12:00:00.000Z');
  profile.run(DAD_WEB, 'Dad', '', '2026-09-21T18:00:00.000Z');
  profile.run(NATASHA, 'Natasha', 'coffee_cuppa', '2026-09-21T12:00:00.000Z');
  profile.run(T13, 'T13', '', '2026-09-21T12:00:00.000Z');

  const score = db.prepare(
    'INSERT INTO scores (player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?)',
  );
  score.run(NATASHA, 'Natasha', 14300, 'squish/1.0', '2026-09-21T00:00:00.000Z');
  score.run(DAD_KEEP, 'Dad', 14300, 'squish/1.0', '2026-09-21T00:01:00.000Z');
  score.run(T13, 'T13', 1313, 'squish/1.0', '2026-09-21T00:02:00.000Z');
  if (strayScores) {
    score.run(DAD_WEB, 'dad', 7600, 'squish/1.0', '2026-09-21T00:03:00.000Z');
    score.run(DAD_PHONE, 'Daddy', 2000, 'squish/1.0', '2026-09-26T00:00:00.000Z');
  }
  db.close();
}

function readProfiles(path) {
  const db = new DatabaseSync(path);
  const rows = db
    .prepare(
      'SELECT player_id, name, avatar, updated_at, name_key FROM profiles ORDER BY player_id',
    )
    .all();
  const index = db
    .prepare(`SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'profiles_name_key'`)
    .get();
  db.close();
  return { rows, indexed: Boolean(index) };
}

async function adminScores(port) {
  const listed = await request(port, 'GET', '/v1/admin/scores?limit=50', {
    headers: { 'X-Squish-Admin': ADMIN_KEY },
  });
  assert.equal(listed.status, 200);
  return listed.json;
}

describe('normalized name is one player', () => {
  it('case and whitespace variants resolve to the player that claimed the name', async () => {
    await withServer(async ({ port }) => {
      const claimed = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: 'Natasha' },
      });
      assert.equal(claimed.status, 201);
      assert.equal(claimed.json.created, true);
      assert.equal(claimed.json.name, 'Natasha');
      assert.equal(claimed.json.avatar, '');
      assert.equal(typeof claimed.json.player_id, 'string');
      assert.equal(typeof claimed.json.updated_at, 'string');

      for (const name of ['natasha', 'Natasha ', '  NATASHA', 'Na\u200Btas\uFEFFha']) {
        const again = await request(port, 'POST', '/v1/players/resolve', { body: { name } });
        assert.equal(again.status, 200, name);
        assert.equal(again.json.created, false);
        assert.equal(again.json.player_id, claimed.json.player_id);
        assert.equal(again.json.name, 'Natasha');
      }

      const spaced = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: '  Ann   Marie  ' },
      });
      assert.equal(spaced.status, 201);
      assert.equal(spaced.json.name, 'Ann Marie');
      const folded = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: 'ann marie' },
      });
      assert.equal(folded.status, 200);
      assert.equal(folded.json.player_id, spaced.json.player_id);
    });
  });

  it('an optional secret is accepted and does not change who the name resolves to', async () => {
    await withServer(async ({ port }) => {
      const claimed = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: 'Natasha', secret: 'later' },
      });
      assert.equal(claimed.status, 201);
      assert.equal(claimed.json.secret, undefined);

      const otherSecret = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: 'NATASHA', secret: 'someone-else' },
      });
      assert.equal(otherSecret.status, 200);
      assert.equal(otherSecret.json.player_id, claimed.json.player_id);
      assert.equal(otherSecret.json.created, false);

      const bad = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: 'Pip', secret: 12 },
      });
      assert.equal(bad.status, 400);
      assert.equal(bad.json.error, 'invalid_secret');

      const empty = await request(port, 'POST', '/v1/players/resolve', { body: { name: '   ' } });
      assert.equal(empty.status, 400);
      assert.equal(empty.json.error, 'invalid_name');
    });
  });

  it('no write route can give a second player a name the first already holds', async () => {
    await withServer(async ({ port }) => {
      const first = uuid();
      const second = uuid();
      const claimed = await putProfile(port, {
        player_id: first,
        name: 'Natasha',
        avatar: 'coffee_cuppa',
      });
      assert.equal(claimed.status, 200);
      assert.deepEqual(Object.keys(claimed.json).sort(), [
        'avatar',
        'name',
        'player_id',
        'updated_at',
      ]);

      const profile = await putProfile(port, {
        player_id: second,
        name: ' natasha ',
        avatar: '',
      });
      assert.equal(profile.status, 409);
      assert.equal(profile.json.error, 'name_taken');

      const score = await postScore(port, { player_id: second, name: 'NATASHA', score: 10 });
      assert.equal(score.status, 409);
      assert.equal(score.json.error, 'name_taken');

      const resolved = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: 'Natasha' },
      });
      assert.equal(resolved.status, 200);
      assert.equal(resolved.json.player_id, first);
      assert.equal(resolved.json.created, false);

      const ownScore = await postScore(port, { player_id: first, name: 'Natasha', score: 4800 });
      assert.equal(ownScore.status, 201);
      assert.deepEqual(Object.keys(ownScore.json).sort(), [
        'best',
        'is_personal_best',
        'rank',
        'total_players',
      ]);

      const renamed = await postScore(port, { player_id: first, name: 'Nat', score: 100 });
      assert.equal(renamed.status, 201);
      const takenOld = await postScore(port, { player_id: second, name: 'Natasha', score: 1 });
      assert.equal(takenOld.status, 409);
      const takenNew = await putProfile(port, { player_id: second, name: 'Nat', avatar: '' });
      assert.equal(takenNew.status, 409);

      const board = await request(port, 'GET', '/v1/leaderboard');
      assert.equal(board.json.entries.length, 1);
      assert.deepEqual(Object.keys(board.json.entries[0]).sort(), [
        'at',
        'avatar',
        'name',
        'player_id',
        'rank',
        'score',
      ]);
      assert.equal(board.json.entries[0].name, 'Nat');
      assert.equal(board.json.entries[0].score, 4800);
    });
  });

  it('resolve is public CORS; a listed origin is echoed and an unlisted one is not', async () => {
    await withServer(async ({ port }) => {
      const listed = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: 'Pip' },
        headers: { Origin: ORIGIN },
      });
      assert.equal(listed.status, 201);
      assert.equal(listed.headers.get('access-control-allow-origin'), ORIGIN);
      assert.equal(listed.headers.get('vary'), 'Origin');

      const foreign = await request(port, 'POST', '/v1/players/resolve', {
        body: { name: 'Pip' },
        headers: { Origin: 'https://evil.example' },
      });
      assert.equal(foreign.status, 200);
      assert.equal(foreign.json.player_id, listed.json.player_id);
      assert.equal(foreign.headers.get('access-control-allow-origin'), null);
      assert.equal(corsNames(foreign.headers).length, 0);

      const preflight = await request(port, 'OPTIONS', '/v1/players/resolve', {
        headers: {
          Origin: ORIGIN,
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Request-Headers': 'content-type',
        },
      });
      assert.equal(preflight.status, 204);
      assert.equal(preflight.headers.get('access-control-allow-origin'), ORIGIN);
    }, { allowedOrigins: [ORIGIN] });
  });

  it('resolve rate limit is separate from score posts', async () => {
    await withServer(async ({ port }) => {
      const first = await request(port, 'POST', '/v1/players/resolve', { body: { name: 'One' } });
      const second = await request(port, 'POST', '/v1/players/resolve', { body: { name: 'Two' } });
      assert.equal(first.status, 201);
      assert.equal(second.status, 429);
      assert.equal(second.json.error, 'rate_limited');
      const score = await postScore(port, { player_id: uuid(), name: 'Three', score: 1 });
      assert.equal(score.status, 201);
    }, { resolveLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }) });
  });
});

describe('a database that already has duplicate names still serves', () => {
  it('starts, answers /healthz and /v1/leaderboard, and does not install the unique index', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'squish-dupes-'));
    const path = join(dir, 'squish.db');
    try {
      seedLegacy(path, { strayScores: false });
      await withServer(async ({ port }) => {
        const health = await request(port, 'GET', '/healthz');
        assert.equal(health.status, 200);
        assert.equal(health.json.ok, true);
        assert.equal(health.json.store, 'sqlite');

        const board = await request(port, 'GET', '/v1/leaderboard');
        assert.equal(board.status, 200);
        assert.equal(board.json.total_players, 3);
        const names = board.json.entries.map((row) => row.name).sort();
        assert.deepEqual(names, ['Dad', 'Natasha', 'T13']);

        const ambiguous = await request(port, 'POST', '/v1/players/resolve', {
          body: { name: ' dad ' },
        });
        assert.equal(ambiguous.status, 409);
        assert.equal(ambiguous.json.error, 'name_ambiguous');
        assert.equal(ambiguous.json.player_id, undefined);

        const stillPosting = await postScore(port, {
          player_id: DAD_KEEP,
          name: 'Dad',
          score: 50,
        });
        assert.equal(stillPosting.status, 201);

        const fresh = await postScore(port, { player_id: uuid(), name: 'Dad', score: 1 });
        assert.equal(fresh.status, 409);
        assert.equal(fresh.json.error, 'name_taken');
      }, { dbPath: path, key: KEY });

      const { rows, indexed } = readProfiles(path);
      assert.equal(indexed, false);
      const dads = rows.filter((row) => row.name_key === 'dad');
      assert.equal(dads.length, 3);
      assert.deepEqual(
        dads.map((row) => row.player_id).sort(),
        [DAD_KEEP, DAD_PHONE, DAD_WEB].sort(),
      );
      assert.equal(rows.find((row) => row.player_id === NATASHA).name_key, 'natasha');
      assert.equal(rows.find((row) => row.player_id === T13).name_key, 't13');
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

describe('admin merge', () => {
  it('moves profiles and score rows onto the survivor, then a second call changes nothing', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'squish-merge-'));
    const path = join(dir, 'squish.db');
    try {
      seedLegacy(path, { strayScores: true });
      await withServer(async ({ port }) => {
        const before = await request(port, 'GET', `/v1/profile?player_id=${DAD_KEEP}`);
        assert.equal(before.status, 200);
        assert.equal(before.json.avatar, 'dumpling_dottie');
        assert.equal(before.json.updated_at, KEEP_UPDATED);
        assert.equal(before.json.name, 'Dad');

        const phone = await request(port, 'POST', '/v1/admin/merge', {
          headers: { Origin: ORIGIN, 'X-Squish-Admin': ADMIN_KEY },
          body: { keep: DAD_KEEP, drop: DAD_PHONE },
        });
        assert.equal(phone.status, 200);
        assert.deepEqual(phone.json, { ok: true });
        assert.equal(corsNames(phone.headers).length, 0);

        const web = await request(port, 'POST', '/v1/admin/merge', {
          headers: { 'X-Squish-Admin': ADMIN_KEY.toUpperCase() },
          body: { keep: DAD_KEEP.toUpperCase(), drop: DAD_WEB.toUpperCase() },
        });
        assert.equal(web.status, 401);

        const webOk = await request(port, 'POST', '/v1/admin/merge', {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
          body: { keep: DAD_KEEP.toUpperCase(), drop: DAD_WEB.toUpperCase() },
        });
        assert.equal(webOk.status, 200);

        const board = await request(port, 'GET', '/v1/leaderboard?limit=10');
        const dads = board.json.entries.filter((row) => row.name === 'Dad');
        assert.equal(dads.length, 1);
        assert.equal(dads[0].player_id, DAD_KEEP);
        assert.equal(dads[0].score, 14300);
        assert.equal(dads[0].avatar, 'dumpling_dottie');
        assert.equal(board.json.total_players, 3);

        const scores = await adminScores(port);
        assert.equal(
          scores.rows.some((row) => row.player_id === DAD_PHONE || row.player_id === DAD_WEB),
          false,
        );
        assert.equal(
          scores.rows.some((row) => row.name === 'Daddy' || row.name === 'dad'),
          false,
        );
        const keptScores = scores.rows.filter((row) => row.player_id === DAD_KEEP);
        assert.equal(keptScores.length, 3);
        assert.ok(keptScores.every((row) => row.name === 'Dad'));

        const survivor = await request(port, 'GET', `/v1/profile?player_id=${DAD_KEEP}`);
        assert.equal(survivor.json.name, 'Dad');
        assert.equal(survivor.json.avatar, 'dumpling_dottie');
        assert.equal(survivor.json.updated_at, KEEP_UPDATED);
        assert.equal(
          (await request(port, 'GET', `/v1/profile?player_id=${DAD_PHONE}`)).status,
          404,
        );
        assert.equal(
          (await request(port, 'GET', `/v1/profile?player_id=${DAD_WEB}`)).status,
          404,
        );

        const resolved = await request(port, 'POST', '/v1/players/resolve', {
          body: { name: '  DAD ' },
        });
        assert.equal(resolved.status, 200);
        assert.equal(resolved.json.player_id, DAD_KEEP);
        assert.equal(resolved.json.created, false);

        const snapshot = {
          scores: await adminScores(port),
          profile: (await request(port, 'GET', `/v1/profile?player_id=${DAD_KEEP}`)).json,
          board: (await request(port, 'GET', '/v1/leaderboard')).json,
        };
        const again = await request(port, 'POST', '/v1/admin/merge', {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
          body: { keep: DAD_KEEP, drop: DAD_PHONE },
        });
        assert.equal(again.status, 404);
        assert.equal(again.json.error, 'not_found');
        assert.deepEqual(await adminScores(port), snapshot.scores);
        assert.deepEqual(
          (await request(port, 'GET', `/v1/profile?player_id=${DAD_KEEP}`)).json,
          snapshot.profile,
        );
        assert.deepEqual((await request(port, 'GET', '/v1/leaderboard')).json, snapshot.board);
      }, { dbPath: path, adminKey: ADMIN_KEY, key: KEY, allowedOrigins: [ORIGIN] });

      const { rows, indexed } = readProfiles(path);
      assert.equal(indexed, true);
      assert.equal(rows.filter((row) => row.name_key === 'dad').length, 1);
      assert.equal(rows.find((row) => row.player_id === DAD_KEEP).name, 'Dad');
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it('blank admin key is 404, a wrong key and the write key are 401, and there is no preflight', async () => {
    const body = { keep: DAD_KEEP, drop: DAD_PHONE };
    await withServer(async ({ port }) => {
      const noHeader = await request(port, 'POST', '/v1/admin/merge', { body });
      const guessed = await request(port, 'POST', '/v1/admin/merge', {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
        body,
      });
      const writeKey = await request(port, 'POST', '/v1/admin/merge', {
        headers: { 'X-Squish-Admin': WRITE_KEY },
        body,
      });
      for (const res of [noHeader, guessed, writeKey]) {
        assert.equal(res.status, 404);
        assert.equal(res.json.error, 'not_found');
        assert.equal(corsNames(res.headers).length, 0);
      }
    });

    await withServer(async ({ port }) => {
      const wrong = await request(port, 'POST', '/v1/admin/merge', {
        headers: { Origin: ORIGIN, 'X-Squish-Admin': 'nope' },
        body,
      });
      assert.equal(wrong.status, 401);
      assert.equal(wrong.json.error, 'unauthorized');
      assert.equal(corsNames(wrong.headers).length, 0);

      const writeKey = await request(port, 'POST', '/v1/admin/merge', {
        headers: { Origin: ORIGIN, 'X-Squish-Admin': WRITE_KEY },
        body,
      });
      assert.equal(writeKey.status, 401);
      assert.equal(writeKey.json.error, 'unauthorized');
      assert.equal(corsNames(writeKey.headers).length, 0);

      const missing = await request(port, 'POST', '/v1/admin/merge', {
        headers: { Origin: ORIGIN },
        body,
      });
      assert.equal(missing.status, 401);

      const preflight = await request(port, 'OPTIONS', '/v1/admin/merge', {
        headers: {
          Origin: ORIGIN,
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Request-Headers': 'x-squish-admin, content-type',
        },
      });
      assert.equal(preflight.status, 404);
      assert.equal(preflight.json.error, 'not_found');
      assert.equal(corsNames(preflight.headers).length, 0);

      const same = await request(port, 'POST', '/v1/admin/merge', {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
        body: { keep: DAD_KEEP, drop: DAD_KEEP },
      });
      assert.equal(same.status, 400);
      assert.equal(same.json.error, 'same_player');

      const missingPlayer = await request(port, 'POST', '/v1/admin/merge', {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
        body,
      });
      assert.equal(missingPlayer.status, 404);
      assert.equal(missingPlayer.json.error, 'not_found');
    }, { adminKey: ADMIN_KEY, allowedOrigins: [ORIGIN] });
  });
});
