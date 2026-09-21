import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createRateLimiter } from '../src/index.js';
import {
  postScore,
  profileBody,
  putProfile,
  request,
  scoreBody,
  withServer,
} from './helpers.js';

const NATASHA = '11111111-1111-4111-8111-111111111111';
const STEVE = '22222222-2222-4222-8222-222222222222';
const PIP = '33333333-3333-4333-8333-333333333333';
const WRITE_KEY = 'devkey';
const ADMIN_KEY = 'admin-secret';
const ORIGIN = 'https://play.example';

const ADMIN_PATHS = [
  ['DELETE', '/v1/scores/1'],
  ['DELETE', `/v1/profile/${NATASHA}`],
  ['POST', '/v1/admin/reset'],
];

function corsNames(headers) {
  return [...headers.keys()].filter((name) => name.startsWith('access-control-'));
}

describe('admin routes disabled when the key is blank (D-046)', () => {
  it('blank admin key → every admin route 404, and no route leaks that it exists', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 14300 });
      await putProfile(port, { player_id: NATASHA, name: 'Natasha', avatar: 'bear_bounce' });

      for (const [method, path] of ADMIN_PATHS) {
        const noHeader = await request(port, method, path, {
          body: method === 'POST' ? { confirm: 'RESET' } : undefined,
        });
        assert.equal(noHeader.status, 404, `${method} ${path} no header`);
        assert.equal(noHeader.json.error, 'not_found');

        const withHeader = await request(port, method, path, {
          headers: { 'X-Squish-Admin': ADMIN_KEY },
          body: method === 'POST' ? { confirm: 'RESET' } : undefined,
        });
        assert.equal(withHeader.status, 404, `${method} ${path} with header`);
        assert.equal(withHeader.json.error, 'not_found');

        const writeAsAdmin = await request(port, method, path, {
          headers: { 'X-Squish-Admin': WRITE_KEY },
          body: method === 'POST' ? { confirm: 'RESET' } : undefined,
        });
        assert.equal(writeAsAdmin.status, 404, `${method} ${path} write key`);
        assert.equal(writeAsAdmin.json.error, 'not_found');
      }

      const board = await request(port, 'GET', '/v1/leaderboard');
      assert.equal(board.json.entries.length, 1);
      assert.equal(board.json.entries[0].score, 14300);
      const profile = await request(port, 'GET', `/v1/profile?player_id=${NATASHA}`);
      assert.equal(profile.status, 200);
    });
  });
});

describe('admin auth when the key is set', () => {
  it('wrong key, missing header, and the write key in X-Squish-Admin are 401', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 100 });

      for (const [method, path] of ADMIN_PATHS) {
        const wrong = await request(port, method, path, {
          headers: { 'X-Squish-Admin': 'nope' },
          body: method === 'POST' ? { confirm: 'RESET' } : undefined,
        });
        assert.equal(wrong.status, 401, `${method} ${path} wrong`);
        assert.equal(wrong.json.error, 'unauthorized');

        const missing = await request(port, method, path, {
          body: method === 'POST' ? { confirm: 'RESET' } : undefined,
        });
        assert.equal(missing.status, 401, `${method} ${path} missing`);
        assert.equal(missing.json.error, 'unauthorized');

        const writeKey = await request(port, method, path, {
          headers: { 'X-Squish-Admin': WRITE_KEY },
          body: method === 'POST' ? { confirm: 'RESET' } : undefined,
        });
        assert.equal(writeKey.status, 401, `${method} ${path} write key`);
        assert.equal(writeKey.json.error, 'unauthorized');
      }
    }, { adminKey: ADMIN_KEY });
  });

  it('the admin key does not grant writes', async () => {
    await withServer(async ({ port }) => {
      const score = await request(port, 'POST', '/v1/scores', {
        key: ADMIN_KEY,
        body: scoreBody({ player_id: NATASHA }),
      });
      assert.equal(score.status, 401);
      assert.equal(score.json.error, 'unauthorized');

      const profile = await request(port, 'PUT', '/v1/profile', {
        key: ADMIN_KEY,
        body: profileBody({ player_id: NATASHA }),
      });
      assert.equal(profile.status, 401);
      assert.equal(profile.json.error, 'unauthorized');
    }, { adminKey: ADMIN_KEY });
  });
});

