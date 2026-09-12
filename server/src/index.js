import { timingSafeEqual } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { createCatalog } from './catalog.js';
import { closeDb, getLeaderboard, getMe, getProfile, insertScore, openDb, storeLabel, upsertProfile } from './db.js';
import { renderBoard } from './page.js';
import { isUuidV4, normalizePlayerId, parseLimit, parseProfileBody, parseScoreBody } from './validate.js';

const BODY_LIMIT = 4096;
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 30;

export function createRateLimiter({ windowMs = RATE_WINDOW_MS, max = RATE_MAX } = {}) {
  const hits = new Map();
  return {
    allow(playerId) {
      const now = Date.now();
      for (const [id, times] of hits) {
        const fresh = times.filter((t) => now - t < windowMs);
        if (fresh.length === 0) hits.delete(id);
        else hits.set(id, fresh);
      }
      const times = hits.get(playerId) ?? [];
      if (times.length >= max) return false;
      times.push(now);
      hits.set(playerId, times);
      return true;
    },
  };
}

function keysMatch(provided, expected) {
  if (typeof provided !== 'string' || typeof expected !== 'string' || expected.length === 0) {
    return false;
  }
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(payload),
  });
  res.end(payload);
}

function sendHtml(res, status, html) {
  res.writeHead(status, {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store',
    'content-length': Buffer.byteLength(html),
  });
  res.end(html);
}

function sendPng(res, data) {
  res.writeHead(200, {
    'content-type': 'image/png',
    'cache-control': 'public, max-age=86400',
    'content-length': data.length,
  });
  res.end(data);
}

function readBody(req, limit = BODY_LIMIT) {
  return new Promise((resolve, reject) => {
    const declared = req.headers['content-length'];
    if (declared !== undefined && Number(declared) > limit) {
      const err = new Error('body_too_large');
      err.code = 'body_too_large';
      reject(err);
      req.resume();
      return;
    }

    const chunks = [];
    let size = 0;
    let settled = false;

    const fail = (code) => {
      if (settled) return;
      settled = true;
      const err = new Error(code);
      err.code = code;
      req.destroy();
      reject(err);
    };

    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) {
        fail('body_too_large');
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (settled) return;
      settled = true;
      resolve(Buffer.concat(chunks));
    });
    req.on('error', (err) => {
      if (settled) return;
      settled = true;
      reject(err);
    });
  });
}

