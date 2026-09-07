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

export function parseLimit(raw, fallback = 10) {
  if (raw === undefined || raw === null || raw === '') return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(50, Math.max(1, Math.trunc(n)));
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
