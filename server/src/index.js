import { timingSafeEqual } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { createCatalog } from './catalog.js';
import {
  closeDb,
  deleteProfile,
  deleteScore,
  getLeaderboard,
  getMe,
  getProfile,
  insertScore,
  listScores,
  openDb,
  resetAll,
  storeLabel,
  upsertProfile,
} from './db.js';
import { renderBoard } from './page.js';
import { isUuidV4, normalizePlayerId, parseLimit, parseProfileBody, parseScoreBody } from './validate.js';

const BODY_LIMIT = 4096;
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 30;
/** Per-IP write ceiling (D-046). Wider than per-player so two people on one NAT can each post. */
const IP_RATE_WINDOW_MS = 60_000;
const IP_RATE_MAX = 60;
const RESET_CONFIRM = 'RESET';

const PUBLIC_CORS_PATHS = new Set([
  '/',
  '/healthz',
  '/v1/scores',
  '/v1/leaderboard',
  '/v1/leaderboard/me',
  '/v1/profile',
]);

export function parseAllowedOrigins(raw) {
  const parts = Array.isArray(raw)
    ? raw
    : typeof raw === 'string'
      ? raw.split(',')
      : [];
  return parts
    .map((s) => (typeof s === 'string' ? s.trim() : ''))
    .filter((s) => s !== '' && s !== '*');
}

export function originAllowed(origin, allowed) {
  if (typeof origin !== 'string' || origin === '' || origin === '*') return false;
  if (!Array.isArray(allowed) || allowed.length === 0) return false;
  return allowed.includes(origin);
}

export function clientAddress(req, addressFor) {
  if (typeof addressFor === 'function') {
    const injected = addressFor(req);
    if (typeof injected === 'string' && injected !== '') return injected;
    return 'unknown';
  }
  const xff = req.headers['x-forwarded-for'];
  if (typeof xff === 'string') {
    const left = xff.split(',')[0].trim();
    if (left) return left;
  }
  const addr = req.socket && req.socket.remoteAddress;
  if (typeof addr === 'string' && addr !== '') return addr;
  return 'unknown';
}

function isPublicCorsPath(path) {
  return PUBLIC_CORS_PATHS.has(path) || path.startsWith('/avatars/');
}

function isAdminOptionsPath(path) {
  if (path === '/v1/admin/reset' || path.startsWith('/v1/admin/')) return true;
  if (/^\/v1\/scores\/[^/]+$/.test(path)) return true;
  if (/^\/v1\/profile\/[^/]+$/.test(path)) return true;
  return false;
}

function matchAdminRoute(method, path) {
  if (method === 'GET' && path === '/v1/admin/scores') {
    return { action: 'list_scores' };
  }
  if (method === 'DELETE') {
    const score = /^\/v1\/scores\/([^/]+)$/.exec(path);
    if (score) return { action: 'delete_score', id: score[1] };
    const profile = /^\/v1\/profile\/([^/]+)$/.exec(path);
    if (profile) return { action: 'delete_profile', playerId: profile[1] };
  }
  if (method === 'POST' && path === '/v1/admin/reset') {
    return { action: 'reset' };
  }
  return null;
}

function corsHeaders(req, allowedOrigins, { preflight = false } = {}) {
  const origin = req.headers.origin;
  if (!originAllowed(origin, allowedOrigins)) return {};
  const headers = {
    'access-control-allow-origin': origin,
    vary: 'Origin',
  };
  if (preflight) {
    headers['access-control-allow-methods'] = 'GET, POST, PUT';
    headers['access-control-allow-headers'] = 'Content-Type, X-Squish-Key';
  }
  return headers;
}

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

function send(res, status, body, extraHeaders = {}) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(payload),
    ...extraHeaders,
  });
  res.end(payload);
}

function sendHtml(res, status, html, extraHeaders = {}) {
  res.writeHead(status, {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store',
    'content-length': Buffer.byteLength(html),
    ...extraHeaders,
  });
  res.end(html);
}

function sendPng(res, data, extraHeaders = {}) {
  res.writeHead(200, {
    'content-type': 'image/png',
    'cache-control': 'public, max-age=86400',
    'content-length': data.length,
    ...extraHeaders,
  });
  res.end(data);
}

