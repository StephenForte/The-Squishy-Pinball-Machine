import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { originAllowed, parseAllowedOrigins } from '../src/index.js';
import { postScore, request, withServer } from './helpers.js';

const ORIGIN_A = 'https://play.example';
const ORIGIN_B = 'https://family.example';
const FOREIGN = 'https://evil.example';
const NATASHA = '11111111-1111-4111-8111-111111111111';

function corsNames(headers) {
  return [...headers.keys()].filter((name) => name.startsWith('access-control-'));
}

describe('CORS fail-closed (D-044)', () => {
  it('no SQUISH_ALLOWED_ORIGINS → no CORS header on any response', async () => {
    await withServer(async ({ port }) => {
      const board = await request(port, 'GET', '/v1/leaderboard', {
        headers: { Origin: FOREIGN },
      });
      assert.equal(board.status, 200);
      assert.equal(board.headers.get('access-control-allow-origin'), null);
      assert.equal(corsNames(board.headers).length, 0);

      const preflight = await request(port, 'OPTIONS', '/v1/profile', {
        headers: {
          Origin: FOREIGN,
          'Access-Control-Request-Method': 'PUT',
          'Access-Control-Request-Headers': 'content-type, x-squish-key',
        },
      });
      assert.equal(preflight.status, 204);
      assert.equal(preflight.headers.get('access-control-allow-origin'), null);
      assert.equal(corsNames(preflight.headers).length, 0);
    });
  });

  it('a listed origin is echoed with Vary: Origin; preflight is 204', async () => {
    await withServer(async ({ port }) => {
      const board = await request(port, 'GET', '/v1/leaderboard', {
        headers: { Origin: ORIGIN_A },
      });
      assert.equal(board.status, 200);
      assert.equal(board.headers.get('access-control-allow-origin'), ORIGIN_A);
      assert.equal(board.headers.get('vary'), 'Origin');

      const preflight = await request(port, 'OPTIONS', '/v1/profile', {
        headers: {
          Origin: ORIGIN_A,
          'Access-Control-Request-Method': 'PUT',
          'Access-Control-Request-Headers': 'content-type, x-squish-key',
        },
      });
      assert.equal(preflight.status, 204);
      assert.equal(preflight.headers.get('access-control-allow-origin'), ORIGIN_A);
      assert.equal(preflight.headers.get('vary'), 'Origin');
      const methods = preflight.headers.get('access-control-allow-methods');
      assert.match(methods, /GET/);
      assert.match(methods, /POST/);
      assert.match(methods, /PUT/);
      const allowHeaders = preflight.headers.get('access-control-allow-headers').toLowerCase();
      assert.match(allowHeaders, /content-type/);
      assert.match(allowHeaders, /x-squish-key/);
    }, { allowedOrigins: [ORIGIN_A, ORIGIN_B] });
  });

  it('an unlisted origin gets no CORS header; the request still succeeds', async () => {
    await withServer(async ({ port }) => {
      await postScore(port, { player_id: NATASHA, name: 'Natasha', score: 100 });
      const board = await request(port, 'GET', '/v1/leaderboard', {
        headers: { Origin: FOREIGN },
      });
      assert.equal(board.status, 200);
      assert.equal(board.json.entries.length, 1);
      assert.equal(board.headers.get('access-control-allow-origin'), null);
      assert.equal(corsNames(board.headers).length, 0);

      const preflight = await request(port, 'OPTIONS', '/v1/scores', {
        headers: { Origin: FOREIGN },
      });
      assert.equal(preflight.status, 204);
      assert.equal(corsNames(preflight.headers).length, 0);
    }, { allowedOrigins: [ORIGIN_A] });
  });

  it('* in the env var is treated as no match, not a wildcard', async () => {
    await withServer(async ({ port }) => {
      const star = await request(port, 'GET', '/v1/leaderboard', {
        headers: { Origin: '*' },
      });
      assert.equal(star.status, 200);
      assert.equal(star.headers.get('access-control-allow-origin'), null);

      const listed = await request(port, 'GET', '/v1/leaderboard', {
        headers: { Origin: ORIGIN_A },
      });
      assert.equal(listed.status, 200);
      assert.equal(listed.headers.get('access-control-allow-origin'), null);
      assert.equal(corsNames(listed.headers).length, 0);
    }, { allowedOrigins: '*' });
  });

  it('a second listed origin works and neither leaks the other header', async () => {
    await withServer(async ({ port }) => {
      const a = await request(port, 'GET', '/v1/leaderboard', {
        headers: { Origin: ORIGIN_A },
      });
      assert.equal(a.headers.get('access-control-allow-origin'), ORIGIN_A);
      assert.notEqual(a.headers.get('access-control-allow-origin'), ORIGIN_B);

      const b = await request(port, 'GET', '/v1/leaderboard', {
        headers: { Origin: ORIGIN_B },
      });
      assert.equal(b.headers.get('access-control-allow-origin'), ORIGIN_B);
      assert.notEqual(b.headers.get('access-control-allow-origin'), ORIGIN_A);
    }, { allowedOrigins: `${ORIGIN_A}, *, ${ORIGIN_B}` });
  });

  it('lookup is on the public list: a listed origin is echoed on GET and OPTIONS', async () => {
    await withServer(async ({ port }) => {
      const got = await request(port, 'GET', '/v1/players/lookup?name=Dad', {
        headers: { Origin: ORIGIN_A },
      });
      assert.equal(got.status, 200);
      assert.equal(got.headers.get('access-control-allow-origin'), ORIGIN_A);
      assert.equal(got.headers.get('vary'), 'Origin');

      const preflight = await request(port, 'OPTIONS', '/v1/players/lookup', {
        headers: {
          Origin: ORIGIN_A,
          'Access-Control-Request-Method': 'GET',
        },
      });
      assert.equal(preflight.status, 204);
      assert.equal(preflight.headers.get('access-control-allow-origin'), ORIGIN_A);
      assert.match(preflight.headers.get('access-control-allow-methods'), /GET/);

      const foreign = await request(port, 'GET', '/v1/players/lookup?name=Dad', {
        headers: { Origin: FOREIGN },
      });
      assert.equal(foreign.status, 200);
      assert.equal(foreign.headers.get('access-control-allow-origin'), null);
      assert.equal(corsNames(foreign.headers).length, 0);

      const foreignPreflight = await request(port, 'OPTIONS', '/v1/players/lookup', {
        headers: {
          Origin: FOREIGN,
          'Access-Control-Request-Method': 'GET',
        },
      });
      assert.equal(foreignPreflight.status, 204);
      assert.equal(foreignPreflight.headers.get('access-control-allow-origin'), null);
      assert.equal(corsNames(foreignPreflight.headers).length, 0);
    }, { allowedOrigins: [ORIGIN_A] });
  });
});