describe('DELETE /v1/scores/:id', () => {
  it('removes exactly that row, leaves the rest, and ranks recompute', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 1000 });
      await postScore(port, { player_id: STEVE, name: 'Steve', score: 2000 });
      await postScore(port, { player_id: PIP, name: 'Pip', score: 500 });

      const before = await request(port, 'GET', '/v1/leaderboard?limit=10');
      assert.equal(before.json.total_players, 3);
      assert.equal(before.json.entries[0].player_id, STEVE);
      assert.equal(before.json.entries[0].rank, 1);

      const deleted = await request(port, 'DELETE', '/v1/scores/2', {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
      });
      assert.equal(deleted.status, 200);
      assert.deepEqual(deleted.json, { ok: true });

      const after = await request(port, 'GET', '/v1/leaderboard?limit=10');
      assert.equal(after.json.total_players, 2);
      assert.equal(after.json.entries.length, 2);
      assert.equal(after.json.entries[0].player_id, NATASHA);
      assert.equal(after.json.entries[0].score, 1000);
      assert.equal(after.json.entries[0].rank, 1);
      assert.equal(after.json.entries[1].player_id, PIP);
      assert.equal(after.json.entries[1].score, 500);
      assert.equal(after.json.entries[1].rank, 2);
    }, { adminKey: ADMIN_KEY });
  });

  it('unknown id is 404', async () => {
    await withServer(async ({ port }) => {
      const res = await request(port, 'DELETE', '/v1/scores/99', {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
      });
      assert.equal(res.status, 404);
      assert.equal(res.json.error, 'not_found');
    }, { adminKey: ADMIN_KEY });
  });
});

describe('DELETE /v1/profile/:player_id', () => {
  it('removes only that profile; the player scores stay', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 4800 });
      await putProfile(port, { player_id: NATASHA, name: 'Natasha', avatar: 'bear_bounce' });
      await putProfile(port, { player_id: STEVE, name: 'Dad', avatar: 'frog_gus' });

      const deleted = await request(port, 'DELETE', `/v1/profile/${NATASHA}`, {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
      });
      assert.equal(deleted.status, 200);
      assert.deepEqual(deleted.json, { ok: true });

      const gone = await request(port, 'GET', `/v1/profile?player_id=${NATASHA}`);
      assert.equal(gone.status, 404);
      assert.equal(gone.json.error, 'unknown_profile');

      const kept = await request(port, 'GET', `/v1/profile?player_id=${STEVE}`);
      assert.equal(kept.status, 200);
      assert.equal(kept.json.avatar, 'frog_gus');

      const board = await request(port, 'GET', '/v1/leaderboard');
      assert.equal(board.json.entries.length, 1);
      assert.equal(board.json.entries[0].player_id, NATASHA);
      assert.equal(board.json.entries[0].score, 4800);
      assert.equal(board.json.entries[0].avatar, '');
    }, { adminKey: ADMIN_KEY });
  });

  it('malformed uuid is 400 invalid_player_id; unknown player is 404', async () => {
    await withServer(async ({ port }) => {
      const bad = await request(port, 'DELETE', '/v1/profile/not-a-uuid', {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
      });
      assert.equal(bad.status, 400);
      assert.equal(bad.json.error, 'invalid_player_id');

      const missing = await request(port, 'DELETE', `/v1/profile/${NATASHA}`, {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
      });
      assert.equal(missing.status, 404);
      assert.equal(missing.json.error, 'not_found');
    }, { adminKey: ADMIN_KEY });
  });
});

describe('POST /v1/admin/reset', () => {
  it('without the confirmation field is 400 and nothing is deleted', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 14300 });
      await putProfile(port, { player_id: NATASHA, name: 'Natasha', avatar: 'bear_bounce' });

      const empty = await request(port, 'POST', '/v1/admin/reset', {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
        body: {},
      });
      assert.equal(empty.status, 400);
      assert.equal(empty.json.error, 'confirmation_required');

      const wrong = await request(port, 'POST', '/v1/admin/reset', {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
        body: { confirm: true },
      });
      assert.equal(wrong.status, 400);
      assert.equal(wrong.json.error, 'confirmation_required');

      const board = await request(port, 'GET', '/v1/leaderboard');
      assert.equal(board.json.entries.length, 1);
      assert.equal(board.json.entries[0].score, 14300);
      const profile = await request(port, 'GET', `/v1/profile?player_id=${NATASHA}`);
      assert.equal(profile.status, 200);
    }, { adminKey: ADMIN_KEY });
  });

  it('with confirm RESET empties both tables and the board renders empty', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 14300 });
      await putProfile(port, { player_id: NATASHA, name: 'Natasha', avatar: 'bear_bounce' });

      const reset = await request(port, 'POST', '/v1/admin/reset', {
        headers: { 'X-Squish-Admin': ADMIN_KEY },
        body: { confirm: 'RESET' },
      });
      assert.equal(reset.status, 200);
      assert.deepEqual(reset.json, { ok: true });

      const board = await request(port, 'GET', '/v1/leaderboard');
      assert.equal(board.status, 200);
      assert.deepEqual(board.json.entries, []);
      assert.equal(board.json.total_players, 0);

      const home = await fetch(`http://127.0.0.1:${port}/`);
      assert.equal(home.status, 200);
      const html = await home.text();
      assert.match(html, /No scores yet/);
      assert.doesNotMatch(html, /Natasha/);

      const profile = await request(port, 'GET', `/v1/profile?player_id=${NATASHA}`);
      assert.equal(profile.status, 404);
    }, { adminKey: ADMIN_KEY });
  });
});