function sendEmpty(res, status, extraHeaders = {}) {
  res.writeHead(status, {
    'content-length': 0,
    ...extraHeaders,
  });
  res.end();
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

function allowWrite(req, ctx, playerId) {
  if (!ctx.limiter.allow(playerId)) return false;
  const addr = clientAddress(req, ctx.addressFor);
  return ctx.ipLimiter.allow(addr);
}

async function handleAdmin(req, res, ctx, route) {
  if (!ctx.adminKey) {
    send(res, 404, { error: 'not_found' });
    return;
  }
  if (!keysMatch(req.headers['x-squish-admin'], ctx.adminKey)) {
    send(res, 401, { error: 'unauthorized' });
    return;
  }

  if (route.action === 'delete_score') {
    const id = Number(route.id);
    if (!Number.isInteger(id) || id < 1 || String(id) !== route.id) {
      send(res, 404, { error: 'not_found' });
      return;
    }
    if (!deleteScore(ctx.db, id)) {
      send(res, 404, { error: 'not_found' });
      return;
    }
    send(res, 200, { ok: true });
    return;
  }

  if (route.action === 'delete_profile') {
    if (!isUuidV4(route.playerId)) {
      send(res, 400, { error: 'invalid_player_id' });
      return;
    }
    if (!deleteProfile(ctx.db, normalizePlayerId(route.playerId))) {
      send(res, 404, { error: 'not_found' });
      return;
    }
    send(res, 200, { ok: true });
    return;
  }

  if (route.action === 'list_scores') {
    const url = new URL(req.url, 'http://localhost');
    const playerIdRaw = url.searchParams.get('player_id');
    let playerId = null;
    if (playerIdRaw !== null) {
      if (!isUuidV4(playerIdRaw)) {
        send(res, 400, { error: 'invalid_player_id' });
        return;
      }
      playerId = normalizePlayerId(playerIdRaw);
    }
    const limit = parseLimit(url.searchParams.get('limit'));
    send(res, 200, listScores(ctx.db, { playerId, limit }));
    return;
  }

  if (route.action === 'reset') {
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

    if (
      body === null ||
      typeof body !== 'object' ||
      Array.isArray(body) ||
      body.confirm !== RESET_CONFIRM
    ) {
      send(res, 400, { error: 'confirmation_required' });
      return;
    }

    resetAll(ctx.db);
    send(res, 200, { ok: true });
  }
}

async function handle(req, res, ctx) {
  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;
  const admin = matchAdminRoute(req.method, path);

  if (req.method === 'OPTIONS') {
    if (isAdminOptionsPath(path)) {
      send(res, 404, { error: 'not_found' });
      return;
    }
    if (isPublicCorsPath(path)) {
      sendEmpty(res, 204, corsHeaders(req, ctx.allowedOrigins, { preflight: true }));
      return;
    }
    send(res, 404, { error: 'not_found' });
    return;
  }

  if (admin) {
    await handleAdmin(req, res, ctx, admin);
    return;
  }

  const cors = corsHeaders(req, ctx.allowedOrigins);

  if (req.method === 'GET' && path === '/') {
    sendHtml(res, 200, renderBoard(getLeaderboard(ctx.db, 10)), cors);
    return;
  }

  if (req.method === 'GET' && path === '/healthz') {
    send(res, 200, { ok: true, store: ctx.store }, cors);
    return;
  }

  if (req.method === 'POST' && path === '/v1/scores') {
    if (!keysMatch(req.headers['x-squish-key'], ctx.key)) {
      send(res, 401, { error: 'unauthorized' }, cors);
      return;
    }

    let raw;
    try {
      raw = await readBody(req);
    } catch (err) {
      if (err.code === 'body_too_large') {
        send(res, 400, { error: 'body_too_large' }, cors);
        return;
      }
      send(res, 400, { error: 'invalid_json' }, cors);
      return;
    }

    let body;
    try {
      body = JSON.parse(raw.toString('utf8'));
    } catch {
      send(res, 400, { error: 'invalid_json' }, cors);
      return;
    }

    const parsed = parseScoreBody(body);
    if (!parsed.ok) {
      send(res, 400, { error: parsed.error }, cors);
      return;
    }

    if (!allowWrite(req, ctx, parsed.value.player_id)) {
      send(res, 429, { error: 'rate_limited' }, cors);
      return;
    }

    const result = insertScore(ctx.db, parsed.value);
    send(res, 201, result, cors);
    return;
  }

  if (req.method === 'GET' && path === '/v1/leaderboard') {
    const limit = parseLimit(url.searchParams.get('limit'));
    send(res, 200, getLeaderboard(ctx.db, limit), cors);
    return;
  }

  if (req.method === 'GET' && path === '/v1/leaderboard/me') {
    const playerId = url.searchParams.get('player_id');
    if (!isUuidV4(playerId)) {
      send(res, 400, { error: 'invalid_player_id' }, cors);
      return;
    }
    const me = getMe(ctx.db, normalizePlayerId(playerId));
    if (!me) {
      send(res, 404, { error: 'unknown_player' }, cors);
      return;
    }
    send(res, 200, me, cors);
    return;
  }

  if (req.method === 'PUT' && path === '/v1/profile') {
    if (!keysMatch(req.headers['x-squish-key'], ctx.key)) {
      send(res, 401, { error: 'unauthorized' }, cors);
      return;
    }

    let raw;
    try {
      raw = await readBody(req);
    } catch (err) {
      if (err.code === 'body_too_large') {
        send(res, 400, { error: 'body_too_large' }, cors);
        return;
      }
      send(res, 400, { error: 'invalid_json' }, cors);
      return;
    }

    let body;
    try {
      body = JSON.parse(raw.toString('utf8'));
    } catch {
      send(res, 400, { error: 'invalid_json' }, cors);
      return;
    }

    const parsed = parseProfileBody(body, (id) => ctx.catalog.has(id));
    if (!parsed.ok) {
      send(res, 400, { error: parsed.error }, cors);
      return;
    }

    if (!allowWrite(req, ctx, parsed.value.player_id)) {
      send(res, 429, { error: 'rate_limited' }, cors);
      return;
    }

    const result = upsertProfile(ctx.db, parsed.value);
    send(res, 200, result, cors);
    return;
  }

  if (req.method === 'GET' && path === '/v1/profile') {
    const playerId = url.searchParams.get('player_id');
    if (!isUuidV4(playerId)) {
      send(res, 400, { error: 'invalid_player_id' }, cors);
      return;
    }
    const profile = getProfile(ctx.db, normalizePlayerId(playerId));
    if (!profile) {
      send(res, 404, { error: 'unknown_profile' }, cors);
      return;
    }
    send(res, 200, profile, cors);
    return;
  }

  if (req.method === 'GET' && path.startsWith('/avatars/')) {
    const match = /^\/avatars\/([^/]+)\.png$/.exec(path);
    if (!match) {
      send(res, 404, { error: 'not_found' }, cors);
      return;
    }
    const id = match[1];
    if (!ctx.catalog.has(id)) {
      send(res, 404, { error: 'not_found' }, cors);
      return;
    }
    const filePath = ctx.catalog.pathFor(id);
    if (!filePath || !existsSync(filePath)) {
      send(res, 404, { error: 'not_found' }, cors);
      return;
    }
    try {
      sendPng(res, readFileSync(filePath), cors);
    } catch {
      send(res, 404, { error: 'not_found' }, cors);
    }
    return;
  }

  send(res, 404, { error: 'not_found' }, cors);
}

export function createServer(options = {}) {
  const dbPath = options.dbPath ?? process.env.DB_PATH ?? ':memory:';
  const key = options.key ?? process.env.SQUISH_KEY ?? '';
  const adminKey = options.adminKey ?? process.env.SQUISH_ADMIN_KEY ?? '';
  const allowedOrigins = parseAllowedOrigins(
    options.allowedOrigins ?? process.env.SQUISH_ALLOWED_ORIGINS,
  );
  const db = openDb(dbPath);
  const limiter = options.limiter ?? createRateLimiter();
  const ipLimiter = options.ipLimiter ?? createRateLimiter({
    windowMs: IP_RATE_WINDOW_MS,
    max: IP_RATE_MAX,
  });
  const catalog = options.catalog ?? createCatalog({
    catalogPath: options.catalogPath,
    repoRoot: options.repoRoot,
  });
  const ctx = {
    db,
    key,
    adminKey,
    allowedOrigins,
    limiter,
    ipLimiter,
    addressFor: options.addressFor,
    store: storeLabel(dbPath),
    catalog,
  };

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
