import { randomUUID } from 'node:crypto';
import { createServer } from '../src/index.js';

const KEY = 'devkey';

export function dbPathForSuite() {
  const env = process.env.DB_PATH;
  if (!env || env === ':memory:') return ':memory:';
  return `${env}.${process.pid}.${Date.now()}.${Math.random().toString(16).slice(2)}`;
}

export function uuid() {
  return randomUUID();
}

export async function listen(server) {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const { port } = server.address();
  return port;
}

export async function close(server) {
  await new Promise((resolve) => server.close(resolve));
}

export async function withServer(fn, options = {}) {
  const server = createServer({
    dbPath: options.dbPath ?? dbPathForSuite(),
    key: options.key ?? KEY,
    limiter: options.limiter,
    catalogPath: options.catalogPath,
    repoRoot: options.repoRoot,
    catalog: options.catalog,
  });
  const port = await listen(server);
  try {
    return await fn({ server, port, key: options.key ?? KEY });
  } finally {
    await close(server);
  }
}

export async function request(port, method, path, { key, body, headers } = {}) {
  const res = await fetch(`http://127.0.0.1:${port}${path}`, {
    method,
    headers: {
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
      ...(key !== undefined ? { 'X-Squish-Key': key } : {}),
      ...headers,
    },
    body: body !== undefined ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined,
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = text;
  }
  return { status: res.status, json };
}

export function scoreBody(overrides = {}) {
  return {
    player_id: overrides.player_id ?? uuid(),
    name: overrides.name ?? 'Natasha',
    score: overrides.score ?? 4800,
    client: overrides.client ?? 'squish/1.0',
  };
}

export function postScore(port, body, key = KEY) {
  return request(port, 'POST', '/v1/scores', { key, body: scoreBody(body) });
}

export function profileBody(overrides = {}) {
  return {
    player_id: overrides.player_id ?? uuid(),
    name: overrides.name ?? 'Natasha',
    avatar: overrides.avatar ?? '',
    client: overrides.client ?? 'squish/1.0',
  };
}

export function putProfile(port, body, key = KEY) {
  return request(port, 'PUT', '/v1/profile', { key, body: profileBody(body) });
}

export async function requestBinary(port, method, path) {
  const res = await fetch(`http://127.0.0.1:${port}${path}`, { method });
  const body = Buffer.from(await res.arrayBuffer());
  return { status: res.status, headers: res.headers, body };
}