describe('admin routes are excluded from CORS', () => {
  it('no admin route ever sends a CORS header, even from a listed origin', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 100 });
      await putProfile(port, { player_id: NATASHA, name: 'Natasha', avatar: 'bear_bounce' });

      for (const [method, path] of ADMIN_PATHS) {
        const res = await request(port, method, path, {
          headers: { Origin: ORIGIN, 'X-Squish-Admin': ADMIN_KEY },
          body: method === 'POST' ? { confirm: 'RESET' } : undefined,
        });
        assert.ok(res.status < 500, `${method} ${path} ${res.status}`);
        assert.equal(res.headers.get('access-control-allow-origin'), null);
        assert.equal(corsNames(res.headers).length, 0, `${method} ${path}`);
      }

      const preflightScore = await request(port, 'OPTIONS', '/v1/scores/1', {
        headers: { Origin: ORIGIN },
      });
      assert.equal(preflightScore.status, 404);
      assert.equal(corsNames(preflightScore.headers).length, 0);

      const preflightProfile = await request(port, 'OPTIONS', `/v1/profile/${NATASHA}`, {
        headers: { Origin: ORIGIN },
      });
      assert.equal(preflightProfile.status, 404);
      assert.equal(corsNames(preflightProfile.headers).length, 0);

      const preflightReset = await request(port, 'OPTIONS', '/v1/admin/reset', {
        headers: { Origin: ORIGIN },
      });
      assert.equal(preflightReset.status, 404);
      assert.equal(corsNames(preflightReset.headers).length, 0);
    }, { adminKey: ADMIN_KEY, allowedOrigins: [ORIGIN] });
  });
});

describe('per-IP write limiting (D-046)', () => {
  it('two player_ids from the same address hit the per-IP ceiling', async () => {
    await withServer(async ({ port }) => {
      const first = await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 1 });
      const second = await postScore(port, { player_id: STEVE, name: 'Steve', score: 1 });
      const third = await postScore(port, { player_id: PIP, name: 'Pip', score: 1 });
      assert.equal(first.status, 201);
      assert.equal(second.status, 201);
      assert.equal(third.status, 429);
      assert.equal(third.json.error, 'rate_limited');
    }, {
      limiter: { allow: () => true },
      ipLimiter: createRateLimiter({ windowMs: 60_000, max: 2 }),
    });
  });

  it('different addresses are independent buckets', async () => {
    await withServer(async ({ port }) => {
      const a1 = await request(port, 'POST', '/v1/scores', {
        key: WRITE_KEY,
        body: scoreBody({ player_id: NATASHA, score: 1 }),
        headers: { 'X-Forwarded-For': '203.0.113.1' },
      });
      const a2 = await request(port, 'POST', '/v1/scores', {
        key: WRITE_KEY,
        body: scoreBody({ player_id: NATASHA, score: 2 }),
        headers: { 'X-Forwarded-For': '203.0.113.1' },
      });
      const b1 = await request(port, 'POST', '/v1/scores', {
        key: WRITE_KEY,
        body: scoreBody({ player_id: STEVE, score: 1 }),
        headers: { 'X-Forwarded-For': '198.51.100.9, 10.0.0.1' },
      });
      assert.equal(a1.status, 201);
      assert.equal(a2.status, 429);
      assert.equal(b1.status, 201);
    }, {
      limiter: { allow: () => true },
      ipLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }),
    });
  });

  it('a missing address does not mean unlimited', async () => {
    await withServer(async ({ port }) => {
      const first = await postScore(port, { player_id: NATASHA, name: 'A', score: 1 });
      const second = await postScore(port, { player_id: STEVE, name: 'B', score: 1 });
      const third = await postScore(port, { player_id: PIP, name: 'C', score: 1 });
      assert.equal(first.status, 201);
      assert.equal(second.status, 201);
      assert.equal(third.status, 429);
    }, {
      limiter: { allow: () => true },
      ipLimiter: createRateLimiter({ windowMs: 60_000, max: 2 }),
      addressFor: () => '',
    });
  });

  it('the existing 30-per-minute per-player limit still applies', async () => {
    await withServer(async ({ port }) => {
      let last;
      for (let i = 0; i < 31; i += 1) {
        last = await postScore(port, { player_id: NATASHA, name: 'Natasha', score: i });
      }
      assert.equal(last.status, 429);
      assert.equal(last.json.error, 'rate_limited');

      const other = await postScore(port, { player_id: STEVE, name: 'Steve', score: 1 });
      assert.equal(other.status, 201);
    }, {
      ipLimiter: createRateLimiter({ windowMs: 60_000, max: 1000 }),
    });
  });
});