async function handle(req, res, ctx) {
  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;

  if (req.method === 'GET' && path === '/') {
    sendHtml(res, 200, renderBoard(getLeaderboard(ctx.db, 10)));
    return;
  }

  if (req.method === 'GET' && path === '/healthz') {
    send(res, 200, { ok: true, store: ctx.store });
    return;
  }

  if (req.method === 'POST' && path === '/v1/scores') {
    if (!keysMatch(req.headers['x-squish-key'], ctx.key)) {
      send(res, 401, { error: 'unauthorized' });
      return;
    }

    let raw;
    try {
      raw = await readBody(req);
    } catch (err) {
      if (err.code === 'body_too_large') {
        send(res, 400, { error: 'body_too_large' });
        return;
      }
      send(res, 400, { error: 'invalid_json' });
      return;
    }

    let body;
    try {
      body = JSON.parse(raw.toString('utf8'));
    } catch {
      send(res, 400, { error: 'invalid_json' });
      return;
    }

    const parsed = parseScoreBody(body);
    if (!parsed.ok) {
      send(res, 400, { error: parsed.error });
      return;
    }

    if (!ctx.limiter.allow(parsed.value.player_id)) {
      send(res, 429, { error: 'rate_limited' });
      return;
    }

    const result = insertScore(ctx.db, parsed.value);
    send(res, 201, result);
    return;
  }

  if (req.method === 'GET' && path === '/v1/leaderboard') {
    const limit = parseLimit(url.searchParams.get('limit'));
    send(res, 200, getLeaderboard(ctx.db, limit));
    return;
  }

  if (req.method === 'GET' && path === '/v1/leaderboard/me') {
    const playerId = url.searchParams.get('player_id');
    if (!isUuidV4(playerId)) {
      send(res, 400, { error: 'invalid_player_id' });
      return;
    }
    const me = getMe(ctx.db, normalizePlayerId(playerId));
    if (!me) {
      send(res, 404, { error: 'unknown_player' });
      return;
    }
    send(res, 200, me);
    return;
  }

  if (req.method === 'PUT' && path === '/v1/profile') {
    if (!keysMatch(req.headers['x-squish-key'], ctx.key)) {
      send(res, 401, { error: 'unauthorized' });
      return;
    }

    let raw;
    try {
      raw = await readBody(req);
    } catch (err) {
      if (err.code === 'body_too_large') {
        send(res, 400, { error: 'body_too_large' });
        return;
      }
      send(res, 400, { error: 'invalid_json' });
      return;
    }

    let body;
    try {
      body = JSON.parse(raw.toString('utf8'));
    } catch {
      send(res, 400, { error: 'invalid_json' });
      return;
    }

    const parsed = parseProfileBody(body, (id) => ctx.catalog.has(id));
    if (!parsed.ok) {
      send(res, 400, { error: parsed.error });
      return;
    }

    if (!ctx.limiter.allow(parsed.value.player_id)) {
      send(res, 429, { error: 'rate_limited' });
      return;
    }

    const result = upsertProfile(ctx.db, parsed.value);
    send(res, 200, result);
    return;
  }

  if (req.method === 'GET' && path === '/v1/profile') {
    const playerId = url.searchParams.get('player_id');
    if (!isUuidV4(playerId)) {
      send(res, 400, { error: 'invalid_player_id' });
      return;
    }
    const profile = getProfile(ctx.db, normalizePlayerId(playerId));
    if (!profile) {
      send(res, 404, { error: 'unknown_profile' });
      return;
    }
    send(res, 200, profile);
    return;
  }

  if (req.method === 'GET' && path.startsWith('/avatars/')) {
    const match = /^\/avatars\/([^/]+)\.png$/.exec(path);
    if (!match) {
      send(res, 404, { error: 'not_found' });
      return;
    }
    const id = match[1];
    if (!ctx.catalog.has(id)) {
      send(res, 404, { error: 'not_found' });
      return;
    }
    const filePath = ctx.catalog.pathFor(id);
    if (!filePath || !existsSync(filePath)) {
      send(res, 404, { error: 'not_found' });
      return;
    }
    try {
      sendPng(res, readFileSync(filePath));
    } catch {
      send(res, 404, { error: 'not_found' });
    }
    return;
  }

  send(res, 404, { error: 'not_found' });
}

export function createServer(options = {}) {
  const dbPath = options.dbPath ?? process.env.DB_PATH ?? ':memory:';
  const key = options.key ?? process.env.SQUISH_KEY ?? '';
  const db = openDb(dbPath);
  const limiter = options.limiter ?? createRateLimiter();
  const catalog = options.catalog ?? createCatalog({
    catalogPath: options.catalogPath,
    repoRoot: options.repoRoot,
  });
  const ctx = { db, key, limiter, store: storeLabel(dbPath), catalog };

  const server = http.createServer((req, res) => {
    handle(req, res, ctx).catch(() => {
      if (!res.headersSent) send(res, 400, { error: 'invalid_json' });
    });
  });

  server.once('close', () => {
    try {
      closeDb(db);
    } catch {
      // already closed
    }
  });

  return server;
}

export function start(options = {}) {
  const port = Number(options.port ?? process.env.PORT) || 8787;
  const server = createServer(options);
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '0.0.0.0', () => {
      resolve(server);
    });
  });
}

const isMain =
  Boolean(process.argv[1]) && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isMain) {
  start().then((server) => {
    const { port } = server.address();
    console.log(`squish leaderboard listening on ${port}`);
  });
}
