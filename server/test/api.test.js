import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { close, listen, postScore, request, scoreBody, uuid, withServer } from './helpers.js';
import { createServer } from '../src/index.js';

const NATASHA = '11111111-1111-4111-8111-111111111111';
const STEVE = '22222222-2222-4222-8222-222222222222';
const KEY = 'devkey';

describe('healthz and routing', () => {
  it('GET /healthz returns ok and the store label', async () => {
    await withServer(async ({ port }) => {
      const res = await request(port, 'GET', '/healthz');
      assert.equal(res.status, 200);
      assert.equal(res.json.ok, true);
      assert.match(res.json.store, /^(memory|sqlite)$/);
    });
  });

  it('unknown routes are 404', async () => {
    await withServer(async ({ port }) => {
      const res = await request(port, 'GET', '/nope');
      assert.equal(res.status, 404);
      assert.equal(res.json.error, 'not_found');
    });
  });
});

describe('POST /v1/scores happy path', () => {
  it('returns rank, best, is_personal_best, total_players', async () => {
    await withServer(async ({ port }) => {
      const res = await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 4800 });
      assert.equal(res.status, 201);
      assert.deepEqual(res.json, {
        rank: 1,
        best: 4800,
        is_personal_best: true,
        total_players: 1,
      });
    });
  });

  it('a lower second score keeps best and is_personal_best=false', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 4800 });
      const res = await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 300 });
      assert.equal(res.status, 201);
      assert.equal(res.json.best, 4800);
      assert.equal(res.json.is_personal_best, false);
      assert.equal(res.json.rank, 1);
    });
  });
});

describe('latest name wins', () => {
  it('board shows the latest name with the best score', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'A', score: 500 });
      await postScore(port, { player_id: NATASHA, name: 'A2', score: 300 });
      const board = await request(port, 'GET', '/v1/leaderboard?limit=5');
      assert.equal(board.status, 200);
      assert.equal(board.json.entries.length, 1);
      assert.equal(board.json.entries[0].name, 'A2');
      assert.equal(board.json.entries[0].score, 500);
      const me = await request(port, 'GET', `/v1/leaderboard/me?player_id=${NATASHA}`);
      assert.equal(me.json.name, 'A2');
      assert.equal(me.json.best, 500);
    });
  });
});

describe('leaderboard ordering and ties', () => {
  it('one row per player, higher score first, ties share rank and keep order', async () => {
    await withServer(async ({ port }) => {
      const third = uuid();
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 500 });
      await postScore(port, { player_id: STEVE, name: 'Steve', score: 500 });
      await postScore(port, { player_id: third, name: 'Pip', score: 400 });

      const first = await request(port, 'GET', '/v1/leaderboard?limit=50');
      const second = await request(port, 'GET', '/v1/leaderboard?limit=50');
      assert.deepEqual(first.json, second.json);
      assert.equal(first.json.total_players, 3);
      assert.equal(first.json.entries.length, 3);
      assert.equal(first.json.entries[0].score, 500);
      assert.equal(first.json.entries[1].score, 500);
      assert.equal(first.json.entries[0].rank, 1);
      assert.equal(first.json.entries[1].rank, 1);
      assert.equal(first.json.entries[2].rank, 3);
      assert.equal(first.json.entries[2].score, 400);
      assert.equal(first.json.entries[0].player_id, NATASHA);
      assert.equal(first.json.entries[1].player_id, STEVE);
    });
  });

  it('clamps limit to 1..50', async () => {
    await withServer(async ({ port }) => {
      for (let i = 0; i < 3; i += 1) {
        await postScore(port, { player_id: uuid(), name: `P${i}`, score: 100 + i });
      }
      const zero = await request(port, 'GET', '/v1/leaderboard?limit=0');
      assert.equal(zero.json.entries.length, 1);
      const huge = await request(port, 'GET', '/v1/leaderboard?limit=100');
      assert.equal(huge.json.entries.length, 3);
      const def = await request(port, 'GET', '/v1/leaderboard');
      assert.equal(def.json.entries.length, 3);
    });
  });
});

