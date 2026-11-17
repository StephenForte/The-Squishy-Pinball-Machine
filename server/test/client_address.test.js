import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { clientAddress, createRateLimiter } from '../src/index.js';
import { profileBody, request, scoreBody, withServer } from './helpers.js';

describe('client address resolution (D-065)', () => {
  const cases = [
    ['CF takes precedence over all XFF hops', {
      'cf-connecting-ip': ' 203.0.113.1 ',
      'x-forwarded-for': '192.0.2.1, 198.51.100.1',
    }, '203.0.113.1'],
    ['empty CF falls through to XFF', {
      'cf-connecting-ip': '', 'x-forwarded-for': '192.0.2.1, 198.51.100.1',
    }, '198.51.100.1'],
    ['whitespace CF falls through to XFF', {
      'cf-connecting-ip': ' \t ', 'x-forwarded-for': '192.0.2.1, 198.51.100.1',
    }, '198.51.100.1'],
    ['right-most non-empty XFF hop is trimmed', {
      'x-forwarded-for': ', 192.0.2.1, , 198.51.100.1 , , ',
    }, '198.51.100.1'],
    ['single-hop XFF is supported', { 'x-forwarded-for': ' 198.51.100.1 ' }, '198.51.100.1'],
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
    for (const socket of [undefined, {}, { remoteAddress: '' }]) {
      assert.equal(clientAddress({ headers: {}, socket }), 'unknown');
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

describe('edge-asserted buckets on every per-IP route (D-065)', () => {
  const routes = [
    ['POST', '/v1/scores', scoreBody(), 201],
    ['PUT', '/v1/profile', profileBody(), 200],
    ['GET', '/v1/players/lookup?name=Probe', undefined, 200],
    ['POST', '/v1/players/resolve', { name: 'Probe' }, 201],
    ['GET', '/player?name=Probe', undefined, 404],
  ];
  for (const [method, path, body, initialStatus] of routes) {
    for (const edge of ['CF', 'XFF']) {
      it(`${method} ${path}: ${edge} prevents XFF spoofing and keeps edge addresses independent`, async () => {
        await withServer(async ({ port, key }) => {
          const headersFor = (spoof, address) => edge === 'CF'
            ? { 'CF-Connecting-IP': address, 'X-Forwarded-For': spoof }
            : { 'X-Forwarded-For': `${spoof}, ${address}, , ` };
          const first = await request(port, method, path, {
            key, body, headers: headersFor('192.0.2.1', '203.0.113.1'),
          });
          assert.equal(first.status, initialStatus);
          // With CF set, this replaces the entire XFF header. Otherwise only
          // the client-supplied left-most hop changes; the edge hop stays put.
          const blocked = await request(port, method, path, {
            key, body, headers: headersFor('192.0.2.2', '203.0.113.1'),
          });
          assert.equal(blocked.status, 429);
          if (path.startsWith('/player?')) {
            assert.match(blocked.headers.get('content-type'), /text\/html/);
          } else {
            assert.equal(blocked.json.error, 'rate_limited');
          }
          const independent = await request(port, method, path, {
            key, body, headers: headersFor('192.0.2.2', '198.51.100.1'),
          });
          assert.equal(independent.status, path === '/v1/players/resolve' ? 200 : initialStatus);
        }, {
          ipLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }),
          resolveLimiter: createRateLimiter({ windowMs: 60_000, max: 1 }),
        });
      });
    }
  }
});
