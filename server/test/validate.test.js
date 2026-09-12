import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { parseLimit, parseProfileBody, parseScoreBody, sanitizeName } from '../src/validate.js';

const ID = '11111111-1111-4111-8111-111111111111';

describe('sanitizeName', () => {
  it('trims and collapses whitespace', () => {
    assert.equal(sanitizeName('  Ann   Marie  '), 'Ann Marie');
  });

  it('strips zero-width characters', () => {
    assert.equal(sanitizeName('Na\u200Btas\uFEFFha'), 'Natasha');
  });

  it('clamps to 16 characters, not bytes', () => {
    assert.equal(sanitizeName('😀'.repeat(20)), '😀'.repeat(16));
  });

  it('rejects empty after stripping controls', () => {
    assert.equal(sanitizeName('\u0001\u0002'), '');
  });
});

describe('parseScoreBody', () => {
  const good = { player_id: ID, name: 'Natasha', score: 4800, client: 'squish/1.0' };

  it('accepts a valid body and lowercases the uuid', () => {
    const parsed = parseScoreBody({ ...good, player_id: ID.toUpperCase() });
    assert.equal(parsed.ok, true);
    assert.equal(parsed.value.player_id, ID);
  });

  it('rejects a non-v4 uuid', () => {
    const parsed = parseScoreBody({ ...good, player_id: '11111111-1111-1111-8111-111111111111' });
    assert.equal(parsed.ok, false);
    assert.equal(parsed.error, 'invalid_player_id');
  });

  it('rejects an empty name', () => {
    assert.equal(parseScoreBody({ ...good, name: '   ' }).error, 'invalid_name');
  });

  it('rejects a name that contains control characters', () => {
    assert.equal(parseScoreBody({ ...good, name: 'Nat\u0001asha' }).error, 'invalid_name');
  });

  it('rejects a negative or float score', () => {
    assert.equal(parseScoreBody({ ...good, score: -1 }).error, 'invalid_score');
    assert.equal(parseScoreBody({ ...good, score: 1.5 }).error, 'invalid_score');
  });
});

describe('parseProfileBody', () => {
  const known = (id) => id === 'bear_bounce';
  const good = {
    player_id: ID,
    name: 'Natasha',
    avatar: 'bear_bounce',
    client: 'squish/1.0',
  };

  it('accepts a valid body, empty avatar, and lowercases the uuid', () => {
    const parsed = parseProfileBody({ ...good, player_id: ID.toUpperCase() }, known);
    assert.equal(parsed.ok, true);
    assert.equal(parsed.value.player_id, ID);
    assert.equal(parsed.value.avatar, 'bear_bounce');

    const empty = parseProfileBody({ ...good, avatar: '' }, () => false);
    assert.equal(empty.ok, true);
    assert.equal(empty.value.avatar, '');
  });

  it('rejects a bad uuid, empty name, unknown avatar, and bad client', () => {
    assert.equal(parseProfileBody({ ...good, player_id: 'nope' }, known).error, 'invalid_player_id');
    assert.equal(parseProfileBody({ ...good, name: '   ' }, known).error, 'invalid_name');
    assert.equal(parseProfileBody({ ...good, name: 'Nat\u0001asha' }, known).error, 'invalid_name');
    assert.equal(parseProfileBody({ ...good, avatar: 'not_a_squishy' }, known).error, 'invalid_avatar');
    assert.equal(parseProfileBody({ ...good, avatar: 1 }, known).error, 'invalid_avatar');
    assert.equal(parseProfileBody({ ...good, client: 'nope' }, known).error, 'invalid_client');
  });
});

describe('parseLimit', () => {
  it('defaults to 10 and clamps to 1..50', () => {
    assert.equal(parseLimit(undefined), 10);
    assert.equal(parseLimit('abc'), 10);
    assert.equal(parseLimit('0'), 1);
    assert.equal(parseLimit('100'), 50);
    assert.equal(parseLimit('5'), 5);
  });
});
