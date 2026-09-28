import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { describe, it } from 'node:test';
import { request, withServer } from './helpers.js';

const ADMIN_KEY = 'admin-secret';
const ORIGIN = 'https://play.example';

const NATASHA = '6c107d4d-1111-4111-8111-111111111111';
const DAD = 'b8aa808f-6d01-439e-87be-664baf0ead85';
const GHOST = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const PIP = '33333333-3333-4333-8333-333333333333';
const OTHER = '22222222-2222-4222-8222-222222222222';

const STRAY_AT = '2026-09-09T00:00:00.000Z';
const DAD_AT = '2026-09-20T00:00:00.000Z';
const NATASHA_AT = '2026-09-21T00:00:00.000Z';
const UPDATED = '2026-09-21T12:00:00.000Z';

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

const PROFILES_SQL = `
  CREATE TABLE profiles (
    player_id text primary key,
    name text not null,
    avatar text not null default '',
    updated_at text not null,
    name_key text not null default ''
  )
`;

function holdersPath(name) {
  return `/v1/admin/holders?name=${encodeURIComponent(name)}`;
}

function corsNames(headers) {
  return [...headers.keys()].filter((name) => name.startsWith('access-control-'));
}

async function rawText(port, method, path, { headers, body } = {}) {
  const res = await fetch(`http://127.0.0.1:${port}${path}`, {
    method,
    headers: {
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
      ...headers,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, text: await res.text(), headers: res.headers };
}

function openSchema(path) {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec(SCORES_SQL);
  db.exec(PROFILES_SQL);
  return db;
}

function seedStrayDad(path) {
  const db = openSchema(path);
  const profile = db.prepare(
    'INSERT INTO profiles (player_id, name, avatar, updated_at, name_key) VALUES (?, ?, ?, ?, ?)',
  );
  profile.run(NATASHA, 'Natasha', 'coffee_cuppa', UPDATED, 'natasha');
  profile.run(DAD, 'Dad', 'dumpling_dottie', UPDATED, 'dad');
  const score = db.prepare(
    'INSERT INTO scores (id, player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?, ?)',
  );
  score.run(3, NATASHA, 'Dad', 5100, 'squish/1.0', STRAY_AT);
  score.run(4, NATASHA, 'Natasha', 14300, 'squish/1.0', NATASHA_AT);
  score.run(5, DAD, 'Dad', 8000, 'squish/1.0', DAD_AT);
  db.close();
}

function seedScoreOnly(path) {
  const db = openSchema(path);
  const score = db.prepare(
    'INSERT INTO scores (id, player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?, ?)',
  );
  score.run(1, GHOST, 'ghost', 10, 'squish/1.0', '2026-09-01T00:00:00.000Z');
  score.run(2, GHOST, 'GHOST', 20, 'squish/1.0', '2026-09-02T00:00:00.000Z');
  db.close();
}

function seedPages(path) {
  const db = openSchema(path);
  const score = db.prepare(
    'INSERT INTO scores (id, player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?, ?)',
  );
  for (let id = 1; id <= 120; id += 1) {
    let createdAt;
    if (id <= 30) createdAt = '2026-09-01T00:00:00.000Z';
    else if (id <= 60) createdAt = '2026-09-02T00:00:00.000Z';
    else createdAt = '2026-09-03T00:00:00.000Z';
    const playerId = id >= 91 ? PIP : OTHER;
    score.run(id, playerId, 'Row', id, 'squish/1.0', createdAt);
  }
  db.close();
}

function seedManyRows(path) {
  const db = openSchema(path);
  const profile = db.prepare(
    'INSERT INTO profiles (player_id, name, avatar, updated_at, name_key) VALUES (?, ?, ?, ?, ?)',
  );
  profile.run(NATASHA, 'Natasha', 'coffee_cuppa', UPDATED, 'natasha');
  profile.run(DAD, 'Dad', 'dumpling_dottie', UPDATED, 'dad');
  const score = db.prepare(
    'INSERT INTO scores (id, player_id, name, score, client, created_at) VALUES (?, ?, ?, ?, ?, ?)',
  );
  score.run(3, NATASHA, 'Dad', 5100, 'squish/1.0', STRAY_AT);
  score.run(7, NATASHA, 'Natasha', 100, 'squish/web', STRAY_AT);
  score.run(8, DAD, 'Dad', 8000, 'squish/1.0', STRAY_AT);
  score.run(9, GHOST, 'Ghost', 15, 'squish/1.0', '2026-08-01T00:00:00.000Z');
  score.run(10, OTHER, 'Other', 42, null, '2026-07-01T00:00:00.000Z');
  db.close();
}

function readTable(path, sql) {
  const db = new DatabaseSync(path, { readOnly: true });
  try {
    return db.prepare(sql).all();
  } finally {
    db.close();
  }
}

function readScores(path) {
  return readTable(
    path,
    'SELECT id, player_id, name, score, client, created_at FROM scores ORDER BY id',
  );
}

function readProfiles(path) {
  return readTable(
    path,
    'SELECT player_id, name, avatar, updated_at, name_key FROM profiles ORDER BY player_id',
  );
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
      .prepare(`SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'profiles_name_key'`)
      .get();
    return {
      profileCount: profiles.length,
      scoreCount: scores.length,
      profiles,
      scores,
      indexSql: index ? index.sql : null,
    };
  } finally {
    db.close();
  }
}

function dropNameIndex(path) {
  const db = new DatabaseSync(path);
  db.exec('DROP INDEX IF EXISTS profiles_name_key');
  db.close();
}

function byCreatedThenId(rows) {
  return rows.slice().sort((a, b) => {
    if (a.created_at !== b.created_at) return a.created_at < b.created_at ? 1 : -1;
    return b.id - a.id;
  });
}

async function withFile(prefix, seed, fn) {
  const dir = await mkdtemp(join(tmpdir(), prefix));
  const path = join(dir, 'squish.db');
  try {
    seed(path);
    await fn(path);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

describe('D-055 stray hold, seen and released without deleting history (D-060)', () => {
  it('resolve stays ambiguous until the stray row is relabeled to its own profile', async () => {
    await withFile('squish-t38-stray-', seedStrayDad, async (path) => {
      await withServer(async ({ port }) => {
        const beforeScores = readScores(path);
        const beforeProfiles = readProfiles(path);
        assert.equal(beforeScores.length, 3);

        const ambiguous = await rawText(port, 'POST', '/v1/players/resolve', {
          body: { name: 'Dad' },
        });
        assert.equal(ambiguous.status, 409);
        assert.equal(ambiguous.text, '{"error":"name_ambiguous"}');

        const listed = await request(port, 'GET', holdersPath('Dad'), {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(listed.status, 200);
        assert.equal(listed.json.key, 'dad');
        assert.equal(listed.json.holders.length, 2);
        const natasha = listed.json.holders.find((row) => row.player_id === NATASHA);
        const dad = listed.json.holders.find((row) => row.player_id === DAD);
        assert.ok(natasha);
        assert.ok(dad);
        assert.deepEqual(natasha.profile, { name: 'Natasha', avatar: 'coffee_cuppa' });
        assert.deepEqual(natasha.score_rows, [
          { id: 3, name: 'Dad', score: 5100, created_at: STRAY_AT },
        ]);
        assert.deepEqual(dad.profile, { name: 'Dad', avatar: 'dumpling_dottie' });

        const folded = await request(port, 'GET', holdersPath('dad'), {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(folded.status, 200);
        assert.deepEqual(folded.json, listed.json);

        const boardBefore = await request(port, 'GET', '/v1/leaderboard');
        const meBefore = await request(port, 'GET', `/v1/leaderboard/me?player_id=${NATASHA}`);
        assert.equal(meBefore.status, 200);
        assert.equal(meBefore.json.best, 14300);
        assert.equal(meBefore.json.name, 'Natasha');

        const relabeled = await request(port, 'POST', '/v1/admin/scores/3/relabel', {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(relabeled.status, 200);
        assert.deepEqual(relabeled.json, {
          ok: true,
          id: 3,
          player_id: NATASHA,
          name_before: 'Dad',
          name_after: 'Natasha',
        });

        const afterScores = readScores(path);
        assert.equal(afterScores.length, beforeScores.length);
        for (const row of afterScores) {
          const prev = beforeScores.find((item) => item.id === row.id);
          if (row.id === 3) {
            assert.equal(row.name, 'Natasha');
            assert.equal(row.player_id, prev.player_id);
            assert.equal(row.score, prev.score);
            assert.equal(row.client, prev.client);
            assert.equal(row.created_at, prev.created_at);
          } else {
            assert.deepEqual(row, prev);
          }
        }
        assert.deepEqual(readProfiles(path), beforeProfiles);

        const released = await request(port, 'POST', '/v1/players/resolve', {
          body: { name: 'Dad' },
        });
        assert.equal(released.status, 200);
        assert.equal(released.json.player_id, DAD);
        assert.equal(released.json.created, false);

        const boardAfter = await request(port, 'GET', '/v1/leaderboard');
        const meAfter = await request(port, 'GET', `/v1/leaderboard/me?player_id=${NATASHA}`);
        assert.deepEqual(boardAfter.json, boardBefore.json);
        assert.deepEqual(meAfter.json, meBefore.json);
        const natashaEntry = boardAfter.json.entries.find((row) => row.player_id === NATASHA);
        assert.equal(natashaEntry.name, 'Natasha');
        assert.equal(natashaEntry.score, 14300);
      }, { dbPath: path, adminKey: ADMIN_KEY });
    });
  });
});

describe('GET /v1/admin/holders', () => {
  it('a free name has no holders, and a score-only holder has a null profile', async () => {
    await withFile('squish-t38-free-', (path) => openSchema(path).close(), async (path) => {
      await withServer(async ({ port }) => {
        const free = await request(port, 'GET', holdersPath('Nobody'), {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(free.status, 200);
        assert.deepEqual(free.json, { key: 'nobody', holders: [] });
      }, { dbPath: path, adminKey: ADMIN_KEY });
    });

    await withFile('squish-t38-ghost-', seedScoreOnly, async (path) => {
      await withServer(async ({ port }) => {
        const held = await request(port, 'GET', holdersPath('ghost'), {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(held.status, 200);
        assert.equal(held.json.key, 'ghost');
        assert.equal(held.json.holders.length, 1);
        assert.equal(held.json.holders[0].player_id, GHOST);
        assert.equal(held.json.holders[0].profile, null);
        assert.deepEqual(
          held.json.holders[0].score_rows.map((row) => [row.id, row.name, row.score, row.created_at]),
          [
            [1, 'ghost', 10, '2026-09-01T00:00:00.000Z'],
            [2, 'GHOST', 20, '2026-09-02T00:00:00.000Z'],
          ],
        );
        const profile = await request(port, 'GET', `/v1/profile?player_id=${GHOST}`);
        assert.equal(profile.status, 404);
      }, { dbPath: path, adminKey: ADMIN_KEY });
    });
  });

  it('control characters, empty, and a missing name are 400 invalid_name', async () => {
    await withServer(async ({ port }) => {
      const paths = [
        '/v1/admin/holders',
        '/v1/admin/holders?name=',
        '/v1/admin/holders?name=%20',
        `/v1/admin/holders?name=${encodeURIComponent('Dad\n')}`,
      ];
      for (const path of paths) {
        const res = await request(port, 'GET', path, {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(res.status, 400, path);
        assert.deepEqual(res.json, { error: 'invalid_name' });
      }
    }, { adminKey: ADMIN_KEY });
  });

  it('writes nothing: counts and the name index stay as they were', async () => {
    await withFile('squish-t38-ro-free-', (path) => openSchema(path).close(), async (path) => {
      await withServer(async ({ port }) => {
        dropNameIndex(path);
        const before = snapshot(path);
        assert.equal(before.indexSql, null);
        assert.equal(before.profileCount, 0);
        assert.equal(before.scoreCount, 0);
        const free = await request(port, 'GET', holdersPath('Nobody'), {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(free.status, 200);
        assert.deepEqual(free.json.holders, []);
        assert.deepEqual(snapshot(path), before);
      }, { dbPath: path, adminKey: ADMIN_KEY });
    });

    await withFile('squish-t38-ro-ghost-', seedScoreOnly, async (path) => {
      await withServer(async ({ port }) => {
        dropNameIndex(path);
        const before = snapshot(path);
        assert.equal(before.indexSql, null);
        assert.equal(before.profileCount, 0);
        assert.equal(before.scoreCount, 2);
        const held = await request(port, 'GET', holdersPath('GHOST'), {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(held.status, 200);
        assert.equal(held.json.holders.length, 1);
        assert.equal(held.json.holders[0].profile, null);
        assert.deepEqual(snapshot(path), before);
      }, { dbPath: path, adminKey: ADMIN_KEY });
    });

    await withFile('squish-t38-ro-held-', seedStrayDad, async (path) => {
      await withServer(async ({ port }) => {
        const before = snapshot(path);
        assert.ok(before.indexSql);
        assert.equal(before.profileCount, 2);
        assert.equal(before.scoreCount, 3);
        const held = await request(port, 'GET', holdersPath('dad'), {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(held.status, 200);
        assert.equal(held.json.holders.length, 2);
        assert.deepEqual(snapshot(path), before);
      }, { dbPath: path, adminKey: ADMIN_KEY });
    });
  });
});

describe('GET /v1/admin/scores offset (D-060)', () => {
  it('pages a tied timestamp in created_at DESC, id DESC order, including a player filter', async () => {
    await withFile('squish-t38-pages-', seedPages, async (path) => {
      await withServer(async ({ port }) => {
        const stored = readScores(path);
        assert.equal(stored.length, 120);
        const tied = stored.filter((row) => row.created_at === '2026-09-03T00:00:00.000Z');
        assert.equal(tied.length, 60);

        const expected = byCreatedThenId(stored);
        const pages = [];
        for (const offset of [0, 50, 100]) {
          const res = await request(port, 'GET', `/v1/admin/scores?limit=50&offset=${offset}`, {
            headers: { 'X-Squish-Admin': ADMIN_KEY },
          });
          assert.equal(res.status, 200, String(offset));
          assert.equal(res.json.total, 120);
          assert.equal(res.json.offset, offset);
          pages.push(res.json.rows);
        }
        assert.deepEqual(pages.map((rows) => rows.length), [50, 50, 20]);

        const flat = pages.flat();
        assert.deepEqual(
          flat.map((row) => row.id),
          expected.map((row) => row.id),
        );
        const seen = new Set(flat.map((row) => row.id));
        assert.equal(seen.size, 120);

        const firstTimes = new Set(pages[0].map((row) => row.created_at));
        const secondTimes = new Set(pages[1].map((row) => row.created_at));
        const shared = [...firstTimes].filter((stamp) => secondTimes.has(stamp));
        assert.ok(shared.includes('2026-09-03T00:00:00.000Z'));

        const omitted = await request(port, 'GET', '/v1/admin/scores?limit=50', {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        const explicit = await request(port, 'GET', '/v1/admin/scores?limit=50&offset=0', {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.deepEqual(omitted.json, explicit.json);
        assert.equal(omitted.json.offset, 0);

        const past = await request(port, 'GET', '/v1/admin/scores?limit=50&offset=500', {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(past.status, 200);
        assert.deepEqual(past.json.rows, []);
        assert.equal(past.json.total, 120);
        assert.equal(past.json.offset, 500);

        for (const bad of ['-1', '1.5', 'abc']) {
          const res = await request(
            port,
            'GET',
            `/v1/admin/scores?offset=${encodeURIComponent(bad)}`,
            { headers: { 'X-Squish-Admin': ADMIN_KEY } },
          );
          assert.equal(res.status, 400, bad);
          assert.deepEqual(res.json, { error: 'invalid_offset' });
        }

        const pipExpected = byCreatedThenId(stored.filter((row) => row.player_id === PIP));
        assert.equal(pipExpected.length, 30);
        assert.equal(new Set(pipExpected.map((row) => row.created_at)).size, 1);
        const pipPages = [];
        for (const offset of [0, 10, 20]) {
          const res = await request(
            port,
            'GET',
            `/v1/admin/scores?player_id=${PIP}&limit=10&offset=${offset}`,
            { headers: { 'X-Squish-Admin': ADMIN_KEY } },
          );
          assert.equal(res.status, 200, `pip ${offset}`);
          assert.equal(res.json.total, 30);
          assert.equal(res.json.offset, offset);
          assert.equal(res.json.rows.length, 10);
          assert.ok(res.json.rows.every((row) => row.player_id === PIP));
          pipPages.push(res.json.rows);
        }
        assert.deepEqual(
          pipPages.flat().map((row) => row.id),
          pipExpected.map((row) => row.id),
        );
        const pipPast = await request(
          port,
          'GET',
          `/v1/admin/scores?player_id=${PIP}&limit=10&offset=100`,
          { headers: { 'X-Squish-Admin': ADMIN_KEY } },
        );
        assert.equal(pipPast.status, 200);
        assert.deepEqual(pipPast.json.rows, []);
        assert.equal(pipPast.json.total, 30);
        assert.equal(pipPast.json.offset, 100);
      }, { dbPath: path, adminKey: ADMIN_KEY });
    });
  });
});

describe('POST /v1/admin/scores/:id/relabel', () => {
  it('an unknown id is 404, a non-integer id is 404, and no profile leaves the row unchanged', async () => {
    await withFile('squish-t38-refuse-', seedScoreOnly, async (path) => {
      await withServer(async ({ port }) => {
        const before = readScores(path);

        const missing = await request(port, 'POST', '/v1/admin/scores/999999/relabel', {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(missing.status, 404);
        assert.deepEqual(missing.json, { error: 'not_found' });

        for (const id of ['abc', '1.5', '01']) {
          const res = await request(port, 'POST', `/v1/admin/scores/${id}/relabel`, {
            headers: { 'X-Squish-Admin': ADMIN_KEY },
          });
          assert.equal(res.status, 404, id);
          assert.deepEqual(res.json, { error: 'not_found' });
        }

        const refused = await request(port, 'POST', '/v1/admin/scores/1/relabel', {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(refused.status, 409);
        assert.deepEqual(refused.json, { error: 'no_profile' });
        assert.deepEqual(readScores(path), before);
        assert.equal(readProfiles(path).length, 0);
      }, { dbPath: path, adminKey: ADMIN_KEY });
    });
  });

  it('changes one row and ignores a name supplied in the body', async () => {
    await withFile('squish-t38-one-', seedManyRows, async (path) => {
      await withServer(async ({ port }) => {
        const before = readScores(path);
        const beforeProfiles = readProfiles(path);
        assert.equal(before.length, 5);

        const relabeled = await request(port, 'POST', '/v1/admin/scores/3/relabel', {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
          body: { name: 'Stolen' },
        });
        assert.equal(relabeled.status, 200);
        assert.deepEqual(relabeled.json, {
          ok: true,
          id: 3,
          player_id: NATASHA,
          name_before: 'Dad',
          name_after: 'Natasha',
        });

        const after = readScores(path);
        assert.equal(after.length, before.length);
        for (const row of after) {
          const prev = before.find((item) => item.id === row.id);
          assert.ok(prev);
          assert.equal(row.id, prev.id);
          assert.equal(row.player_id, prev.player_id);
          assert.equal(row.score, prev.score);
          assert.equal(row.client, prev.client);
          assert.equal(row.created_at, prev.created_at);
          if (row.id === 3) assert.equal(row.name, 'Natasha');
          else assert.equal(row.name, prev.name);
        }
        assert.deepEqual(readProfiles(path), beforeProfiles);
        assert.equal(after.find((row) => row.id === 8).name, 'Dad');
        assert.equal(after.find((row) => row.id === 9).name, 'Ghost');
      }, { dbPath: path, adminKey: ADMIN_KEY });
    });
  });
});

describe('admin auth on holders, paged scores, and relabel', () => {
  const routes = [
    ['GET', '/v1/admin/holders?name=Dad'],
    ['GET', '/v1/admin/scores?offset=0'],
    ['POST', '/v1/admin/scores/3/relabel'],
  ];

  it('no header and a wrong key are 401, and an allowed origin still gets no CORS header', async () => {
    await withServer(async ({ port }) => {
      for (const [method, path] of routes) {
        const missing = await request(port, method, path, { headers: { Origin: ORIGIN } });
        assert.equal(missing.status, 401, `${method} ${path} missing`);
        assert.deepEqual(missing.json, { error: 'unauthorized' });
        assert.equal(missing.headers.get('access-control-allow-origin'), null);
        assert.equal(corsNames(missing.headers).length, 0);

        const wrong = await request(port, method, path, {
          headers: { Origin: ORIGIN, 'X-Squish-Admin': 'nope' },
        });
        assert.equal(wrong.status, 401, `${method} ${path} wrong`);
        assert.deepEqual(wrong.json, { error: 'unauthorized' });
        assert.equal(wrong.headers.get('access-control-allow-origin'), null);
        assert.equal(corsNames(wrong.headers).length, 0);
      }

      const listed = await request(port, 'GET', '/v1/admin/scores?offset=0', {
        headers: { Origin: ORIGIN, 'X-Squish-Admin': ADMIN_KEY },
      });
      assert.equal(listed.status, 200);
      assert.equal(listed.headers.get('access-control-allow-origin'), null);
      assert.equal(corsNames(listed.headers).length, 0);

      for (const path of [
        '/v1/admin/holders',
        '/v1/admin/scores',
        '/v1/admin/scores/3/relabel',
      ]) {
        const preflight = await request(port, 'OPTIONS', path, {
          headers: { Origin: ORIGIN, 'Access-Control-Request-Method': 'POST' },
        });
        assert.equal(preflight.status, 404, path);
        assert.deepEqual(preflight.json, { error: 'not_found' });
        assert.equal(preflight.headers.get('access-control-allow-origin'), null);
        assert.equal(corsNames(preflight.headers).length, 0);
      }
    }, { adminKey: ADMIN_KEY, allowedOrigins: [ORIGIN] });
  });

  it('a blank admin key answers 404 on all three routes', async () => {
    await withServer(async ({ port }) => {
      for (const [method, path] of routes) {
        const noHeader = await request(port, method, path);
        assert.equal(noHeader.status, 404, `${method} ${path} no header`);
        assert.deepEqual(noHeader.json, { error: 'not_found' });

        const withHeader = await request(port, method, path, {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
        });
        assert.equal(withHeader.status, 404, `${method} ${path} with header`);
        assert.deepEqual(withHeader.json, { error: 'not_found' });
        assert.equal(withHeader.headers.get('access-control-allow-origin'), null);
      }
    });
  });
});