describe('GET /v1/leaderboard/me', () => {
  it('404 for an unknown player', async () => {
    await withServer(async ({ port }) => {
      const res = await request(port, 'GET', `/v1/leaderboard/me?player_id=${NATASHA}`);
      assert.equal(res.status, 404);
      assert.equal(res.json.error, 'unknown_player');
    });
  });

  it('400 for a bad uuid', async () => {
    await withServer(async ({ port }) => {
      const res = await request(port, 'GET', '/v1/leaderboard/me?player_id=not-a-uuid');
      assert.equal(res.status, 400);
      assert.equal(res.json.error, 'invalid_player_id');
    });
  });
});

describe('validation and auth errors', () => {
  it('400 on bad uuid, empty name, control-char name, negative or float score', async () => {
    await withServer(async ({ port }) => {
      const badUuid = await postScore(port, { player_id: 'nope', name: 'Natasha', score: 1 });
      assert.equal(badUuid.status, 400);
      assert.equal(badUuid.json.error, 'invalid_player_id');

      const empty = await postScore(port, { player_id: NATASHA, name: '   ', score: 1 });
      assert.equal(empty.status, 400);
      assert.equal(empty.json.error, 'invalid_name');

      const control = await postScore(port, { player_id: NATASHA, name: 'Nat\u0001asha', score: 1 });
      assert.equal(control.status, 400);
      assert.equal(control.json.error, 'invalid_name');

      const neg = await postScore(port, { player_id: NATASHA, score: -1 });
      assert.equal(neg.status, 400);
      assert.equal(neg.json.error, 'invalid_score');

      const flt = await postScore(port, { player_id: NATASHA, score: 1.5 });
      assert.equal(flt.status, 400);
      assert.equal(flt.json.error, 'invalid_score');
    });
  });

  it('400 on invalid JSON and on a body over 4 KB', async () => {
    await withServer(async ({ port }) => {
      const bad = await request(port, 'POST', '/v1/scores', {
        key: KEY,
        body: '{not json',
      });
      assert.equal(bad.status, 400);
      assert.equal(bad.json.error, 'invalid_json');

      const huge = await request(port, 'POST', '/v1/scores', {
        key: KEY,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          player_id: NATASHA,
          name: 'Natasha',
          score: 1,
          client: 'squish/1.0',
          pad: 'x'.repeat(5000),
        }),
      });
      assert.equal(huge.status, 400);
      assert.equal(huge.json.error, 'body_too_large');
    });
  });

  it('401 on a wrong or missing key', async () => {
    await withServer(async ({ port }) => {
      const wrong = await request(port, 'POST', '/v1/scores', {
        key: 'nope',
        body: scoreBody({ player_id: NATASHA }),
      });
      assert.equal(wrong.status, 401);
      assert.equal(wrong.json.error, 'unauthorized');

      const missing = await request(port, 'POST', '/v1/scores', {
        body: scoreBody({ player_id: NATASHA }),
      });
      assert.equal(missing.status, 401);
      assert.equal(missing.json.error, 'unauthorized');
    });
  });

  it('429 on the 31st post in a minute', async () => {
    await withServer(async ({ port }) => {
      let last;
      for (let i = 0; i < 31; i += 1) {
        last = await postScore(port, { player_id: NATASHA, name: 'Natasha', score: i });
      }
      assert.equal(last.status, 429);
      assert.equal(last.json.error, 'rate_limited');
    });
  });
});

describe('file DB restart', () => {
  it('schema survives a restart on a file DB with existing rows', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'squish-'));
    const path = join(dir, 'squish.db');
    try {
      const first = createServer({ dbPath: path, key: KEY });
      const port1 = await listen(first);
      const posted = await postScore(port1, { player_id: NATASHA, name: 'Natasha', score: 4800 });
      assert.equal(posted.status, 201);
      await close(first);

      const second = createServer({ dbPath: path, key: KEY });
      const port2 = await listen(second);
      const board = await request(port2, 'GET', '/v1/leaderboard?limit=5');
      assert.equal(board.status, 200);
      assert.equal(board.json.entries.length, 1);
      assert.equal(board.json.entries[0].score, 4800);
      assert.equal(board.json.entries[0].name, 'Natasha');
      await close(second);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
