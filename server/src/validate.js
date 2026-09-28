const UUID_V4 =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CLIENT = /^squish\/.+$/;
const MAX_SCORE = 9_999_999;

export function isUuidV4(value) {
  return typeof value === 'string' && UUID_V4.test(value);
}

export function normalizePlayerId(value) {
  return String(value).toLowerCase();
}

/** Trim, strip controls/zero-width, collapse whitespace, clamp to 16 characters. */
export function sanitizeName(raw) {
  if (typeof raw !== 'string') return '';
  const stripped = raw.replace(/[\p{Cc}\p{Cf}]/gu, '');
  const collapsed = stripped.trim().replace(/\s+/g, ' ');
  return [...collapsed].slice(0, 16).join('');
}

/**
 * Identity key for a name: sanitizeName, then Unicode case fold.
 * "Natasha", "natasha" and "  NATASHA" share one key. Locale-independent.
 */
export function nameKey(raw) {
  return sanitizeName(raw).toLowerCase();
}

export function parseLimit(raw, fallback = 10) {
  if (raw === undefined || raw === null || raw === '') return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(50, Math.max(1, Math.trunc(n)));
}

/**
 * Page start for GET /v1/admin/scores (D-060). Omitted means the first page.
 * Present values must be a canonical integer ≥ 0; floats, signs, and junk are
 * invalid so a bad offset cannot silently clamp onto a real page.
 */
export function parseOffset(raw) {
  if (raw === undefined || raw === null) return { ok: true, value: 0 };
  if (typeof raw !== 'string' || !/^(0|[1-9][0-9]*)$/.test(raw)) {
    return { ok: false, error: 'invalid_offset' };
  }
  const n = Number(raw);
  if (!Number.isSafeInteger(n)) return { ok: false, error: 'invalid_offset' };
  return { ok: true, value: n };
}

export function parseScoreBody(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, error: 'invalid_json' };
  }
  if (!isUuidV4(body.player_id)) {
    return { ok: false, error: 'invalid_player_id' };
  }
  if (typeof body.name === 'string' && /[\p{Cc}]/u.test(body.name)) {
    return { ok: false, error: 'invalid_name' };
  }
  const name = sanitizeName(body.name);
  if (!name) {
    return { ok: false, error: 'invalid_name' };
  }
  if (!Number.isInteger(body.score) || body.score < 0 || body.score > MAX_SCORE) {
    return { ok: false, error: 'invalid_score' };
  }
  if (typeof body.client !== 'string' || !CLIENT.test(body.client)) {
    return { ok: false, error: 'invalid_client' };
  }
  return {
    ok: true,
    value: {
      player_id: normalizePlayerId(body.player_id),
      name,
      score: body.score,
      client: body.client,
    },
  };
}

/**
 * Same sanitise-then-validate shape as parseScoreBody (D-026).
 * `isKnownAvatar` is the catalog whitelist; only "" bypasses it.
 */
export function parseProfileBody(body, isKnownAvatar = () => false) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, error: 'invalid_json' };
  }
  if (!isUuidV4(body.player_id)) {
    return { ok: false, error: 'invalid_player_id' };
  }
  if (typeof body.name === 'string' && /[\p{Cc}]/u.test(body.name)) {
    return { ok: false, error: 'invalid_name' };
  }
  const name = sanitizeName(body.name);
  if (!name) {
    return { ok: false, error: 'invalid_name' };
  }
  if (typeof body.avatar !== 'string') {
    return { ok: false, error: 'invalid_avatar' };
  }
  if (body.avatar !== '' && !isKnownAvatar(body.avatar)) {
    return { ok: false, error: 'invalid_avatar' };
  }
  if (typeof body.client !== 'string' || !CLIENT.test(body.client)) {
    return { ok: false, error: 'invalid_client' };
  }
  return {
    ok: true,
    value: {
      player_id: normalizePlayerId(body.player_id),
      name,
      avatar: body.avatar,
      client: body.client,
    },
  };
}

/**
 * Resolve or claim a name (D-053). Unauthenticated today.
 * `secret` is optional and unused so a later password can occupy the same field.
 */
export function parseResolveBody(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, error: 'invalid_json' };
  }
  if (typeof body.name === 'string' && /[\p{Cc}]/u.test(body.name)) {
    return { ok: false, error: 'invalid_name' };
  }
  const name = sanitizeName(body.name);
  if (!name) {
    return { ok: false, error: 'invalid_name' };
  }
  if (Object.prototype.hasOwnProperty.call(body, 'secret')) {
    if (typeof body.secret !== 'string') {
      return { ok: false, error: 'invalid_secret' };
    }
  }
  return {
    ok: true,
    value: {
      name,
      secret: typeof body.secret === 'string' ? body.secret : '',
    },
  };
}

/**
 * Query `name` for GET /v1/players/lookup (D-059). Same accept/reject rules as
 * parseResolveBody's name: a control character is invalid, and so is empty
 * after sanitising. A missing query value is invalid too.
 */
export function parseLookupName(raw) {
  if (typeof raw !== 'string') {
    return { ok: false, error: 'invalid_name' };
  }
  if (/[\p{Cc}]/u.test(raw)) {
    return { ok: false, error: 'invalid_name' };
  }
  const name = sanitizeName(raw);
  if (!name) {
    return { ok: false, error: 'invalid_name' };
  }
  return { ok: true, value: { name } };
}

/** Admin merge. `keep` survives; `drop` is absorbed. Ids are inputs, never implied. */
export function parseMergeBody(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, error: 'invalid_json' };
  }
  if (!isUuidV4(body.keep) || !isUuidV4(body.drop)) {
    return { ok: false, error: 'invalid_player_id' };
  }
  const keep = normalizePlayerId(body.keep);
  const drop = normalizePlayerId(body.drop);
  if (keep === drop) {
    return { ok: false, error: 'same_player' };
  }
  return { ok: true, value: { keep, drop } };
}
