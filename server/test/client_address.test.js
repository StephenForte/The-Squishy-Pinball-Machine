import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { clientAddress, createRateLimiter } from '../src/index.js';
import { profileBody, request, scoreBody, withServer } from './helpers.js';

describe('client address resolution (D-066)', () => {
  const cases = [
    ['CF takes precedence over all XFF hops', {
      'cf-connecting-ip': ' 203.0.113.1 ',
      'x-forwarded-for': '192.0.2.1, 198.51.100.1',
    }, '203.0.113.1'],
    ['empty CF falls through to the socket', {
      'cf-connecting-ip': '', 'x-forwarded-for': '192.0.2.1, 198.51.100.1',
    }, 'socket-address'],
    ['whitespace CF falls through to the socket', {
      'cf-connecting-ip': ' \t ', 'x-forwarded-for': '192.0.2.1, 198.51.100.1',
    }, 'socket-address'],
    ['multi-hop XFF falls through to the socket', {
      'x-forwarded-for': ', 192.0.2.1, , 198.51.100.1 , , ',
    }, 'socket-address'],
    ['single-hop XFF falls through to the same socket', {
      'x-forwarded-for': '198.51.100.2',
    }, 'socket-address'],
    ['True-Client-IP falls through to the socket', {
      'true-client-ip': '198.51.100.1',
    }, 'socket-address'],
    ['missing headers fall through to the socket', {}, 'socket-address'],
    ['empty headers fall through to the socket', {
      'cf-connecting-ip': ' ', 'x-forwarded-for': ', , ',
    }, 'socket-address'],
  ];
  for (const [name, headers, expected] of cases) {
    it(name, () => {
      assert.equal(clientAddress({ headers, socket: { remoteAddress: 'socket-address' } }), expected);
    });
  }

  it('missing or empty socket addresses share unknown', () => {
    const headers = {
      'x-forwarded-for': '192.0.2.1',
      'true-client-ip': '198.51.100.1',
    };
    for (const socket of [undefined, {}, { remoteAddress: '' }]) {
      assert.equal(clientAddress({ headers, socket }), 'unknown');
    }
  });

  it('addressFor overrides headers and the socket, including the unknown bucket', () => {
    const req = { headers: { 'cf-connecting-ip': '203.0.113.1' }, socket: { remoteAddress: 'socket' } };
    assert.equal(clientAddress(req, (incoming) => {
      assert.equal(incoming, req);
      return 'injected-address';
    }), 'injected-address');
    for (const value of ['', undefined, null]) {
      assert.equal(clientAddress(req, () => value), 'unknown');
    }
  });
});

describe('client address buckets on every per-IP route (D-066)', () => {
  const routes = [
    ['POST', '/v1/scores', scoreBody(), 201],
    ['PUT', '/v1/profile', profileBody(), 200],
    ['GET', '/v1/players/lookup?name=Probe', undefined, 200],
    ['POST', '/v1/players/resolve', { name: 'Probe' }, 201],
    ['GET', '/player?name=Probe', undefined, 404],
  ];
  for (const [method, path, body, initialStatus] of routes) {
    it(`${method} ${path}: adding or changing XFF leaves the socket bucket exhausted`, async () => {
      await withServer(async ({ port, key }) => {
        const first = await request(port, method, path, { key, body });
        assert.equal(first.status, initialStatus);

        for (const xff of ['192.0.2.1', '192.0.2.2, 198.51.100.1']) {
          const blocked = await request(port, method, path, {
            key, body, headers: { 'X-Forwarded-For': xff },
          });
          assert.equal(blocked.status, 429);
          if (path.startsWith('/player?')) {
            assert.match(blocked.headers.get('content-type'), /text\/html/);
          } else {
            assert.equal(blocked.json.error, 'rate_limited');
          }
        }
      }, {
        ipLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }),
        resolveLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }),
      });
    });

    it(`${method} ${path}: CF addresses get independent buckets and ignore XFF`, async () => {
      await withServer(async ({ port, key }) => {
        const send = (cf, xff) => request(port, method, path, {
          key, body, headers: { 'CF-Connecting-IP': cf, 'X-Forwarded-For': xff },
        });
        const first = await send('203.0.113.1', '192.0.2.1');
        assert.equal(first.status, initialStatus);
        const blocked = await send('203.0.113.1', '192.0.2.2');
        assert.equal(blocked.status, 429);
        if (path.startsWith('/player?')) {
          assert.match(blocked.headers.get('content-type'), /text\/html/);
        } else {
          assert.equal(blocked.json.error, 'rate_limited');
        }
        const independent = await send('198.51.100.1', '192.0.2.2');
        assert.equal(independent.status, path === '/v1/players/resolve' ? 200 : initialStatus);
      }, {
        ipLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }),
        resolveLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }),
      });
    });
  }
});