describe('parseAllowedOrigins and originAllowed', () => {
  it('splits, trims, and drops empty parts and *', () => {
    assert.deepEqual(parseAllowedOrigins(undefined), []);
    assert.deepEqual(parseAllowedOrigins(null), []);
    assert.deepEqual(parseAllowedOrigins(''), []);
    assert.deepEqual(parseAllowedOrigins('*'), []);
    assert.deepEqual(parseAllowedOrigins(' https://a.example , *, https://b.example '), [
      'https://a.example',
      'https://b.example',
    ]);
    assert.deepEqual(parseAllowedOrigins(['https://a.example', '', '*', 'https://b.example']), [
      'https://a.example',
      'https://b.example',
    ]);
  });

  it('matches only an exact listed origin', () => {
    const allowed = parseAllowedOrigins(`${ORIGIN_A}, ${ORIGIN_B}`);
    assert.equal(originAllowed(ORIGIN_A, allowed), true);
    assert.equal(originAllowed(ORIGIN_B, allowed), true);
    assert.equal(originAllowed(FOREIGN, allowed), false);
    assert.equal(originAllowed('', allowed), false);
    assert.equal(originAllowed('*', allowed), false);
    assert.equal(originAllowed(ORIGIN_A, []), false);
    assert.equal(originAllowed(ORIGIN_A, null), false);
  });
});
